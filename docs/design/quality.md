# Quality

Quality support is optional (the owner's request, November 13, 2026). It is active only when the Quality mod, or another mod, gives qualities above normal, and it has no setting. `quality` is an optional dependency in `info.json`.

Two things are kept apart:

- **What a request asks for.** An item request can ask for one quality, for qualities compared with one, or for any quality. Freighters fetch what the request asks for. The quality of the depots or the freighter never decides what a freighter carries.
- **What a freighter's or depot's own quality gives.** A better freighter carries more, drives faster and has a bigger tank and more health. A better depot has a bigger chest or tank.

Without qualities above normal, everything works as before quality: normal requests, and requests from before quality, are stored and handled exactly as they always were.

## Code

- `scripts/quality.lua`: the qualities the game has, comparators, `normalize`, `matching`, keys, item filters and multipliers.
- `scripts/logistics.lua`: requests (`set_request`, `get_request`), need and room (`logistics.graded_need`), loading (`logistics.load_qualities`), trip parts (`logistics.set_parts`), freighter choice (`logistics.next_freighter`), parked fuel per quality, `logistics.replaced`, `logistics.forget_lost_qualities`.
- `scripts/promises.lua`: promises and cargo coming home, by key (`ledger.allocate`, `ledger.foreign`, `file_coming_one`).
- `scripts/research.lua` and `scripts/fuel.lua`: a freighter's cargo, speed and tank at its quality.
- `scripts/freighter-requests.lua`: freighters asked of robots, by quality.
- `scripts/depot-upgrades.lua`: a depot replaced by itself at another quality.
- `scripts/request-gui.lua`: the quality row of the item request panel.
- `scripts/depot-settings.lua`: the comparator in blueprints (`jatz_quality_comparator`).

## Requests

A request (item request and buffer depots only; fluids have no quality) stores two extra fields:

- `quality`: nil for normal.
- `comparator`: nil for `=`; one of the game's quality comparators `≠`, `>`, `<`, `≥`, `≤` as the game reads them back (the ASCII forms `!=`, `>=`, `<=` are accepted too); or `"any"`, with no quality.

So normal requests, and those from before quality, are unchanged everywhere: tags, blueprints and the remote interface (`set_request(entity, item, count, quality, comparator)`, `get_request`).

- `quality.normalize` refuses a quality the game doesn't have, or a hidden one other than normal. The base game without the Quality mod lists normal itself as hidden (probed on 2.1.24).
- Qualities compare by `level`, as the game's own item filters do (probed on 2.1.24 with `get_item_count_filtered` and each comparator).
- `quality.matching` lists the qualities a request takes, highest first. Freighters take the highest first (the owner's choice, November 13, 2026).
- `logistics.graded_need` reads held stock with the request's `ItemFilter` (`quality.item_filter`).

## Keys, promises and trips

Promises, what trips bring and providers' stock are kept by key (`quality.key`):

- an item at normal quality: the item's name, as before quality;
- an item at another quality: `"item/quality"` (prototype names can't hold a slash);
- a fluid: its name.

A trip planning more than normal has `trip.mix` (quality to amount, adding up to `planned`, set by `logistics.set_parts`). Each quality has its own stock and promise queue (`honoured`, `keep_promises`, and `release_excess`, which lets the lowest qualities go first) and its own cargo stacks (`ledger.allocate`, which also fills a full load). [Runtime state](../runtime-state.md) lists the trip fields.

A trip of one key keeps the code and cost it had before quality: `file_coming_one`, the scalar `promise` path, `logistics.honoured_one`, and `keep_promises`' scalar branch. The UPS emulator counted 10% more instructions per tick before they had their own paths.

## Room in a request depot

The room for several qualities is worked out as the game fills a chest:

- empty stacks: the insertable count of a quality no stack has (`quality.absent`; the game's hidden `quality-unknown` is such a quality, probed on 2.1.24);
- each quality's part-filled stacks;
- what is coming of each quality filling its own room first.

So a freighter loading several qualities (`logistics.load_qualities`) never brings what has to be spilled.

Cargo still coming home of qualities the request no longer takes (the request changed after they loaded: `ledger.foreign`) counts towards no demand but keeps its room, for a plain request too.

## A freighter's quality

A freighter's quality (`trip.freighter_quality`, nil for normal) multiplies by the quality's `default_multiplier` (+30% a level, read from the game so modded qualities count):

- its cargo stacks, rounded down as the game rounds chest slots (`research.cargo_stacks`);
- its fluid, to whole units (`research.fluid_capacity_of`);
- its speed (`research.freighter_speed`);
- its fuel tank (`fueling.fuel_capacity`, `fueling.tank_of`; see [Fuel](fuel.md)).

Its unit is made at that quality, so the game gives it that quality's health (probed: 500, 800, 1,250 for normal, rare, legendary). `repaint` keeps the quality.

- A depot sends its highest-quality freighter first (`logistics.next_freighter`, one `get_item_quality_counts` call).
- Parked fuel is kept per quality: `depot.fuel` for normal, `depot.graded_fuel[quality]` otherwise. `logistics.freighter_fuel` gives each freighter's tank (`home_tanks`, `out_tanks`) for the request panel.

## A depot's quality

Better depots get the game's bigger chests and tanks, probed at the default sizes:

| Quality | Chest slots (`quality_affects_inventory_size`) | Storage tank volume |
| --- | --- | --- |
| normal | 48 | 25,000 |
| rare | 76 | 40,000 |
| legendary | 120 | 62,500 |

- 1.6 times 25,000 is a hair over 40,000, so a tank's size is floored to whole units (`logistics.fluid_limit`, which `set_request` uses).
- A Fuel depot's hidden tank is remade at its depot's quality (`depot.tank_graded`, looked at once).

### A depot replaced by itself at another quality

Robots or a space platform carrying out an upgrade order, or a player building the depot over itself at another quality, replace the entity with a new unit number in the same tick. `scripts/depot-upgrades.lua` recognises this and moves everything the mod kept to the new depot, through `logistics.replaced`, `depot_road.replaced` and `road_monitor.replaced`, as for legacy depots. It also keeps the depot's robot access, which the game turns back on. [Logistic robots and replacing depots](depots-robots-and-replacing.md) covers replacing depots in general.

Quality-specific parts of `logistics.replaced`:

- It moves where each trip's promise is filed (`trip.promise.provider`), so letting the promise go or filing it again looks at the new depot.
- It cuts the request to what the new chest or tank holds, as `set_request` does, because a lower quality's is smaller. Kept above that, a "Full loads only" request would wait for a load that never fits.

The events, probed on 2.1.24:

- Robots and platforms: `on_*_mined_entity` with the old entity still marked for upgrade to the same depot (no pre-mined event), then the build event for the new one.
- A player: `on_pre_build`, `on_pre_player_mined_item`, `on_player_mined_entity`, then `on_built_entity`. The player's cursor is read at `on_pre_build` (`storage.depot_builds`): it can be empty by the time the old depot is mined (0.1.8 crashed on that).

## Robots and freighter requests

Robots asked for freighters bring the quality of the panel's cursor ghost, or of a lost freighter for its replacement (`replenishment.quality`, the latest asked for). Those still waiting for a free truck chest stack keep their own quality (`replenishment.waiting`, first asked first, a plan per quality). [Runtime state](../runtime-state.md) describes these fields.

- The game reads a proxy's insert plans back sorted by quality and joins those of one quality (probed on 2.1.24). So `depot.freighter_asks` lists the truck chest stacks asked for in the order asked, with their quality, and freighters put in by hand cancel the last asked first (`reduce_freighter_requests`).
- Removal plans name each stack's quality.

## Request panel

Only while `quality.available()`, an item request panel has a quality row under the item and amount:

- the label "Quality";
- a comparator drop-down, with "Any quality" last;
- a drop-down of the qualities (`quality.names()`, lowest first, each with its icon), hidden while "Any quality" is chosen.

So it reads "Quality ≥ rare", and no comparator sits between the item and its amount (the owner's report, November 14, 2026). The item chooser stays a plain item chooser.

- An open panel's row follows the request at each refresh (`show_quality`, which also builds it), as the checkboxes do, because other players, Copy and Paste settings and the remote interface change a request while it is open. Each drop-down is written only when it differs, so one a player has open stays open.
- Choosing another item keeps the request's quality. With no request (the item cleared), the row is what the player chose for the next item.
- A panel still open in a save is built again at a mod change (`request_gui.on_configuration_changed`, after `setup`, so a quality that is gone is already forgotten). The game keeps a mod's GUI as it was, but the drop-down's events read its selected index in today's `quality.names()`, which may list other qualities.

## Blueprints

Blueprint request settings carry the quality in their signal (parametrisable) and the comparator as the settings' `jatz_quality_comparator` tag, only when it is not `=`. See [Roads and deliveries](roads-and-deliveries.md) (blueprint parametrisation) for request settings.

## Mod changes

A quality a mod change removed is forgotten (`logistics.forget_lost_qualities`, from `logistics.add_all`):

- a depot's request for it becomes a normal one (any quality stays any);
- parked fuel kept under it goes (those freighters have full tanks now);
- robots bring normal freighters for the freighter target;
- a trip plans no load of it, and its freighter counts as normal, driving at a normal freighter's speed.

## Tests

- `tests/lua/quality.lua` runs on `tests/lua/harness.lua`'s quality-aware fakes (a name alone is normal quality, as in the game).
- `tests/lua/quality.lua` and `tests/lua/control-events.lua` cover requests, deliveries, room, freighters, robots, upgrades and the panel.
- The check mod's `scenarios/quality`, run by `tools/test_mod.py` when the Quality mod is enabled (`EXPECTED_QUALITY`), covers them against the real engine.
