#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
"""Load the packaged mod in Factorio and check that everything can be crafted, placed and driven.

Builds the mod zip with tools/package_mod.py, installs it in an isolated workspace
under .local/mod-check/ with the check mod from tests/factorio/, creates a save
(placing every depot in four directions with pipes, a fuelled, driven freighter
and road-connected provider and request depots) and runs it until the deliveries
are done. Runs once with the base game only and,
when the installation includes Space Age and everything it needs, once more with
Space Age. Also checks that every item, recipe and entity name the game shows has
an English translation. Works with the free headless server.

python3 tools/test_mod.py --factorio /path/to/factorio/bin/x64/factorio
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from package_mod import build

ROOT = Path(__file__).resolve().parents[1]
CHECK = ROOT / 'tests/factorio/jatz-distribution-check_0.1.0'
OURS = ('jatz-distribution', 'jatz-distribution-check')
# Dependency prefixes Factorio loads with the mod: required ('' and '~') and recommended ('+').
LOADED_WITH = re.compile(r'^\s*(?:~|\+)?\s*([A-Za-z0-9_-]+)')
EXPECTED = {'free_recipes': 9, 'ghosts': 28, 'placed': 28, 'rotations': 112, 'pipe_connections': 20,
            'cleared_zones': 28,
            # Deliveries (tests/factorio/jatz-distribution-check_0.1.0/control.lua): 30 of the
            # provider's 50 iron plates reach the request over the road; the request on an
            # isolated road tile gets nothing, and the one without road sends no freighter.
            'delivered': 30, 'provider_left': 20, 'island_received': 0, 'request_status': 'satisfied',
            'island_status': 'unreachable', 'unpaved_status': 'no-road',
            # Cargo keeps item data; a full request depot fetches nothing; a destroyed freighter is
            # replaced; a changed request doesn't load the old item; cargo cut off from its
            # destination goes back to the provider; nothing is ever spilled; requests are
            # validated, cloned and cleared; road is laid on ground but not water.
            'armor_equipment': 1, 'full_status': 'full', 'full_provider_left': 50,
            'redelivered_after_destroy': 30, 'changed_provider_left': 20, 'changed_received': 0,
            'changed_status': 'no-provider', 'cut_returned': 30, 'cut_received': 0, 'cut_status': 'unreachable',
            'spilled': 0, 'bad_item_rejected': True, 'refused_request_kept': True, 'cloned_request': 'wood x5', 'request_cleared': True, 'road_on_grass': True,
            'road_on_water': False,
            # Road and depot changes take effect at once: a mended road is used, a removed provider
            # is replaced by the next one, a removed request depot's freighter leaves.
            'rerouted_received': 10, 'rerouted_from_farther': 10, 'orphaned_provider_left': 10,
            'rerouted_same_freighter': True,
            # The provider nearest by road wins over the one nearest in a straight line, and a
            # request with no road route to any provider sends no freighter at all.
            'shortest_from_far': 10, 'shortest_from_near': 0, 'island_freighter_sent': False,
            # The freighter is drawn at 75% of the artwork's scale (1.5 x 4.5 tiles measured).
            'freighter_box': [1.125, 3.375],
            # Depots lay road under their loading zone, connecting road a tile away, and take it
            # away when removed, putting back what it covered; road that was already there, or
            # laid over theirs, stays; a shared tile keeps road until the last depot goes; nothing
            # is laid on water.
            'depot_road_laid': 'jatz-depot-road', 'depot_road_hides': 'grass-1', 'connected_by_depot_roads': 5,
            'concrete_restored': 'concrete', 'grass_restored': 'grass-1', 'road_kept_on_build': 'jatz-road',
            'road_kept_on_removal': 'jatz-road', 'covered_kept': 'stone-path', 'water_left': 'water',
            'shared_kept': 'jatz-depot-road', 'shared_restored': 'concrete',
            # Request depots send their own freighters: as many as needed, one after another, from
            # more than one provider, all back in the slot after; none without freighters;
            # freighters put in the chest go to the slot; removed depots leave theirs behind.
            'multi_freighters_sent': 2, 'multi_received': 60, 'multi_from_near': 30, 'multi_from_far': 30,
            'multi_freighters_home': 5, 'no_trucks_status': 'no-trucks', 'absorbed': 2, 'absorbed_left_in_chest': 0,
            'orphaned_freighters_dropped': 3, 'destroyed_freighters_dropped': 102,
            # A slot holding 3 takes 97 more (a depot holds 100), however many are asked for; more
            # than a stack (10) is requested and taken away a stack at a time.
            'add_beyond_limit': 97, 'requested_many': 25, 'requested_many_pending': 25, 'removing_many': 25,
            'removing_many_pending': 25, 'removing_many_left': 0,
            # Freighters requested (as from remote view) within the slot's limit, cancelled and
            # requested again; construction robots bring the 3 from storage into the slot.
            'requested': 4, 'requested_beyond_limit': 95, 'cancelled': 99, 'requested_again': 3,
            'robots_delivered': 4,
            # Then 2 taken away again by robots (as by a right-click in remote view): 2 stay in
            # the slot, storage is back to 4. A removal marked and cancelled at the start put its
            # freighter back.
            'removal_marked': 1, 'removal_cancelled': 1, 'robots_removal_marked': 2, 'slot_after_removal': 2,
            'storage_after_removal': 4,
            # The request panel's status light: the game's four status indicator sprites exist.
            'status_lights': 4,
            # Blueprints keep a request depot's request (tag) and freighters (insert plan): the
            # ghost built from one asks for 7 wood and has robots bring 3 freighters. Copy and Paste
            # settings has robots bring what the destination lacks (1 -> 3). Freighters put in by
            # hand count towards what was requested: requests beyond it go (6 asked, 7 put in ->
            # 0; 5 asked, 5 put in -> 0; 5 asked, 2 put in -> 3; the blueprint's 3, put in -> 0).
            'blueprinted': 1, 'blueprint_tag': 'wood', 'blueprint_freighters': 3, 'built_request': 'wood x7',
            'built_freighters_requested': 3, 'matched': 2, 'trimmed_requests': 0, 'filled_by_hand_requests': 0,
            'partly_filled_requests': 3, 'built_filled_requests': 0,
            # Blueprint setup keeps other items' plans and their chest stacks, drops settings the
            # depot no longer has, counts freighters still in the chest; malformed tags build
            # harmlessly; pasting a smaller count cancels the excess requests; filling by hand
            # trims at once.
            'blueprint_kept_other_items': True, 'blueprint_freighters_first_stack': 1, 'blueprint_cleared': True,
            'blueprint_counts_chest': 5, 'malformed_tags_built': True, 'matched_down': 3, 'trimmed_at_once': 0,
            # Ctrl+click of freighters into a depot's window fills the slot (95 -> 100) and gives
            # the rest back (10), leaving none in the chest.
            'ctrl_click_taken': 5, 'ctrl_click_returned': 10, 'ctrl_click_slot': 100, 'ctrl_click_left_in_chest': 0,
            'ctrl_click_pockets': 10,
            # Other items moved in the same way stay in the depot's chest, as in any container.
            'ctrl_click_other_items_kept': 20, 'ctrl_click_other_items_returned': 0,
            # Only freighters the player just moved: ones already in the chest stay (2 new ones
            # back, 3 old ones kept); newcomers merged into a stack waiting for robots go to the
            # slot (3), the 5 waiting stay.
            'ctrl_click_only_new_returned': 2, 'ctrl_click_existing_kept': 3, 'ctrl_click_merged_taken': 3,
            'ctrl_click_marked_left': 5,
            # A request Factorio dropped when part of it was filled by hand (5 asked, 1 put in) is
            # asked again for the rest (4); taking freighters away stops topping up (3 stay).
            'dropped_requested_again': 4, 'dropped_slot': 1, 'sent_away_requested': 3,
            # The same for a depot built over a blueprint ghost without its tags (as by hand).
            'untagged_requested_again': 4,
            # /jatz-freighters describes a depot's freighter slot from the real request proxies.
            'described': True,
            # Buffer depots: a request depot set to request from them takes its 20 from a buffer 20
            # tiles away rather than a provider 10 away; a buffer fills from the provider (15), not
            # from the other buffer; buffers have no request-from-buffers setting.
            'buffered_request': 20, 'buffer_taken_from': 20, 'buffer_filled': 15, 'buffer_provider_left': 85,
            'buffer_has_no_from_buffers': False,
            # Priority: a provider 30 tiles away at priority 9 supplies all 10, not one 10 tiles away
            # at priority 2; providers start at 5; request depots have no priority.
            'priority_from_far': 10, 'priority_from_near': 0, 'priority_default': 5,
            'request_has_no_priority': False,
            # Liquid depots: 1200 water in 500 loads from a liquid provider holding 2000; a liquid
            # request depot set to request from buffers takes 300 steam from a liquid buffer, at its
            # 500 degrees, not from a nearer provider; only liquid request depots get a truck chest;
            # robots bring a liquid depot's 2 freighters through it; items and fluids don't mix.
            'water_delivered': 1200, 'water_left': 800, 'truck_chests': 1, 'provider_truck_chests': 0,
            'liquid_refuses_items': False, 'item_depot_refuses_fluids': False,
            'steam_delivered': 300, 'steam_temperature': 500, 'steam_buffer_left': 700,
            'steam_provider_left': 1000, 'liquid_requested': 2, 'liquid_robots_delivered': 2,
            # A hand-placed freighter lowers the same request proxy (5 -> 4) instead of replacing
            # it, so an open window keeps showing the request.
            'hand_fill_same_proxy': True, 'hand_fill_requested': 4}
# Long enough for the check mod's deliveries (it fails itself at tick 1700).
TICKS = 1800


def run(command, log, timeout=300):
    with log.open('w') as handle:
        return subprocess.run(command, stdout=handle, stderr=subprocess.STDOUT, timeout=timeout).returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--factorio', required=True, type=Path)
    parser.add_argument('--data-dir', type=Path)
    args = parser.parse_args()
    binary = args.factorio.expanduser().resolve()
    data = args.data_dir.resolve() if args.data_dir else binary.parents[2] / 'data'
    if not binary.is_file() or not (data / 'base/info.json').exists():
        parser.error('Factorio executable or data directory missing')
    bundled = bundled_mods(data)
    space_age = enabled_with('space-age', bundled)
    setups = {'base game': {'base'}, **({'Space Age': space_age} if space_age else {})}
    if not space_age:
        print('Space Age, or a mod it needs, is not installed: checking the base game only.')
    failed = False
    for label, enabled in setups.items():
        failed |= not check(binary, data, bundled, enabled, label)
    raise SystemExit(1 if failed else 0)


def bundled_mods(data):
    """The mods shipped in the data directory (base, Space Age and its parts), with their info.json."""
    return {path.parent.name: json.loads(path.read_text()) for path in data.glob('*/info.json')
            if path.parent.name != 'core'}


def enabled_with(name, bundled):
    """name and every bundled mod Factorio loads with it, or None if one is missing."""
    found, pending = set(), [name]
    while pending:
        mod = pending.pop()
        if mod in found:
            continue
        if mod not in bundled:
            return None
        found.add(mod)
        for dependency in bundled[mod].get('dependencies', []):
            if dependency.lstrip().startswith(('!', '?', '(?)')):
                continue
            match = LOADED_WITH.match(dependency)
            if match:
                pending.append(match.group(1))
    return found


def locale_keys(root=ROOT):
    """section.key for every English translation in the mod."""
    keys = set()
    for path in (root / 'locale/en').glob('*.cfg'):
        section = ''
        for line in path.read_text(encoding='utf-8').splitlines():
            line = line.strip()
            if line.startswith('[') and line.endswith(']'):
                section = line[1:-1]
            elif '=' in line and not line.startswith((';', '#')):
                keys.add(f'{section}.{line.split("=", 1)[0]}')
    return keys


def check(binary, data, bundled, enabled_mods, label):
    parent = ROOT / '.local/mod-check'
    parent.mkdir(parents=True, exist_ok=True)
    workspace = Path(tempfile.mkdtemp(prefix='run-', dir=parent))
    mods = workspace / 'mods'
    mods.mkdir()
    package, _ = build(mods)
    shutil.copytree(CHECK, mods / CHECK.name)
    # List every bundled mod explicitly: Factorio enables installed ones that aren't listed.
    enabled = {name: name in enabled_mods for name in sorted(bundled)}
    enabled.update({name: True for name in OURS})
    (mods / 'mod-list.json').write_text(json.dumps({'mods': [
        {'name': name, 'enabled': state} for name, state in enabled.items()]}))
    write = workspace / 'write'
    write.mkdir()
    config = workspace / 'config.ini'
    config.write_text(f'[path]\nread-data={data.as_posix()}\nwrite-data={write.as_posix()}\n')
    save = workspace / 'jatz-distribution-check.zip'
    command = [str(binary), '--config', str(config), '--mod-directory', str(mods)]
    report_path = write / 'script-output/jatz-distribution-check.json'
    created = run(command + ['--create', str(save)], workspace / 'create.log')
    driven = created == 0 and save.exists() and run(
        command + ['--benchmark', str(save), '--benchmark-ticks', str(TICKS), '--benchmark-runs', '1'],
        workspace / 'drive.log') == 0
    # Factorio logs a checksum for every active mod, including ones without data stage files.
    loaded = sorted(set(re.findall(r'Checksum (?:for|of) ([A-Za-z0-9_-]+): \d+$',
                                   (workspace / 'create.log').read_text(), re.MULTILINE)))
    if not driven or not report_path.exists():
        for log in ('create.log', 'drive.log'):
            if (workspace / log).exists():
                print(f'--- {log}\n' + (workspace / log).read_text()[-6000:])
        print(f'{label}: FAILED. Evidence kept at {workspace}')
        return False
    report = json.loads(report_path.read_text())
    report['loaded_mods'] = loaded
    wrong = {key: report.get(key) for key, value in EXPECTED.items() if report.get(key) != value}
    expected_mods = sorted(enabled_mods | set(OURS) | {'core'})
    translations = locale_keys()
    untranslated = sorted({key for names in report.get('localised_names', {}).values()
                           for key in names.values() if key not in translations})
    if report.get('menu_tab') != 'logistics':
        wrong['menu_tab'] = report.get('menu_tab')
    if wrong or report.get('driven_tiles', 0) <= 1 or loaded != expected_mods or untranslated:
        problems = wrong or {'loaded': loaded, 'expected': expected_mods, 'untranslated': untranslated,
                             'driven_tiles': report.get('driven_tiles')}
        print(f'{label}: FAILED with {problems}. Evidence kept at {workspace}')
        return False
    (workspace / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'{label}: {package.name} passed: {report["placed"]} depots placed, {report["rotations"]} rotations, '
          f'{report["pipe_connections"]} pipe connections, {report["free_recipes"]} free recipes, '
          f'freighter drove {report["driven_tiles"]:.1f} tiles, {report["delivered"]} iron plates delivered by road '
          f'(a {report["detour"]:.0f}-tile detour, {report["road_samples"]} on-road samples), menu row {report["menu_row_order"]!r} directly above '
          f'the car row {report["car_row_order"]!r} in {report["menu_tab"]}. Mods loaded: {", ".join(loaded)}')
    return True


if __name__ == '__main__':
    main()
