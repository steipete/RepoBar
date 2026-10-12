#!/usr/bin/env python3
"""Update the existing Sparkle feed and Homebrew cask after publication."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET


def api(path, data=None):
    req = urllib.request.Request('https://api.github.com/' + path,
        headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
                 'Accept': 'application/vnd.github+json'},
        data=json.dumps(data).encode() if data is not None else None,
        method='PUT' if data is not None else 'GET')
    with urllib.request.urlopen(req, timeout=60) as response:
        return json.load(response)


def main():
    meta = json.loads(Path('release/release.json').read_text())
    if meta['dry_run']:
        raise ValueError('No handoffs during a dry run')
    version = meta['version']
    if sys.argv[1] == 'appcast':
        path = 'repos/steipete/RepoBar/contents/appcast.xml'
        current = api(path + '?ref=main')
        ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
        ET.register_namespace('sparkle', ns[1:-1])
        tree = ET.fromstring(base64.b64decode(current['content']))
        channel = tree.find('channel')
        generated = ET.parse('release/appcast.xml')
        target = [item for item in generated.findall('./channel/item') if item.findtext(ns + 'shortVersionString') == version]
        if len(target) != 1:
            raise ValueError('Expected one verified appcast item')
        items = list(channel.findall('item'))
        build = int(target[0].findtext(ns + 'version'))
        if any(int(item.findtext(ns + 'version')) >= build for item in items):
            raise ValueError('Appcast already contains this or a newer build')
        channel.insert(list(channel).index(items[0]) if items else len(channel), target[0])
        content = ET.tostring(tree, encoding='utf-8', xml_declaration=True)
        message = f'chore: update Sparkle feed for v{version}'
    elif sys.argv[1] == 'homebrew':
        path = 'repos/steipete/homebrew-tap/contents/Casks/repobar.rb'
        current = api(path + '?ref=main')
        content = base64.b64decode(current['content']).decode()
        old = re.search(r'^  version "([0-9.]+)"$', content, re.M)
        if old is None or tuple(map(int, old[1].split('.'))) >= tuple(map(int, version.split('.'))):
            raise ValueError('Cask already contains this or a newer version')
        archive = Path(f'release/RepoBar-{version}.zip')
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        content, count = re.subn(r'^  version "[0-9.]+"$', f'  version "{version}"', content, flags=re.M)
        if count != 1:
            raise ValueError('Unexpected cask version syntax')
        content, count = re.subn(r'^  sha256 "[0-9a-f]{64}"$', f'  sha256 "{digest}"', content, flags=re.M)
        if count != 1:
            raise ValueError('Unexpected cask checksum syntax')
        content = content.encode()
        message = f'chore: update RepoBar cask to {version}'
    else:
        raise ValueError('Unknown handoff')
    api(path, {'message': message, 'sha': current['sha'], 'branch': 'main',
               'content': base64.b64encode(content).decode()})
    if base64.b64decode(api(path + '?ref=main')['content']) != content:
        raise ValueError('Handoff readback mismatch')


if __name__ == '__main__':
    main()
