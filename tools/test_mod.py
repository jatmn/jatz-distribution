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

--mod adds another mod's zip to both runs. With one of the Mining Drones mods
(Mining_Drones, Mining_Drones_Remastered or Mining_Drones_Mod), a request depot must
also fetch iron ore from a mining depot's output, at the road it lays behind the depot.
With Milestones, Milestones must load our preset addon.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

from package_mod import build

ROOT = Path(__file__).resolve().parents[1]
CHECK = ROOT / 'tests/factorio/jatz-distribution-check_0.1.0'
OURS = ('jatz-distribution', 'jatz-distribution-check')
# Dependency prefixes Factorio loads with the mod: required ('' and '~') and recommended ('+').
LOADED_WITH = re.compile(r'^\s*(?:~|\+)?\s*([A-Za-z0-9_-]+)')
EXPECTED = {'free_recipes': 10,
            # All 10 recipes are free. Research: the freight system (after engine) unlocks the item
            # and fuel depots, the freighter and road; liquid freight, after it and fluid handling,
            # the liquid depots; and the road network monitor research, after it and the circuit
            # network, the monitor; each locked until then. Freighter speed has 4 levels then an
            # infinite one; item and fluid capacity 5 each. A force with speed 1-4 and the infinite level written to 7, item
            # capacity 1-2 and fluid capacity 1-3 has 6, 2 and 3 levels; a new force none. Its
            # freighter leaves at 2.2 times the speed, slows to 1.6 times on the road when speed
            # level 4 is undone, and brings 12 stacks (1200 iron plates) a trip, 2000 in all.
            'research_unlocks': {
                'jatz-freight-system': {'prerequisites': ['engine'], 'locked': 6, 'unlocked': 6, 'recipes': [
                    'jatz-provider-depot', 'jatz-request-depot', 'jatz-buffer-depot', 'jatz-fuel-depot',
                    'jatz-quinityn-freighter', 'jatz-road']},
                'jatz-liquid-freight': {'prerequisites': ['fluid-handling', 'jatz-freight-system'], 'locked': 3,
                                        'unlocked': 3, 'recipes': [
                    'jatz-liquid-provider-depot', 'jatz-liquid-request-depot', 'jatz-liquid-buffer-depot']},
                'jatz-road-network-monitor': {'prerequisites': ['circuit-network', 'jatz-freight-system'], 'locked': 1,
                                              'unlocked': 1, 'recipes': ['jatz-road-monitor']}},
            'speed_infinite': True, 'research_levels': {'jatz-freighter-speed': 5, 'jatz-freighter-item-capacity': 5,
                                                        'jatz-freighter-fluid-capacity': 5},
            'researched_levels': {'speed': 6, 'item_capacity': 2, 'fluid_capacity': 3, 'fresh': 0},
            'researched_speed': 2.2, 'researched_speed_reversed': 1.6, 'researched_first_load': 1200,
            'researched_received': 2000,
            'ghosts': 28, 'placed': 28, 'rotations': 112, 'pipe_connections': 20,
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
            'redelivered_after_destroy': 30, 'destroyed_restocked': 3, 'changed_provider_left': 20, 'changed_received': 0,
            'changed_status': 'no-provider', 'cut_returned': 30, 'cut_received': 0, 'cut_status': 'unreachable',
            'spilled': 0, 'bad_item_rejected': True, 'refused_request_kept': True, 'cloned_request': 'wood x5', 'request_cleared': True, 'road_on_grass': True,
            'road_on_water': False,
            # Nothing but belts, pipes, train tracks and vehicles can be placed on road: not depots,
            # nor their ghosts, though their loading zone can be road.
            'depot_on_road': False, 'depot_ghost_on_road': False, 'depot_zone_on_road': True,
            'on_road': {'small-electric-pole': False, 'inserter': False, 'wooden-chest': False,
                        'transport-belt': True, 'pipe': True, 'straight-rail': True, 'jatz-quinityn-freighter': True,
                        'jatz-road-monitor': False},
            # Nor can road be laid under any of them, a gate included while it stands open.
            'road_under': {'open_gate': 'grass-1', 'closed_gate': 'grass-1', 'pole': 'grass-1',
                           'gate_still_open': True, 'gate_closed': True},
            # Road and depot changes take effect at once: a mended road is used, a removed provider
            # is replaced by the next one, a removed request depot's freighter leaves.
            'rerouted_received': 10, 'rerouted_from_farther': 10, 'orphaned_provider_left': 10,
            'rerouted_same_freighter': True,
            # The provider nearest by road wins over the one nearest in a straight line, and a
            # request with no road route to any provider sends no freighter at all.
            'shortest_from_far': 10, 'shortest_from_near': 0, 'island_freighter_sent': False,
            # The freighter is drawn at 60% of the artwork's scale (1.5 x 4.5 tiles measured): 0.9 x 2.7,
            # as the engine stores it, in 1/256 tiles rounded towards the centre.
            'freighter_box': [0.8984375, 2.6953125],
            # Players can't place the freighter as a car unless the jatz-freighter-drivable startup
            # setting, off by default, is on.
            'freighter_placeable': False,
            # The freighter's cargo is light grey on the way to the provider; loading iron plates
            # swaps it for the freighter in iron ore's map color, which drives them home. Water
            # takes its own color.
            'paint_out': 'jatz-freighter-drone', 'paint_home': 'jatz-freighter-drone-233', 'paint_swapped': True,
            'paint_iron_plate': True, 'paint_water': True,
            # A freighter with a sticker (like fire) stuck to it loads without being swapped, so the
            # sticker and its damage go on untouched, and is painted on the way home once the
            # sticker wears off; its 10 iron plates arrive.
            'sticker_kept': True, 'sticker_then_painted': True, 'sticky_received': 10,
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
            # Enemies: a freighter runs over a biter on the road (impact damage) and delivers
            # anyway, leaving the player beside it unhurt; biters destroy another freighter, which
            # explodes and leaves the car's wreck where it died. Its depot asks robots for a
            # replacement at once, is filled by its other freighters, and the robots bring the
            # replacement (3 again). Freighters out show up in the pollution statistics.
            'runover_received': 10, 'runover_biter': 'jatz-freighter-drone/impact', 'bystander_unhurt': True,
            'ambush_killed_by': 'behemoth-biter/physical', 'ambush_exploded': True, 'ambush_wrecks': 1,
            'ambush_replacement_requested': 1, 'ambush_received': 10,
            'ambush_freighters_home': 3, 'freighters_polluted': True,
            # The request panel's status light: the game's four status indicator sprites exist.
            'status_lights': 4,
            # Every depot takes a red wire in all four directions. A provider switched off by its
            # circuit condition supplies nothing (its request depot finds no provider) until a
            # combinator switches it on at tick 300; a request depot switched off sends nothing
            # until then. The road network monitor, beside one road, shows what its provider and
            # liquid provider hold, leaving out a switched-off provider, request depots and the
            # other road. Only delivery depots take a condition; players can't open the monitor.
            # The monitor opens, to its own panel (its reading); its signals stay its own.
            'wired_depots': 28, 'circuit_refused_elsewhere': False, 'monitor_operable': True,
            # Monitors reading request depots: before tick 300 the wall request depot holds none
            # and still needs all 10 (its provider is switched off); afterwards it holds 10 and
            # needs none. An unknown reading is refused; the default is providers and buffers.
            'monitor_readings_refused': False, 'monitor_reading_default': 'supply',
            'circuit_readings_after': {'requests': 'stone-wall=10', 'needs': ''},
            # A combinator's settings pasted onto a monitor: the monitor shows its own reading, in its
            # own switched-on, unmultiplied section, and the shared group keeps signal-A = 123.
            'monitor_pasted': {'shows': 'stone-wall=10,water=1000', 'own': True,
                               'group': {'source': 'signal-A=123', 'other': 'signal-A=123'}},
            # Each depot condition agrees with the game's own (a lamp's) on the same wires.
            'condition_parity': {'anything_ge_b': {'native': False, 'depot': False},
                                 'everything_gt_b': {'native': True, 'depot': True},
                                 'overflow': {'native': False, 'depot': False},
                                 'wildcard_wrap': {'native': True, 'depot': True}},
            'monitor_beside_road': True,
            'circuit_before': {'walls': 0, 'lamps': 0, 'walls_status': 'no-provider', 'lamps_status': 'disabled',
                               'monitor': {'walls': 0, 'water': 1000, 'lamps': 0},
                               # The switched-off provider's hover panel says so with a red light;
                               # the request depot, which has no condition, shows its own status.
                               'gated_status': {'red': True, 'label': 'jatz-circuit-status.entity-off'},
                               'readings': {'requests': '', 'needs': 'stone-wall=10'},
                               'request_status': False,
                               # The modes road's monitor leaves out another force's 50 copper.
                               'merged_monitor': 'wood=2800'},
            # Once that force merges into the player's, the monitor counts its copper, with no road
            # or depot changing.
            'monitor_after_merge': 'copper-plate=50,wood=2800',
            # 200 wood taken out of the wired depot this tick: the wire still carries its 300 (3100),
            # and the 2800 elsewhere is not more than 2900, before or after.
            'circuit_transfer': {'before': False, 'after': False, 'wire': 3100, 'held': 100},
            # A monitor counting a provider's 100 iron, cloned at tick 301 and wired to it: the clone
            # puts nothing on the wire before its first update (200: the provider's own 100 and the
            # monitor's count), so the provider's iron plate > 0 doesn't hold.
            'monitor_clone': {'before': {'wire': 200, 'fulfilled': False, 'monitor': 'iron-plate=100'},
                              'after': {'wire': 200, 'fulfilled': False, 'clone_shows': ''}},
            # Switched on at tick 300, the provider shows its own status again.
            'circuit_status_after': True,
            'circuit_walls': 10, 'circuit_lamps': 10, 'circuit_after': {'walls': 10, 'water': 1000, 'lamps': 0},
            # Reading the circuit network, a depot leaves out its own wood: 300 here and 2800 at the
            # depot wired to it (or counted by the monitor) is not more than 3000, but is more than
            # 2700. Reading its own 200 wood: more than 100, not more than 300. An unknown mode is
            # refused.
            'circuit_modes': {'wired_wire': 3100, 'monitored_wire': 3100, 'wired': False, 'monitored': False,
                              'own': True, 'own_mode': 'contents', 'wired_2700': True, 'monitored_2700': True,
                              'own_300': False},
            'circuit_mode_refused': False,
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
            'water_delivered': 1200, 'water_provider_left': 800, 'truck_chests': 1, 'provider_truck_chests': 0,
            'liquid_refuses_items': False, 'item_depot_refuses_fluids': False,
            'steam_delivered': 300, 'steam_temperature': 500, 'steam_buffer_left': 700,
            'steam_provider_left': 1000, 'liquid_requested': 2, 'liquid_robots_delivered': 2,
            # Not set to request from buffers, with the only liquid provider empty, a liquid request
            # depot falls back to the liquid buffer for its 300 crude oil.
            'fallback_from_buffers': False, 'fallback_delivered': 300, 'fallback_buffer_left': 700,
            # A hand-placed freighter lowers the same request proxy (5 -> 4) instead of replacing
            # it, so an open window keeps showing the request.
            'hand_fill_same_proxy': True, 'hand_fill_requested': 4,
            # Tank sizes: the check mod sets the liquid provider and liquid buffer settings to
            # 40,000 and 15,000 (settings-updates.lua); the other tanks keep 25,000.
            'tank_sizes': {'fuel': 25000, 'liquid-provider': 40000, 'liquid-request': 25000,
                           'liquid-buffer': 15000},
            # Fuel: a freighter short of fuel for the leg fills up at a Fuel depot first (5 of 10
            # coal, 20 MJ) and still delivers, parking with 19 MJ left; with liquid fuel it takes
            # 50 of 100 petroleum gas (the mod makes it burn at 0.4 MJ); with no fuel to be had it
            # stays home saying so, and goes at once (delivering a second later, not after its
            # 10-second wait) when coal is put in the Fuel depot. A Fuel depot
            # turned by script turns its hidden tank too.
            # Low on the way, the freighter's hover shows its fuel as a yellow status.
            'fuel_stop_first': True, 'fuel_delivered': 10, 'fuel_coal_left': 5, 'fuel_left_mj': 19,
            'fuel_hover': 'jatz-gui.freighter-fuel', 'fuel_hover_diode': 'yellow',
            'liquid_fuel_delivered': 10, 'liquid_fuel_taken': 50, 'no_fuel_status': 'no-fuel',
            'no_fuel_received_before': 0, 'no_fuel_status_after_coal': 'delivering',
            'no_fuel_received_after': 10, 'no_fuel_coal_left': 0,
            'fuel_tank_turned': True,
            # A Fuel depot cloned alone, or with its hidden tank, keeps its coal and its liquid,
            # with one tank; the original keeps its own.
            'fuel_clone_alone': 'water 1234, 10 coal, 1 tank(s)',
            'fuel_clone_with_tank': 'water 1234, 10 coal, 1 tank(s)',
            'fuel_clone_source': 'water 1234, 10 coal, 1 tank(s)',
            # Our Milestones preset addon names only real items.
            'milestones': ['jatz-quinityn-freighter x1', 'jatz-quinityn-freighter x100', 'jatz-road x1000']}
