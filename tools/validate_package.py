#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Validate the actual ZIP against source files, release metadata and its checksum."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

from package_mod import REPO, mod_files
from release_metadata import package_metadata, split_notes, validate_notes


def validate(output, tag=None, root=REPO):
    info, notes = package_metadata(root)
    source_info = json.loads((root / 'info.json').read_text())
    if tag is not None:
        if split_notes((root / 'changelog.txt').read_text())[0] is not None:
            raise ValueError('Finalize Unreleased notes before stable publication')
        if tag != 'v' + info['version']:
            raise ValueError('Stable tag must match the package version')
    folder = f'{info["name"]}_{info["version"]}'
    archive = output / (folder + '.zip')
    expected = {path.relative_to(root).as_posix(): path.read_bytes() for path in mod_files(root)}
    expected['changelog.txt'] = notes.encode()
    if info != source_info:
        expected['info.json'] = (json.dumps(info, indent=2) + '\n').encode()
    required = {'info.json', 'changelog.txt', 'control.lua', 'data.lua', 'COPYING', 'COPYING.LESSER', 'NOTICE',
                'assets/roads/yuoki-railways/Licence.txt'}
    if not required <= expected.keys():
        raise ValueError('Required release files or notices are missing')
    with zipfile.ZipFile(archive) as zipped:
        names = zipped.namelist()
        if len(names) != len(set(names)) or set(names) != {folder + '/' + name for name in expected}:
            raise ValueError('Unexpected or missing package entries')
        if zipped.testzip() is not None:
            raise ValueError('Package CRC validation failed')
        for name, content in expected.items():
            if zipped.read(folder + '/' + name) != content:
                raise ValueError(f'Package bytes differ from source: {name}')
        validate_notes(zipped.read(folder + '/changelog.txt').decode(), info['version'])
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    if (output / 'SHA256SUMS').read_text() != f'{checksum}  {archive.name}\n':
        raise ValueError('Package checksum does not match')
    print(f'Validated {archive.name}, {len(expected)} files and licence notices')
    return info, archive


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=REPO / 'dist')
    parser.add_argument('--tag')
    args = parser.parse_args()
    validate(args.output, args.tag)
