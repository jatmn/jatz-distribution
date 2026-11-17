# Quality

Quality support is optional (the owner's request, November 13, 2026): active only when a mod gives qualities above normal, with no setting. Two things are kept apart:

- **What a request asks for**: one quality, qualities compared with one, or any. The quality of depots or freighters never decides what a freighter carries.
- **What an entity's own quality gives**: a better freighter carries more, drives faster, and has a bigger tank and more health; a better depot has a bigger chest or tank.

## Code

- `scripts/quality.lua`: qualities, comparators, keys, filters, multipliers.
- `scripts/logistics.lua`, `scripts/promises.lua`: requests, room, loading, trips, freighter choice, `logistics.replaced`, `logistics.forget_lost_qualities`.
- `scripts/depot-upgrades.lua`, `scripts/freighter-requests.lua`, `scripts/request-gui.lua`.
- Tests: `tests/lua/quality.lua`, `tests/lua/control-events.lua`; the check mod's `scenarios/quality`.

## Requests

A request stores `quality` (nil for normal) and `comparator` (nil for `=`, a game comparator, or `"any"`), so normal requests, and those from before quality, are unchanged in tags, blueprints and the remote interface.

- `quality.normalize` refuses an unknown quality or a hidden one other than normal. Without the Quality mod the game lists normal itself as hidden (probed on 2.1.24).
- Qualities compare by `level`, as the game's item filters do (probed on 2.1.24).
- Freighters take the highest matching quality first (the owner's choice, November 13, 2026).

## Keys and trips

Stock and promises are kept by key (`quality.key`): the name for a normal item or a fluid, `"item/quality"` otherwise. A trip of one key keeps its own cheaper path (`file_coming_one`, `logistics.honoured_one`); keep it.

## Room in a request depot

Room for several qualities is worked out as the game fills a chest, with empty stacks counted for a quality no stack has (`quality.absent`; the hidden `quality-unknown` is one, probed on 2.1.24), so a freighter never brings what must be spilled. Cargo of qualities the request no longer takes counts towards no demand but keeps its room.

## A freighter's quality

Cargo, fluid, speed and tank multiply by the quality's `default_multiplier`, read from the game so modded qualities count. The unit is made at that quality, so the game gives its health.

## A depot's quality

Better depots get the game's bigger chests and tanks. A rare tank's size is a hair over 40,000, so tank sizes are floored to whole units (`logistics.fluid_limit`).

A depot replaced by itself at another quality (upgrade order, or built over itself) gets a new unit number; `scripts/depot-upgrades.lua` moves everything to it and keeps its robot access, which the game turns back on ([depots and replacing](depots-robots-and-replacing.md)). `logistics.replaced` cuts the request to the new chest or tank, or a "Full loads only" request would wait forever.

Events, probed on 2.1.24: robots and platforms raise `on_*_mined_entity` (no pre-mined event), then the build. A player raises `on_pre_build` first; its cursor is read there (`storage.depot_builds`), since it can be empty by the time the old depot is mined (0.1.8 crashed on that).

## Robots and freighter requests

The game reads a proxy's insert plans back sorted by quality and joins those of one quality (probed on 2.1.24). So `depot.freighter_asks` keeps the order asked, and freighters put in by hand cancel the last asked first.

## Request panel

The quality row sits under the item and amount, so no comparator sits between them (the owner's report, November 14, 2026). It follows the request at each refresh, writing a drop-down only when it differs, so one a player has open stays open. A panel open in a save is rebuilt at a mod change: its drop-down indices would read today's quality list.

## Mod changes

A quality a mod removed is forgotten (`logistics.forget_lost_qualities`): requests for it (not "any") and its freighters become normal.