# With a Mining Drones mod: the mining depot's road, and 30 of its 40 iron ore delivered.
MINING_DRONES = {'Mining_Drones', 'Mining_Drones_Remastered', 'Mining_Drones_Mod'}
EXPECTED_MINING = {'zone': 'jatz-depot-road', 'delivered': 30, 'left': 10}
# With Milestones: its log line when a new game loads our preset addon (control.lua).
MILESTONES_LOADED = re.compile(r'Preset addons loaded: \{[^}]*"Jat\'z Distribution"')
# Long enough for the check mod's deliveries (it fails itself at tick 2500).
TICKS = 2600


def run(command, log, timeout=300):
    with log.open('w') as handle:
        return subprocess.run(command, stdout=handle, stderr=subprocess.STDOUT, timeout=timeout).returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--factorio', required=True, type=Path)
    parser.add_argument('--data-dir', type=Path)
    parser.add_argument('--mod', action='append', default=[], type=Path,
                        help="another mod's zip to load too, such as one of the Mining Drones mods or Milestones (repeatable)")
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
    extra = {mod_name(path): path.resolve() for path in args.mod}
    failed = False
    for label, enabled in setups.items():
        failed |= not check(binary, data, bundled, enabled, label, extra)
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


def mod_name(path):
    """The name in a mod zip's info.json (in its one top-level folder)."""
    with zipfile.ZipFile(path) as archive:
        info = [name for name in archive.namelist() if name.count('/') == 1 and name.endswith('/info.json')
                and not name.startswith('__MACOSX/')]
        return json.loads(archive.read(info[0]))['name']


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


