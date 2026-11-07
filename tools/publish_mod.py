#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Publish an already validated tagged package to Factorio; safe to retry the same bytes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

from package_mod import REPO
from release_metadata import version_parts
from validate_package import validate

PORTAL = 'https://mods.factorio.com'


def request_json(url, fields=None, archive=None, token=None, field='file', content_type='application/zip'):
    """GET, or POST multipart fields and an optional file (`archive`, sent as `field`); returns the JSON reply."""
    headers, body = {}, None
    if fields is not None:
        boundary = uuid.uuid4().hex
        sections = []
        for key, value in fields.items():
            sections.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"\r\n\r\n{value}\r\n'.encode())
        if archive is not None:
            sections.append((f'--{boundary}\r\nContent-Disposition: form-data; name="{field}"; '
                             f'filename="{archive.name}"\r\nContent-Type: {content_type}\r\n\r\n').encode())
            sections.extend([archive.read_bytes(), b'\r\n'])
        sections.append(f'--{boundary}--\r\n'.encode())
        body = b''.join(sections)
        headers['Content-Type'] = 'multipart/form-data; boundary=' + boundary
    if token is not None:
        headers['Authorization'] = 'Bearer ' + token
    request = urllib.request.Request(url, data=body, headers=headers)
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def listing(name):
    # The portal's CDN caches this reply for 15 minutes, so the read before uploading would hide the new release from
    # verification. A query string the cache has never seen always reaches the portal.
    try:
        return request_json(PORTAL + '/api/mods/' + urllib.parse.quote(name, safe='') + '?fresh=' + uuid.uuid4().hex)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise


def published(mod, info, archive):
    for release in (mod or {}).get('releases', []):
        if release['version'] == info['version']:
            if release['file_name'] != archive.name or release['sha1'] != hashlib.sha1(archive.read_bytes()).hexdigest():
                raise ValueError('This portal version already has different package bytes')
            return True
    return False


def publish(output, tag, token, license_id=None, root=REPO):
    info, archive = validate(output, tag, root)
    if not token:
        raise ValueError('Connect FACTORIO_API_KEY before publishing to the portal')
    mod = listing(info['name'])
    if published(mod, info, archive):
        print('The portal already has this exact package')
        return
    if any(version_parts(item['version']) > version_parts(info['version']) for item in (mod or {}).get('releases', [])):
        raise ValueError('A newer version is already published on the portal')
    endpoint, fields = '/api/v2/mods/releases/init_upload', {}
    if mod is None:
        # Custom licence IDs are the code at the end of the portal's licence edit page, such as custom_6aee33da2a59c98152d81dc1.
        if not isinstance(license_id, str) or not re.fullmatch(r'custom_[0-9A-Za-z]+', license_id):
            raise ValueError('First publication needs FACTORIO_LICENSE_ID for the mixed-licence package')
        endpoint = '/api/v2/mods/init_publish'
        fields = {'license': license_id, 'category': 'content',
                  'description': info['description'] + '\n\nSee the source repository and NOTICE for licence terms.',
                  'source_url': 'https://github.com/jatmn/jatz-distribution'}
    initialized = request_json(PORTAL + endpoint, {'mod': info['name']}, token=token)
    url = initialized.get('upload_url', '')
    parsed = urllib.parse.urlparse(url)
    if initialized.get('error') or parsed.scheme != 'https' or not parsed.netloc or parsed.username or parsed.password:
        raise ValueError('The portal did not provide a valid HTTPS upload destination')
    # The upload URL carries its own authorization. Never forward the API key or log the URL.
    result = request_json(url, fields, archive=archive)
    if result.get('success') is not True:
        raise ValueError('The portal rejected the package; retry the same tag after checking its state')
    deadline = time.monotonic() + 60
    while True:
        if published(listing(info['name']), info, archive):
            print('Verified portal publication of ' + archive.name)
            return
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ValueError('Portal verification is pending; retry the same tag, without changing its bytes')
        time.sleep(min(5, remaining))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=REPO / 'dist')
    parser.add_argument('--tag', required=True)
    args = parser.parse_args()
    try:
        publish(args.output, args.tag, os.environ.get('FACTORIO_API_KEY'), os.environ.get('FACTORIO_LICENSE_ID'))
    except urllib.error.HTTPError as error:
        raise SystemExit(f'Factorio HTTP {error.code}; verify credentials and retry the same tag') from None
    except (urllib.error.URLError, TimeoutError):
        raise SystemExit('Factorio connection failed; check the portal before retrying the same tag') from None
