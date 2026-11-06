#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Check the Factorio Mod Portal page in portal/, and bring the live page in line with it.

The page is portal/summary.txt (the short summary), portal/description.md (the long
description, Markdown) and the screenshots in portal/gallery/ (the gallery, in filename
order). Relative links in the description point into this repository, so it previews on
GitHub; for the portal they become absolute GitHub URLs pinned to the release tag.

--check                 validate portal/ (CI): needs no network.
--tag vX.Y.Z --dry-run  print what a sync would change on the live page; needs no API key.
--tag vX.Y.Z            change what differs, after that release is published
                        (FACTORIO_API_KEY with the ModPortal: Edit Mods permission).
"""
import argparse
import hashlib
import json
import os
from pathlib import PurePosixPath
import re
import subprocess
import urllib.error
import urllib.parse

from package_mod import REPO
from publish_mod import PORTAL, request_json
from release_metadata import version_parts

SOURCE = 'jatmn/jatz-distribution'
SUMMARY_LIMIT = 500  # the portal's limit (Mod details API)
# The portal documents no gallery limits; this is the project's guard (large PNGs have failed to upload).
IMAGE_LIMIT = 5 * 1024 * 1024
IMAGE_TYPES = {'.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg'}
# Linked from the description: served raw, so the portal shows the picture rather than GitHub's page.
PICTURES = {'.png', '.jpg', '.jpeg', '.gif', '.webp'}
LINK = re.compile(r'\]\(([^()\s]+)(\s+"[^"]*")?\)')
REFERENCE = re.compile(r'^ {0,3}\[[^\]]+\]:', re.MULTILINE)
SCHEME = re.compile(r'[A-Za-z][A-Za-z0-9+.-]*:')
TAG = re.compile(r'v[0-9]+\.[0-9]+\.[0-9]+')


def tracked_files(root=REPO):
    listed = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z'])
    return {os.fsdecode(name) for name in listed.split(b'\0') if name}


def portal_url(target, ref, root, tracked, problems):
    """The absolute URL a relative link in portal/description.md stands for."""
    if SCHEME.match(target) or target.startswith('#'):
        return target
    path, _, fragment = target.partition('#')
    if path.startswith('/') or '?' in path:
        problems.append(f'Link {target!r}: use a path relative to portal/')
        return target
    resolved = (root / 'portal' / urllib.parse.unquote(path)).resolve()
    try:
        relative = resolved.relative_to(root.resolve()).as_posix()
    except ValueError:
        problems.append(f'Link {target!r} points outside the repository')
        return target
    directory = resolved.is_dir()
    if not directory and not resolved.is_file():
        problems.append(f'Link {target!r}: {relative} does not exist')
    elif tracked is not None and not directory and relative not in tracked:
        problems.append(f'Link {target!r}: {relative} is not committed, so GitHub will not serve it')
    quoted = urllib.parse.quote(relative)
    if PurePosixPath(relative).suffix.lower() in PICTURES:
        return f'https://raw.githubusercontent.com/{SOURCE}/{ref}/{quoted}'
    kind = 'tree' if directory else 'blob'
    return f'https://github.com/{SOURCE}/{kind}/{ref}/{quoted}' + ('#' + fragment if fragment else '')


def render(ref, root=REPO, tracked=None):
    """The page as the portal gets it: summary, description with pinned links, and gallery files."""
    portal, problems = root / 'portal', []
    summary = (portal / 'summary.txt').read_text(encoding='utf-8').strip()
    if not summary:
        problems.append('portal/summary.txt is empty')
    if len(summary) > SUMMARY_LIMIT:
        problems.append(f'portal/summary.txt has {len(summary)} characters; the portal allows {SUMMARY_LIMIT}')
    source = (portal / 'description.md').read_text(encoding='utf-8').strip()
    if not source:
        problems.append('portal/description.md is empty')
    if REFERENCE.search(source):
        problems.append('portal/description.md: use inline links; reference-style links are not rewritten')
    if source.count('](') != len(LINK.findall(source)):
        problems.append('portal/description.md: a link target has spaces or brackets; it would not be rewritten')
    description = LINK.sub(lambda match: '](' + portal_url(match.group(1), ref, root, tracked, problems)
                           + (match.group(2) or '') + ')', source)
    gallery = sorted((portal / 'gallery').iterdir()) if (portal / 'gallery').is_dir() else []
    for path in gallery:
        name = 'portal/gallery/' + path.name
        if not path.is_file() or path.suffix.lower() not in IMAGE_TYPES:
            problems.append(f'{name}: the gallery takes only PNG and JPEG images')
        elif path.stat().st_size > IMAGE_LIMIT:
            problems.append(f'{name} is over {IMAGE_LIMIT // 1024 // 1024} MiB')
        elif tracked is not None and name not in tracked:
            problems.append(f'{name} is not committed')
    if problems:
        raise ValueError('\n'.join(problems))
    return {'summary': summary, 'description': description, 'gallery': gallery}


def full_listing(name):
    try:
        return request_json(PORTAL + '/api/mods/' + urllib.parse.quote(name, safe='') + '/full')
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise


def same_text(a, b):
    """Equal apart from line endings and trailing whitespace, which the portal may change."""
    def lines(text):
        return [line.rstrip() for line in (text or '').replace('\r\n', '\n').strip().split('\n')]
    return lines(a) == lines(b)


def checked(result, action):
    if not isinstance(result, dict) or result.get('error') or result.get('success') is not True:
        detail = result.get('message') or result.get('error') if isinstance(result, dict) else None
        raise ValueError(f'The portal refused to {action}' + (f': {detail}' if detail else ''))
    return result


def upload_image(name, path, token):
    started = request_json(PORTAL + '/api/v2/mods/images/add', {'mod': name}, token=token)
    if not isinstance(started, dict):
        started = {}
    parsed = urllib.parse.urlparse(started.get('upload_url', ''))
    if started.get('error') or parsed.scheme != 'https' or not parsed.netloc or parsed.username or parsed.password:
        raise ValueError('The portal did not provide a valid HTTPS image upload destination')
    # The upload URL carries its own authorization. Never forward the API key or log the URL.
    result = request_json(started['upload_url'], {}, archive=path, field='image', content_type=IMAGE_TYPES[path.suffix.lower()])
    if not isinstance(result, dict) or not result.get('id') or result.get('error'):
        raise ValueError(f'The portal rejected {path.name}')
    return result['id']


def sync(tag, token, dry_run=False, root=REPO):
    if not TAG.fullmatch(tag or ''):
        raise ValueError('Expected a stable tag such as v0.1.1')
    info = json.loads((root / 'info.json').read_text(encoding='utf-8'))
    page = render(tag, root)
    mod = full_listing(info['name'])
    if mod is None:
        if not dry_run:
            raise ValueError('The mod is not on the portal yet: publish the release before syncing its page')
        print('Not on the portal yet: the first sync after publishing sets the summary, description and gallery')
        return
    if any(version_parts(release['version']) > version_parts(tag[1:]) for release in mod.get('releases', [])):
        raise ValueError('The portal has a newer release; an older tag never replaces its page')
    details = {field: page[field] for field in ('summary', 'description') if not same_text(mod.get(field), page[field])}
    images = [(path, hashlib.sha1(path.read_bytes()).hexdigest()) for path in page['gallery']]
    current = [image.get('id') for image in mod.get('images', [])]
    # An empty portal/gallery leaves the live gallery alone, so images added by hand survive.
    gallery = bool(images) and [digest for _, digest in images] != current
    for field in details:
        print(f'{field}: changed')
    if gallery:
        removed = len(set(current) - {digest for _, digest in images})
        print('gallery: ' + ', '.join(f'{path.name} ({"kept" if digest in current else "new"})' for path, digest in images)
              + (f'; {removed} image(s) not in portal/gallery leave the page' if removed else ''))
    if not details and not gallery:
        print('The portal page is already up to date')
        return
    if dry_run:
        return
    if not token:
        raise ValueError('Connect FACTORIO_API_KEY before changing the portal page')
    name = info['name']
    if details:
        checked(request_json(PORTAL + '/api/v2/mods/edit_details', {'mod': name, **details}, token=token),
                'change the ' + ' and '.join(details))
    if gallery:
        ids = [digest if digest in current else upload_image(name, path, token) for path, digest in images]
        result = checked(request_json(PORTAL + '/api/v2/mods/images/edit', {'mod': name, 'images': ','.join(ids)},
                                      token=token), 'arrange the gallery')
        if [image.get('id') for image in result.get('images', [])] != ids:
            raise ValueError('The portal gallery does not match portal/gallery after the change; sync the same tag again')
    print('Updated the portal page from ' + tag)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument('--check', action='store_true')
    action.add_argument('--tag')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--print', action='store_true', help='also print the summary and description as the portal gets them')
    args = parser.parse_args()
    try:
        if args.print:
            page = render(args.tag or 'main', tracked=tracked_files())
            print(page['summary'] + '\n\n' + '-' * 72 + '\n\n' + page['description'] + '\n\n' + '-' * 72)
        if args.check:
            page = render('HEAD', tracked=tracked_files())
            print(f'Portal page OK: {len(page["summary"])}-character summary, '
                  f'{len(page["description"])}-character description, {len(page["gallery"])} gallery images')
        else:
            sync(args.tag, os.environ.get('FACTORIO_API_KEY'), args.dry_run)
    except ValueError as error:
        raise SystemExit(str(error)) from None
    except urllib.error.HTTPError as error:
        raise SystemExit(f'Factorio HTTP {error.code}; check the API key has Edit Mods and sync the same tag again') from None
    except (urllib.error.URLError, TimeoutError):
        raise SystemExit('Factorio connection failed; sync the same tag again') from None