def check(binary, data, bundled, enabled_mods, label, extra=None):
    parent = ROOT / '.local/mod-check'
    parent.mkdir(parents=True, exist_ok=True)
    workspace = Path(tempfile.mkdtemp(prefix='run-', dir=parent))
    mods = workspace / 'mods'
    mods.mkdir()
    package, _ = build(mods)
    shutil.copytree(CHECK, mods / CHECK.name)
    extra = extra or {}
    for path in extra.values():
        shutil.copy(path, mods / path.name)
    # List every bundled mod explicitly: Factorio enables installed ones that aren't listed.
    enabled = {name: name in enabled_mods for name in sorted(bundled)}
    enabled.update({name: True for name in (*OURS, *extra)})
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
    expected_mods = sorted(enabled_mods | set(OURS) | set(extra) | {'core'})
    translations = locale_keys()
    untranslated = sorted({key for names in report.get('localised_names', {}).values()
                           for key in names.values() if key not in translations})
    if report.get('menu_tab') != 'logistics':
        wrong['menu_tab'] = report.get('menu_tab')
    if MINING_DRONES & set(extra) and report.get('mining') != EXPECTED_MINING:
        wrong['mining'] = report.get('mining')
    if 'Milestones' in extra and not MILESTONES_LOADED.search((workspace / 'create.log').read_text()):
        wrong['milestones_addon'] = 'not loaded by Milestones'
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
          f'the car row {report["car_row_order"]!r} in {report["menu_tab"]}. Mods loaded: {", ".join(loaded)}'
          + (f'. Mining depot: {report["mining"]["delivered"]} iron ore delivered' if 'mining' in report else '')
          + ('. Milestones loaded our preset addon' if 'Milestones' in extra else ''))
    return True


if __name__ == '__main__':
    main()
