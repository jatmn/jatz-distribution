# Freighter network window

The freighter network window (the owner's request, November 15, 2026) shows a force's freighters, depots and what its depots hold and request, item by item and fluid by fluid. It opens from the `jatz-network` shortcut. Its numbers come from snapshots collected a few depots per tick and shared by every player viewing the same force, so an open window never scans the whole network in one tick.

## Code

- `scripts/network-gui.lua`: the window, the snapshots and their refresh.
- `prototypes/shortcut.lua`: the `jatz-network` shortcut (toggleable, the freighter's icon, unlocked by `jatz-freight-system`).
- `control.lua`: calls `network_gui.refresh` every tick and `network_gui.on_configuration_changed` on a mod change.
- `scripts/request-gui.lua`: routes the GUI events to it (`on_gui_closed`, `on_gui_click`, `on_gui_selection_state_changed`, `on_gui_elem_changed`) and registers `on_lua_shortcut`, `on_gui_selected_tab_changed` and `on_player_changed_force`.
- `locale/*/` `[jatz-network]`: captions and the tooltips that define each number.

## The window

The shortcut opens the window in `player.gui.screen` and lights the shortcut; pressing it again, the close button, E or Esc (the window is `player.opened`) close it.

- **Controls.** A surface drop-down ("All surfaces", then each surface where the force has depots, by planet or space platform name), shown with more than one surface or with Space Age; and a filter: all stock and requests, unmet demand only, or stock without configured requests.
- **Overview.** All freighters of request and buffer depots (parked and out) and those out on the road, then a count of each depot kind: provider, request and buffer for items and fluids, and the Fuel depot (and other depots, such as Mining Drones' mining depot) under "Support".
- **Items and Fluids tabs.** Each has a badge with the number of resources listed, a resource picker (`choose-elem-button`, right-click clears it), two header lines, and resource rows.
- **Resource rows.** One line per resource, in fixed-width, right-aligned number columns shared with the headers, so values line up from row to row: for providers, requesters and buffers each, the stock held and a depot count; then "Still needed". Numbers are short (63.8k, 1.2M), zero is a dash, and the exact values are in the tooltips.
- **Paging.** Seven rows a page (`PAGE_SIZE`), which fit without scrolling at the default UI scale. Rows are sorted by unmet demand, then name. Below them: previous and next buttons, the page number, and the snapshot's age.

## What the numbers mean

`count_depot` reads each provider, request and buffer depot once per snapshot:

- **Stock** is what the depots hold. Item totals combine qualities; hovering a stock amount shows the breakdown by quality. A liquid request or buffer depot's parked freighter fluid storage (`depot.reserve`) counts as held.
- **Offering** (provider and buffer tooltips) is unpromised stock, `ledger.available`, which excludes what freighters have promised to load. Parked freighter fluid storage is held but not offered.
- **Requests** count depots with a request set, with the configured target.
- **Still needed** is `logistics.missing`: active requests less matching stock and inbound commitments, with each request's quality filter. Supply elsewhere is not subtracted.
- Disabled depots and depots marked for deconstruction neither offer nor add to "Still needed", but their stock and configured requests stay visible.
- Fuel depots and cargo on the road are not counted in held stock.

## Snapshots and refresh

`network_gui.refresh(tick)` runs every tick:

1. With no open windows it returns at once.
2. It drops state for invalid players, closes windows destroyed from outside (unlighting the shortcut), and reopens a window whose player changed force.
3. With no connected viewer it clears every snapshot field and returns.
4. A new snapshot starts when none is being collected and a viewed force has no snapshot, or 300 ticks (`INTERVAL`) after the last one finished. It lists every depot ID, sorted, and counts only the forces being viewed.
5. It visits at most eight depot IDs a tick (`PER_TICK`) across all watched forces. IDs whose depot is gone or invalid are skipped.
6. When the list is done, each still-viewed force's counts become its snapshot, stamped with the tick.
7. It updates at most one viewer a tick, rotating from `storage.network_viewer` so later viewers aren't starved: a full page render (`show`) for a viewer who hasn't seen the latest snapshot, otherwise just the snapshot's age label when it changed.

Clicks, the filter, the surface, the resource picker and tabs redraw from the cached snapshot (`show_cached`) without scanning.

### Storage

| Field | Holds |
| --- | --- |
| `storage.network_gui[player index]` | The viewer's state: force, filter, page, surface, chosen resource, and the snapshot tick and age shown |
| `storage.network_scan` | The snapshot being collected: sorted depot IDs, cursor (`at`) and partial counts per force. It survives saves and multiplayer joins, so collection is deterministic |
| `storage.network_data[force index]` | Each viewed force's completed snapshot |
| `storage.network_next` | The tick the next snapshot may start |
| `storage.network_viewer` | The last viewer updated, for the rotation |

Closing the last window, or no connected viewer, clears `network_scan`, `network_data`, `network_next` and `network_viewer`.

## Layout changes, force changes and mod changes

- The frame carries `tags.layout`, set to the `LAYOUT` constant. Bump `LAYOUT` whenever the window's element tree changes.
- `rebuilt(player, frame)` reopens a window whose `tags.layout` differs, which draws the cached snapshot. Both `show` and the age refresh call it before writing to the window's elements, so a window saved by an earlier build of the same version is rebuilt instead of erroring.
- A force change (`on_player_changed_force`, or a changed force seen by `refresh`) reopens the window at once, so no data of the previous force stays.
- `network_gui.on_configuration_changed` discards every snapshot and reopens every open window.

## Engine traps

- A GUI element can't be named like a `LuaGuiElement` member: an earlier version's item table named `items` failed in game. Pick child names that are not member names.
- The engine cannot raise `on_lua_shortcut` by script, so the check mod's network scenario calls that handler directly.

## Tests

- `tests/lua/control-events.lua` ("Network command center"): event wiring, multiplayer viewers, the per-tick budget, filters, layout rebuilds and the window's lifecycle.
- The check mod's `scenarios/network`, run by `tools/test_mod.py`, uses the real GUI and inventories and the mod's own helpers, with inbound commitments supplied explicitly in the scenario's own Lua state.
