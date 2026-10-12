#!/usr/bin/env python3
"""Publish verified immutable artifacts, refusing existing release versions."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.parse
import urllib.request
import importlib.util

spec = importlib.util.spec_from_file_location("validator", Path(__file__).with_name("validate-release.py"))
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def main():
    directory = Path("release")
    metadata = json.loads((directory / "release.json").read_text())
    if metadata["dry_run"] or metadata["commit"] != os.environ["RELEASE_COMMIT"]:
        raise ValueError("Publication is not authorized for this artifact")
    tag = metadata["tag"]
    repo = os.environ["GITHUB_REPOSITORY"]
    def unchanged_tag():
        remote = subprocess.check_output(["git", "ls-remote", "origin", "refs/tags/" + tag], text=True).split()
        if len(remote) != 2 or remote[0] != metadata["tag_object"]:
            raise ValueError("Release tag moved or disappeared")
    unchanged_tag()
    if validator.release_for_tag(repo, tag) is not None:
        raise ValueError("A release already exists for this version")
    manifest = (directory / "SHA256SUMS").read_text().splitlines()
    expected = {}
    for line in manifest:
        digest, name = line.split("  ")
        if Path(name).name != name or name in expected:
            raise ValueError("Invalid checksum manifest")
        if hashlib.sha256((directory / name).read_bytes()).hexdigest() != digest:
            raise ValueError("Artifact checksum mismatch: " + name)
        expected[name] = digest
    names = set(expected) | {"SHA256SUMS"}
    if names != {path.name for path in directory.iterdir()}:
        raise ValueError("Unexpected artifact set")
    validator.check_appcast_build(repo, metadata["build"])
    notes = (directory / "RELEASE-NOTES.md").read_text()
    created = validator.api(f"repos/{repo}/releases", data={
        "tag_name": tag, "target_commitish": metadata["commit"], "draft": True,
        "name": repo.split("/")[1] + " " + tag, "body": notes,
    })
    release_path = f"repos/{repo}/releases/{created['id']}"
    upload_url = created["upload_url"].split("{", 1)[0]
    if urllib.parse.urlsplit(upload_url).hostname != "uploads.github.com":
        raise ValueError("Unexpected GitHub upload host")
    for name in sorted(names):
        request = urllib.request.Request(upload_url + "?" + urllib.parse.urlencode({"name": name}),
            data=(directory / name).read_bytes(), method="POST",
            headers={"Authorization": "Bearer " + os.environ["GH_TOKEN"], "Content-Type": "application/octet-stream"})
        with urllib.request.urlopen(request, timeout=300) as response:
            asset = json.load(response)
        if asset["state"] != "uploaded" or asset["size"] != (directory / name).stat().st_size:
            raise ValueError("GitHub upload is incomplete")
    release = validator.api(release_path)
    if not release["draft"] or {asset["name"] for asset in release["assets"]} != names:
        raise ValueError("Draft asset inventory mismatch")
    if release["body"].replace("\r\n", "\n").strip() != (directory / "RELEASE-NOTES.md").read_text().strip():
        raise ValueError("Draft notes differ from validated changelog")
    downloaded = Path(os.environ["RUNNER_TEMP"]) / "release-download"
    downloaded.mkdir()
    class DownloadRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, request, fp, code, msg, headers, newurl):
            redirected = super().redirect_request(request, fp, code, msg, headers, newurl)
            if redirected is not None and urllib.parse.urlsplit(newurl).hostname != "api.github.com":
                redirected.remove_header("Authorization")
            return redirected
    opener = urllib.request.build_opener(DownloadRedirect)
    for asset in release["assets"]:
        request = urllib.request.Request(asset["url"], headers={
            "Authorization": "Bearer " + os.environ["GH_TOKEN"], "Accept": "application/octet-stream"})
        with opener.open(request, timeout=300) as response:
            (downloaded / asset["name"]).write_bytes(response.read())
    for name in names:
        if (downloaded / name).read_bytes() != (directory / name).read_bytes():
            raise ValueError("Draft download differs: " + name)
    unchanged_tag()
    validator.api(release_path, data={"draft": False}, method="PATCH")
    if validator.api(release_path)["draft"]:
        raise ValueError("Release is still a draft")


if __name__ == "__main__":
    main()
