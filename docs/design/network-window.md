# Freighter network window

The `jatz-network` shortcut opens a window (the owner's request, November 15, 2026) with a force's freighters, depots, and what its depots hold and request. The numbers and controls are in the [guide](../guide.md) and the locale tooltips.

## Code

- `scripts/network-gui.lua`: the window, snapshots and refresh.
- `prototypes/shortcut.lua`: the shortcut.
- `control.lua`: calls `network_gui.refresh` every tick and `on_configuration_changed`.
- `scripts/request-gui.lua`: routes GUI, shortcut and force-change events to it.

## Numbers

- Offering is `ledger.available`; "Still needed" is `logistics.missing`, which doesn't subtract supply elsewhere.
- Seven rows a page (`PAGE_SIZE`) fit without scrolling at the default UI scale.

## Snapshots and budget

An open window must never scan the whole network in one tick.

- `refresh` returns at once with no open window, and clears every snapshot with no connected viewer.
- A snapshot lists every depot ID, sorted, and visits at most `PER_TICK` IDs a tick, counting only viewed forces. A new one starts `INTERVAL` ticks after the last. Viewers of a force share its snapshot.
- Collection state is in `storage`, so it survives saves and joins and stays deterministic.
- At most one viewer is updated a tick, rotating from `storage.network_viewer`.
- Clicks, filters, tabs and paging redraw from the cached snapshot (`show_cached`) without scanning.

## Opening, pinning and surfaces

- A new window preselects `player.surface`: the surface viewed, so in remote view the planet or platform looked at (`physical_surface` is where the player stands). Rebuilds keep the window's selected surface, including an explicit All surfaces choice, even after the player travels.
- `show` falls back to all surfaces while the selected surface is absent from the snapshot, retaining the choice so a shared snapshot taken before its first depot doesn't lose it. A later snapshot selects it when present; choosing All surfaces explicitly clears the choice.
- Pinned (`state.pinned`), the window is not `player.opened`, so E, Esc and other GUIs leave it. Pinning sets `opened` to nil, which raises `on_gui_closed` for the frame; `on_gui_closed` ignores a pinned window. Unpinning makes it `opened` again.
- A rebuild through `open` (layout, force or mod change) keeps the pin and doesn't take `opened`. `close` forgets it, so the window opens unpinned.

## Layout and force changes

- The frame carries `tags.layout`, set to `LAYOUT`. Bump `LAYOUT` on any change to the window's element tree.
- `rebuilt(player, frame)` reopens a window whose `tags.layout` differs. Both `show` and the age refresh call it before writing to elements, so a window saved by an earlier build is rebuilt instead of erroring.
- A force change reopens the window at once, so no data of the previous force stays. A mod change discards every snapshot and reopens every window.

## Engine traps

- A GUI child can't be named like a `LuaGuiElement` member: an item table named `items` failed in game.
- `on_lua_shortcut` can't be raised by script, so the check mod's `scenarios/network` calls the handler directly.

## Tests

`tests/lua/control-events.lua` ("Network command center") and the check mod's `scenarios/network`.
