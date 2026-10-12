#!/usr/bin/env python3
"""Validate a frozen release candidate without changing tags or remote state."""
import datetime
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.error
import urllib.request


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def api(path, missing_ok=False, data=None, method=None):
    request = urllib.request.Request(
        "https://api.github.com/" + path,
        headers={"Authorization": "Bearer " + os.environ["GH_TOKEN"],
                 "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28",
                 "Content-Type": "application/json"},
        data=json.dumps(data).encode() if data is not None else None, method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        if missing_ok and error.code == 404:
            return None
        raise RuntimeError(f"GitHub API failed with HTTP {error.code}") from None


def release_for_tag(repo, tag):
    # The tag endpoint excludes drafts. List authenticated releases instead.
    for page in range(1, 101):
        releases = api(f"repos/{repo}/releases?per_page=100&page={page}")
        matches = [release for release in releases if release["tag_name"] == tag]
        if matches:
            return matches[0]
        if len(releases) < 100:
            return None
    raise ValueError("Could not finish checking release history")


def check_appcast_build(repo, build):
    import base64
    import xml.etree.ElementTree as ET
    current = api(f"repos/{repo}/contents/appcast.xml?ref=main")
    root = ET.fromstring(base64.b64decode(current["content"]))
    versions = [int(item.text) for item in root.findall("./channel/item/{http://www.andymatuschak.org/xml-namespaces/sparkle}version")]
    if not versions or build <= max(versions):
        raise ValueError("BUILD_NUMBER must exceed every published Sparkle build")


def notes_for(changelog, version):
    headings = list(re.finditer(r"^## (.+)$", changelog, re.M))
    matching = [(i, heading) for i, heading in enumerate(headings)
                if re.fullmatch(re.escape(version) + r" - \d{4}-\d{2}-\d{2}", heading[1])]
    if len(matching) != 1:
        raise ValueError("Expected exactly one dated changelog section for " + version)
    index, heading = matching[0]
    date = datetime.date.fromisoformat(heading[1].rsplit(" - ", 1)[1])
    if date > datetime.datetime.now(datetime.timezone.utc).date():
        raise ValueError("Release date is in the future")
    end = headings[index + 1].start() if index + 1 < len(headings) else len(changelog)
    section = changelog[heading.start():end].rstrip() + "\n"
    if not changelog[heading.end():end].strip():
        raise ValueError("Release notes are empty")
    return section


def metadata():
    package = json.loads(Path("package.json").read_text())
    version = package["version"]
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Only stable semantic versions are supported")
    if package.get("private") is not True:
        raise ValueError("Reassess npm publishing before removing private: true")
    if Path("version.env").exists():
        values = dict(line.split("=", 1) for line in Path("version.env").read_text().splitlines() if "=" in line)
        if values["MARKETING_VERSION"] != version or not re.fullmatch(r"[1-9][0-9]*", values["BUILD_NUMBER"]):
            raise ValueError("version.env and package.json must agree; build number must be positive")
    else:
        lock = json.loads(Path("package-lock.json").read_text())
        if lock["version"] != version or lock["packages"][""]["version"] != version:
            raise ValueError("package-lock.json version mismatch")
    return version


def main():
    version = metadata()
    notes = notes_for(Path("CHANGELOG.md").read_text(), version)
    dry = os.environ.get("DRY_RUN", "true") == "true"
    tag = os.environ.get("RELEASE_TAG", "")
    commit = git("rev-parse", "HEAD")
    if os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch" and os.environ["GITHUB_REF"] != "refs/heads/main":
        raise ValueError("Dispatch the workflow from protected main")
    git("merge-base", "--is-ancestor", commit, "origin/main")
    tag_object = ""
    if tag:
        if tag != "v" + version:
            raise ValueError("Tag and version metadata disagree")
        if git("cat-file", "-t", tag) != "tag":
            raise ValueError("An annotated, signed tag is required")
        tag_object = git("rev-parse", tag)
        if git("rev-parse", tag + "^{commit}") != commit:
            raise ValueError("Tag does not name the checked-out commit")
        signers = Path(os.environ["RUNNER_TEMP"]) / "release-signers"
        signers.write_text(git("show", "origin/main:.github/release-signers") + "\n")
        git("-c", "gpg.format=ssh", "-c", "gpg.ssh.allowedSignersFile=" + str(signers), "verify-tag", tag)
    elif not dry:
        raise ValueError("Publishing requires an existing signed annotated tag")
    repo = os.environ["GITHUB_REPOSITORY"]
    runs = api(f"repos/{repo}/actions/workflows/ci.yml/runs?event=push&head_sha={commit}&per_page=100")["workflow_runs"]
    if not any(run["head_sha"] == commit and run["head_branch"] == "main" and run["conclusion"] == "success" for run in runs):
        raise ValueError("Successful push CI on this exact main commit is required")
    if not dry and release_for_tag(repo, tag) is not None:
        raise ValueError("This version already has a release; never republish it")
    build = int(dict(line.split("=", 1) for line in Path("version.env").read_text().splitlines() if "=" in line)["BUILD_NUMBER"])
    if not dry:
        check_appcast_build(repo, build)
    out = Path("release")
    out.mkdir(exist_ok=True)
    (out / "RELEASE-NOTES.md").write_text(notes)
    (out / "release.json").write_text(json.dumps({"version": version, "commit": commit, "tag": tag,
                                                "tag_object": tag_object, "dry_run": dry, "build": build}) + "\n")
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"version={version}\ncommit={commit}\ntag_object={tag_object}\n")


if __name__ == "__main__":
    main()
