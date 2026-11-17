# Test results

Latest in-game results for the current artwork. The full screenshots and reports from every test round are kept in the private `jatz-distribution-archive` repository.

## Saved windows rebuild on an age update too (November 16, 2026)

PR #115 review follow-up (Pullfrog, on `e6e02e339c328f9b3c7d10345ef7e16bbdcd1c26`): only a full
render checked the window's layout tag. A window saved by an earlier build of this version that
already showed the current snapshot got no new render, and its next age-label update wrote to
`inner.paging.snapshot`, which the base build's tree lacks, stopping the tick handler. Every write
to the window now goes through the same check, so that update rebuilds the window from the cached
snapshot instead.

- `tests/lua/control-events.lua` restores an already-drawn base-build window (untagged, its label
  on `inner`) and advances ticks only: it failed with that error before the fix and now rebuilds
  with no inventory reads or new scan. Setup tests, Lua syntax, Luacheck, StyLua and whitespace passed.
- `tools/test_mod.py` (Factorio 2.1.24 headless) passed with base and Space Age, including the
  network scenario. `tools/emulate_ups.py` (standard) against `e6e02e3`: identical.

## Seven-row pages without a cut-off row (November 16, 2026)

PR #115 follow-up to the owner's in-game screenshot of `6a87e105e6f62b0766f32fccbee2ddf69475a77f`:
rows measure about 60 px at the default UI scale, so eight rows (about 480 px) overflowed the
440 px pane cap and the eighth row hid behind a scrollbar. Pages now hold seven rows and the pane
has no height cap, so a page always shows whole. The layout tag moves to 7 so open windows rebuild.

- `tools/test_mod.py` passed with base and Space Age; the Lua setup tests check a bounded first
  page of seven. Lint, emulator boundaries, releases, portal, package and whitespace passed.
- `tools/emulate_ups.py` (standard) against `683882b`: identical instructions, calls and deliveries.
  `tools/benchmark_ups.py` against `683882b` (GUI closed, three runs): mean update 1.129 → 1.135 ms,
  script 0.455 → 0.448 ms, p99 3.484 → 3.221 ms, same vehicles and deliveries; within run spread.
- **Still needed:** graphical confirmation that seven rows show with no scrollbar.

## Single-line network rows with named number columns (November 16, 2026)

PR #115 follow-up to the owner's screenshot of `9449454ab06d2518ea66b975efd7c6df0de3c910`
(misaligned rows, unclear counts, labels wasting space). Factorio 2.1.25 headless; Lua 5.2.4.

- Each resource is one line: its icon, then numbers only, in fixed-width right-aligned columns.
  The header names every column once: each role's depot icon and name over **Stock** and
  **Depots** (providers holding it) or **Requests** (depots requesting it), then **Still needed**.
  Per-cell depot icons and "offering"/"requesting" captions are gone; holding, offering, target
  and unmet details stay in each number's tooltip. Amounts of 10,000 or more are shortened
  (63.8k, 189k, 1.2M; exact on hover) and zero shows as a dash. Summary headings start at their
  icons. A layout tag rebuilds windows saved by any earlier build of this version.
- `tools/test_mod.py` passed with base and Space Age, including identical header/row column
  widths, right alignment, the role headings spanning their two columns, captions, counts and
  rebuilding an untagged window. `tests/lua/control-events.lua` (via `tools/test_mod_setup.py`)
  checks counts, tooltips, dashes and rebuilding untagged and older windows without a scan.
- Lua syntax, Luacheck, StyLua, Ruff, setup, emulator boundaries, releases, portal, package
  build/validation and whitespace passed.
- `tools/emulate_ups.py` (standard) against `683882b`: identical mean/p99/worst instructions,
  API calls, path requests, commands, freighters and deliveries. `tools/benchmark_ups.py` against
  `683882b`, three runs each: mean update 1.139 → 1.135 ms, script 0.458 → 0.451 ms, p99
  3.626 → 3.414 ms, same 1,512 vehicles out and 265,200 items/minute (GUI closed).
- Open-window probe (8 rows, 5,000 forced full-page refreshes, five alternating runs) against
  `9449454`: median 0.349 → 0.321 ms per refresh (ranges 0.340–0.412 and
  0.308–0.355); each row now has 8 cells instead of 21 elements. Scan limits unchanged.
- **Still needed:** graphical confirmation of the alignment and spacing, and live multiplayer.

## Row depot icon sizing and metric meanings (November 16, 2026)

PR #115 follow-up to the owner's screenshot and count/arrow clarification at
`3fe3c07d9a611e1d03e95b45218e3cedf70dd36e`. Runtime blob:
`scripts/network-gui.lua` `68489a8a55f2334cc281995212ec2b8ee2856f5d`.

- Restored resource/picker icons to 40 px while row/header depot symbols are 48 px, matching
  the readable summary icons. Matching margins retain the existing first-column alignment.
- Holding counts use natural-width left-aligned labels beside the depot image. Ambiguous arrows
  are removed; the other count explicitly says offering or requesting. Row height accommodates
  the larger models; window width, dividers, summaries, controls and data accounting are retained.
- `tools/test_mod.py` passed with base and Space Age, including native 40/48 px sizing,
  zero forced count-label minimum, left alignment, labeled activity count values, absence of arrow
  widgets, retained geometry/counts/quality, and rebuilding earlier same-version GUI layouts.
  Lua harnesses retain force isolation, shared work budget, cached controls and 61-viewer checks.
- Lua syntax, Luacheck 1.2.0, StyLua 2.5.2, Ruff 0.17.3, setup (16), emulator boundaries (6),
  releases (14), portal (7), portal content, package bytes/checksum and whitespace passed.
- Engine comparison against `683882b`, three alternating runs each: mean update 1.143 → 1.135 ms,
  script 0.454 → 0.450 ms, p99 3.345 → 3.582 ms, median worst tick 6.361 → 6.111 ms.
  Individual worst ticks overlapped (5.624–8.274 before, 5.914–6.425 after). Both variants retained
  1,512 vehicles out and 265,200 items/minute. No speedup or zero-cost claim; the GUI is closed here.
- Engine-free standard comparison against the upstream base was identical in instruction counts,
  API calls, path requests, commands, freighters and deliveries.
- The real-engine eight-row GUI API probe against the starting repair head measured median
  0.342 → 0.346 ms, with overlapping ranges, after 500 warm-ups and 5,000 refreshes per run,
  three alternating runs. Global scan/refresh limits are unchanged. This is one viewer's update
  work, not a graphical rendering or live multiplayer result.
- **Still needed:** graphical confirmation of depot-icon legibility, count proximity and clear
  labeled metrics, plus live multiplayer/save/load checks. The submitted screenshot shows the
  previous sizes and ambiguous arrows, not this candidate.

## Network window row separation and read-only summaries (November 16, 2026)

PR #115 follow-up to the owner's screenshot at `6f5ce9c8f767218155baf97671ea16d4d7ec1d12`.
Runtime blob: `scripts/network-gui.lua` `4c888a53bbe8b04843b4ad7997bd856e564c4e13`.
Factorio 2.1.25 headless; Lua 5.2.4.

- Added a native horizontal line under each resource row, with row visibility controlling the line.
  Widened the shared grid and increased row padding/spacing and the bounded scroll area.
- Depot/resource summaries use read-only 48 px sprites and adjacent depot counts; the picker,
  page arrows and close remain buttons. Header/metric depot symbols are 24 px rather than 16 px.
- `tools/test_mod.py`: base and Space Age passed, including native line direction/full width,
  read-only widget types, exact counts/zeros, icon sizes, shared header/row geometry and close/rebuild
  behavior. The event harness verifies both previous-draft layouts rebuild without inventory reads,
  as well as the existing force isolation, scan budget, cached controls and 61-viewer fairness.
- Lua syntax, Luacheck 1.2.0, StyLua 2.5.2, Ruff 0.17.3, setup (16), emulator boundaries (6),
  releases (14), portal (7), portal content, package bytes/checksum and whitespace passed.
- Standard engine comparison against `683882b`, three alternating runs each: mean update
  1.120 → 1.135 ms (+1.3%), script 0.445 → 0.458 ms, p99 3.419 → 3.618 ms, median worst tick
  6.354 → 6.575 ms. Individual worst ticks overlapped (5.227–8.345 before, 6.054–7.702 after).
  Both variants had 1,512 vehicles out and delivered 265,200 items/minute. These are GUI-closed
  measurements; the small timing increase is disclosed, with no speedup or zero-cost claim.
- Engine-free standard comparison against the upstream base was identical in instruction counts,
  API calls, path requests, commands, freighters and deliveries.
- The real-engine eight-row refresh probe against `6f5ce9c`, three alternating runs of 5,000
  refreshes after 500 warm-ups, measured median 0.330 → 0.338 ms. This is about 0.009 ms extra
  per full page, with overlapping ranges. Shared scan/render budgets are unchanged; this probe
  measures one viewer's GUI API work, not drawing or live multiplayer latency.
- **Validation still needed:** the new row rules, icon legibility, read-only appearance and roomier
  layout in the graphical client, plus live multiplayer/save/load checks. The supplied screenshot
  shows the previous layout, not this candidate.

## Network window proportions and alignment: screenshot repair (November 16, 2026)

PR #115 follow-up to the owner's graphical screenshot at `4403d7d2192036394341edf690baa2b3264638d4`.
Runtime blob: `scripts/network-gui.lua` `4c6299ad73a9f86083c1420c7ce4d84b065fe43e`.
Factorio 2.1.25 (build 88022), Linux x86_64 headless; Lua 5.2.4.

- The screenshot showed the first draft's uneven summary panels, mostly empty Other row,
  rectangular resource/picker slots and disproportionate active arrow. The repair uses one summary
  band with Fuel/Mining Drones in Support, native 40 px square slots, bounded status sprites and
  shared header/row table geometry. Primary numbers share label height and right alignment.
- `tools/test_mod.py`: base game and Space Age passed. The real GUI scenario checks equal header/row
  widths, padding, spacing and column widths; square resource/picker sizes; equal primary-value
  label height; centered depot columns; explicit sprite resizing; counts, quality and demand.
- Both development ZIPs use unreleased version 0.1.10. A saved previous-draft window can lack the
  new fleet container without a configuration-change event. The regression fails before the guard;
  it now rebuilds through the existing cached-open path, preserving counts without inventory reads.
  The event harness and real-engine scenario both check the rebuild.
- Lua syntax, Luacheck 1.2.0, StyLua 2.5.2, Ruff 0.17.3, setup (16 tests), emulator boundaries (6),
  releases (14), portal (7), portal content, package bytes/checksum and whitespace passed.
- Standard engine comparison against `683882b`, three alternating runs each: mean update
  1.131 → 1.138 ms, script 0.455 → 0.453 ms, p99 3.512 → 3.410 ms, median worst tick
  5.862 → 6.232 ms. Individual worst ticks overlapped (5.384–7.027 ms before, 5.576–7.185 after).
  Mean differences are within run variation; no speedup or tail improvement is claimed.
  Both variants had 1,512 vehicles out and 265,200 items delivered/minute. The GUI is closed here.
- Engine-free standard comparison against the upstream base was identical in instructions, API calls,
  path requests, commands, freighters and deliveries.
- The eight-row real-engine GUI update probe compared the repair with the starting draft:
  500 warm-ups and 5,000 forced refreshes per run, three alternating runs. Median 0.331 → 0.335 ms,
  with overlapping ranges (0.330–0.339 before, 0.328–0.337 after). No material change established.
  This is one viewer's API/update work; it does not measure drawing or multiplayer latency.
- **Validation still needed:** inspect this revised layout in the graphical client and perform the
  live multiplayer/save/load checks. The owner's screenshot proves the previous layout failed;
  it does not validate this revised layout. Shared scan and render budgets remain unchanged.

## Compact network window: automated checks passed; graphical and multiplayer checks pending (November 16, 2026)

Candidate `feat/network-gui-polish`, based on `683882b4f40f96286f6b1191f460882be4cca194`.
Runtime blob: `scripts/network-gui.lua` `989089feb2d33c54959befff1e05fd11b0df7eda`.
Factorio 2.1.25 (build 88022), Linux x86_64 headless; Lua 5.2.4.

- The production GUI groups item/liquid depots by role, keeps Fuel and optional Mining Drones
  counts, and uses resource/status icons with stock, request, offering and quality details on hover.
  The new layout expectations fail against the baseline's missing overview and pass on the candidate.
- `tools/test_mod.py`: base game and Space Age passed, including real GUI elements, depot icon/count
  overlays (including zero), resource icons, stock and demand, configuration rebuild and keyboard close.
  The network scenario uses explicit reservation/inbound state; road deliveries have their own checks.
- `tools/test_mod_setup.py`: 16 passed, including the existing shared inventory budget, force isolation,
  cached controls, disconnect/close behavior and fair updates for 61 fake viewers. These are production
  handlers with simulated engine objects, not a live multiplayer session.
- `tools/test_emulate_ups.py`: 6 passed; release tests: 14; portal tests: 7. Lua 5.2 syntax,
  Luacheck 1.2.0, StyLua 2.5.2, Ruff 0.17.3, portal content, package bytes/checksum and whitespace passed.
- Standard engine benchmark, three alternating runs per variant: mean update 1.125 → 1.124 ms,
  script 0.449 → 0.452 ms, p99 3.451 → 3.564 ms, median worst tick 5.811 → 6.286 ms.
  Individual worst ticks ranged 5.745–8.137 ms before and 6.199–7.110 ms after; no tail-latency
  improvement is claimed. Both variants had 1,512 freighters out and delivered 265,200 items/minute.
  This benchmark has the GUI closed; its per-tick execution path is unchanged.
- Engine-free standard comparison: identical mean/p99/worst Lua instructions and API calls,
  path requests, commands, freighter counts and deliveries.
- A separate run-owned headless probe measured real GUI updates with 24 depots and eight item rows:
  500 warm-ups, then 5,000 forced full-page refreshes, three alternating runs each. Median refresh
  cost was 0.353 → 0.329 ms after moving fixed status sprites to window creation and reducing repeated
  GUI lookups. This isolates refresh work for one viewer; it does not measure drawing or multiplayer
  latency. Shared scan/render budgets are unchanged, and depot counts are only rewritten when changed.
- **Still required:** inspect the window in a graphical client at normal resolution/UI scale, with long
  names and large counts, and perform the live multiplayer/save-load checks in `docs/testing.md`.
  Headless API checks and the fake-viewer tests cannot prove visual quality or live join behavior.

## Z-key freighter drops: automated checks passed (November 16, 2026)

Candidate `fix/z-drop-freighter-absorption`, based on `51c25b67643c4f1e07bf8ea57575f67f6d272d3b`.
Runtime blobs: `control.lua` 0cb049a6409006e2d49d536af156201511f16113, `scripts/request-gui.lua`
87f4ec3e77b7a0f8aa2c54636f2c81dd652bb6ee, `scripts/logistics.lua`
41e1ca5a424bcc2b765a6678be3f025e1c7df309.
Factorio 2.1.25 (build 88022), Linux x86_64 headless; Lua 5.2.4.

- The Lua event regression fails on the baseline's missing single-item-drop registration and
  passes with the fix. It checks the destination supplied by the event, delayed cursor
  notifications, unrelated drops, providers and a stale carried count. Its event-name fake
  rejects unknown names, checked against the 2.1.25 API.
- The leftover-removal regression fails at the starting PR head `422f8f6`, in both the
  real-handler Lua test and the headless scenario. With the repair, request and buffer
  depots immediately absorb one dropped freighter after some or all observed leftovers
  were removed, preserving remaining leftovers through the delayed cursor notification.
  The scenario models that extraction with real inventory removal, between dispatch and drop.
- `tools/test_mod.py`: passed with the base game and Space Age, including the new
  `drop-freighters` scenario's real inventories, request and buffer slots, robot-request
  trimming, overflow, unrelated items, cargo and a working burner inserter.
- `tools/test_mod_setup.py` (16 tests), `tools/test_emulate_ups.py` (6 tests), release and
  portal tests, package validation, Lua syntax, Luacheck 1.2.0, StyLua 2.5.2, Ruff 0.17.3
  and whitespace checks passed.
- Standard engine benchmark against `51c25b6`, three runs per variant: mean update
  1.936 → 1.899 ms; run spread 0.071 ms before and 0.025 ms after, so no speedup is
  established. Vehicles out (1,512) and deliveries/minute (265,200) were identical. Engine-free emulation was
  identical in instructions, API calls, path requests, commands and deliveries.
- **Graphical check passed (owner-confirmed):** Z-dropping loads the depot as expected and
  loaders do not immediately extract the dropped freighter. This confirms the observed
  keyboard-drop outcome; the exact event order was not instrumented, and individual modded
  inserter/loader variants were not recorded. The headless scenario supplies the event payload
  to the production handler because the engine cannot raise this event by script.

## Buffer pull wording: checks passed; text only

**November 16, 2026.** PR #112 review repair on `8ad87c90f1d7021089e78ada74e8c5918f63998f`, against
`main` at `51c25b67643c4f1e07bf8ea57575f67f6d272d3b`. Locale and documentation only; no code,
test or behaviour change, so Factorio and the UPS benchmark were not rerun.

- The `searching` status text and the guide's status legend now name lower-priority buffers for a
  buffer depot with the setting, as `no-provider` and `unreachable` already did.
- The setting description, the guide and `AGENTS.md` state the rule as where a buffer sends its
  freighters. A pickup a request depot sent before it was swapped for a buffer depot still loads,
  as the swap checks require; the guide and `AGENTS.md` say so, and that a buffer pull whose source
  became a request depot takes nothing there.
- `tools/test_mod_setup.py`: 16 passed; `tools/test_releases.py`: 14 passed;
  `tools/test_portal_page.py`: 7 passed; `tools/test_ci_changes.py`: 18 passed (1 skipped);
  `git diff --check` passed.

## Buffer pulls from a replaced source: passed (automated)

**November 16, 2026.** PR #112 review repair on `7bbe41722aeebd2f484ad7be3dcbc1b2968f5079`, against
`main` at `51c25b67643c4f1e07bf8ea57575f67f6d272d3b`; Factorio 2.1.24 headless on Linux x86-64.

- A buffer pull whose source buffer was replaced by a request depot on the way loaded that depot's
  stock (10 of its 20): pickup checked the priority rule only while the source was still a buffer.
  It now takes nothing there and looks for another source. A source replaced by a buffer still
  gives its load. The new swap check fails on the previous revision.
- `tools/test_mod.py`: passed with base game and Space Age. The check mod now waits for the upward
  buffer rows, which are on their own surface, before it reads them.
- `tools/test_mod_setup.py`: 16 passed; `tools/test_emulate_ups.py`: 6 passed;
  `tools/emulate_ups.py --base` against that `main`: mean +0.1%, p99 +0.2%, worst +0.1%; API calls,
  path requests, commands, freighters and deliveries unchanged.
- `tools/benchmark_ups.py --compare origin/main`, standard preset, three runs each: mean update
  1.393 ms before and 1.389 ms after, within run variation; 1,512 freighters out and 265,200
  items/minute delivered in both.
- StyLua 2.5.2, Luacheck 1.2.0, Lua 5.2 syntax, `git diff --check`, and the CI package job's release,
  portal and package build/validation steps passed. No visual changes.

## Pre-update pickups and disabled buffer scans: Lua checks passed; Factorio not rerun

**November 16, 2026.** PR #112 review repair on `a545788313b39dcef11489c3c1b5beb12c1a6c95`, against
`main` at `51c25b67643c4f1e07bf8ea57575f67f6d272d3b`. No Factorio executable was available, so
`tools/test_mod.py` and `tools/benchmark_ups.py` were not rerun for this revision.

- A requester dispatched to a buffer on `main`, its home replaced by a buffer and saved before
  pickup, received 0 of 10 after reloading with the previous PR revision. A trip without an
  admission record now counts as a requester's pickup, as no earlier version sent buffers to buffers.
  The same state, made by `main`'s own `scripts/logistics.lua`, now delivers 10 and leaves 10, as
  on `main`, with the setting on or off. The changed swap check fails on the previous revision.
- With the setting off, buffer searches read it once each instead of once for each other buffer.
  For 400 stocked buffers over 60 `on_tick_share` ticks (Lua instructions in `scripts/`):
  `main` 2,049,416; previous revision 3,963,816 with 159,600 setting reads; this one 2,214,616 with
  400. A new logistics check fails on the previous revision.
- `tools/test_mod_setup.py`: 16 passed; `tools/test_emulate_ups.py`: 6 passed;
  `tools/emulate_ups.py --base` against that `main`: mean +0.1%, p99 +0.2%, worst +0.1%, deliveries unchanged.
- StyLua 2.5.2, Luacheck 1.2.0, Lua 5.2 syntax, Ruff 0.17.3, `git diff --check`, and the CI package
  job's release, portal and package build/validation steps passed. No visual changes.

## Buffer pickup after home replacement: passed (automated)

**November 16, 2026.** PR #112 repair working tree on `0b1d467b72550e9b30f4f69a933864cb1de59b33`,
against `main` at `51c25b67643c4f1e07bf8ea57575f67f6d272d3b`; Factorio 2.1.24 headless on Linux x86-64.

- `tools/test_mod.py`: passed with base game and Space Age, including undo, bonuses, network and
  Quality scenarios. The new engine case dispatches a requester to a buffer, applies a scripted
  request-to-buffer upgrade before pickup, and requires all 10 promised wood at home and 10 left
  at the source. Equal priorities prevent a fresh buffer pull from hiding a cancelled pickup.
- `tools/test_mod_setup.py`: 16 tests passed; `tools/test_emulate_ups.py`: 6 passed. Added swap
  checks cover both startup values and requester source modes, new and older saved trip records,
  module/configuration reload, both reroute admission changes, and older buffer trips' priority
  refusal. Reload here uses the Lua harness; it is not a second Factorio process save/load test.
- The home-replacement regression fails on the starting PR code. Isolated mutations omitting the
  reroute update or legacy snapshot, or bypassing an older trip's priority guard, fail the intended
  delivered-stock assertions. The existing buffer-origin priority refusals pass with the repair.
- Lua 5.2 syntax, Luacheck 1.2.0, StyLua 2.5.2, package build/validation and `git diff --check` passed.
- Standard UPS: three paired runs against that `main`; stress: one paired run. Both kept the same
  delivered stock and active freighters. These use the default provider/request maps, not a large
  enabled buffer-chain network; no speed-up claimed. No visual changes or graphical-client check.

## Buffers pull by priority: passed (automated)

**November 15, 2026.** Against `main` at `a826850320c5b1f5b2f3658c895fb0a56628f9be`,
Factorio 2.1.24 headless on Linux, base game and Space Age.

- `tools/test_mod.py`: the packaged mod passed, including undo, bonuses and Quality scenarios.
  With the new startup setting enabled, item and liquid buffers at priorities 2, 5 and 8 moved
  stock upward: the middle buffer refilled after the central one collected its stock. A second
  priority-2 buffer received nothing. The liquid arrived at its original 80 degrees.
- `tools/test_mod_setup.py`: 16 tests passed. The logistics checks cover disabled, equal and
  descending priorities for both kinds, completed transfers, shared ranking with normal providers,
  and priority changes during a pending search and before pickup. The new upward-transfer check
  fails on the original production code, which admits no buffer source for another buffer.
- `tools/benchmark_ups.py --compare origin/main`: standard preset, three runs per revision.
  Mean update was 1.124 ms before and 1.120 ms after (within run variation); deliveries remained
  265,200 items/minute with 1,512 active freighters. This checks default settings on the existing
  benchmark map; it does not measure a large network of opt-in buffer chains.
- No graphics changed; graphical-client inspection was not performed.

## Freighter network command center: automated checks passed; visual check pending

**November 15, 2026.** Uncommitted `feat/network-supply-demand` candidate based on
`a826850320c5b1f5b2f3658c895fb0a56628f9be`; network module blob `b313d80ba593ddbcae3512229fb9229148a24008`.
Factorio 2.1.24 (build 87808), Linux x86_64 headless; Python 3.13.5 and Lua 5.2.4.

- `tools/test_mod.py`: passed with base game and Space Age. The new network scenario exercises
  real tabbed GUI construction, item/fluid and depot-role stock, quality-aware need, reservations,
  explicitly supplied inbound commitments, parked fluid storage, rebuilding and engine close events.
- `tools/test_mod_setup.py`: 16 tests passed, including the control-event GUI regressions;
  `tools/test_emulate_ups.py`, release and portal/package validation passed. Lua syntax,
  Luacheck 1.2.0, StyLua 2.5.2, Ruff 0.17.3 and whitespace checks passed.
- The new first-open regression fails against the baseline GUI and its original event wiring.
  Independent review found starvation with 61 simultaneous viewers; the added regression fails
  before the correction and passes with rotating viewer service. Multiplayer clients themselves
  were not connected; the harness checks shared work, isolation, disconnects and closed-window behavior.
- Repository engine benchmarks (three runs per variant, GUI closed): standard mean update
  1.334 → 1.353 ms (+1.4%); stress 7.220 → 7.275 ms (+0.8%). Delivery totals and active freighters
  were identical; changes are small relative to run spread. These measured the initial candidate;
  later open-window fairness/tooltip changes leave the measured closed-window path unchanged.
  Final-tree engine-free emulation: +0.1% mean instructions, unchanged API calls and deliveries.
- Separate real-engine GUI probes, one player and 600 stationary depots: worst open-window GUI tick
  6.320 → 0.591 ms with one resource per chest; 30.616 → 7.227 ms with 48 resources per chest.
  The dense probe's mean GUI work rose 0.391 → 0.418 ms while being spread across ticks. These
  single-run timings exclude other game update work and graphical rendering; they do not guarantee
  latency on every factory or machine. No inventory reads occur once all connected viewers close.
- **Untested:** graphical layout, normal UI scales and live multiplayer join/latency. The graphical
  client gate remains pending before submission; headless runs are not visual approval.

## Quality: passed (automated)

**November 14, 2026.** Quality support rebased onto `016bc60fc762a541be01dec1cfaa5946c271bb7e`
(after the freighter bonuses beside the Bonuses window, #101), Factorio 2.1.24 headless on Linux
(build 87808), base game and Space Age with Quality.

- `tools/test_mod.py`: packaged mod passed with the base game and Space Age, including the new
  quality scenario and #101's bonuses scenario. That covers requests by quality, better freighters and depots, a robot upgrade
  and a player's fast replace, and blueprints. Against the base the same scenario fails: normal items
  arrive instead of rare, a rare freighter brings 100 with a 20 MJ tank, and an upgraded depot loses
  its request and freighters.
- `tools/test_mod_setup.py`: all 15 setup tests passed, including the new `tests/lua/quality.lua`
  (133 checks) on the shared `tests/lua/harness.lua`, the logistics harness's 768 the same as on
  `main`, and the control-event checks for upgrades, the quality panel and its fuel tooltip.
- An independent review found four defects: room by quality when planning, rare cargo refiled as
  normal, a hand-mined upgrade-marked depot, and a Fuel depot's refuel stop. All are fixed, each with
  a check that fails before its fix.
- A second review (of `7145d36`) found two more, both fixed with checks that fail before the fix: a
  provider upgraded while a freighter was on its way kept that freighter's promise filed under the
  old depot, so it was never let go (in the engine, 30 plates restocked after the first 30 were never
  fetched; now all 60 arrive); and freighters waiting for a free truck chest stack took the quality
  of the next one asked for (21 normal and 1 rare asked for brought 2 rare; now 1 normal and 1 rare).
- A third review (of `690429b`) found a freighter on the road kept its quality's speed after a mod
  change removed that quality (on 2.1.24, a rare freighter kept 0.1056 after the save was loaded
  without Quality; now 0.066, a normal one's), and the depot's fuel tooltip said a full tank holds a
  normal freighter's 20 MJ beside a full rare freighter's 32 MJ. Both are fixed, with checks that fail
  before the fix; the fuel descriptions now give 20 MJ as a normal freighter's tank and say a depot
  sends its best freighters first.
- A fourth review (of `52f7016`) found four more, all fixed with checks that fail before the fix:
  cargo of a quality the request no longer takes (changed after it was loaded) had no room kept for
  it, so another freighter took the stack and it was spilled (in the engine, with one stack, an epic,
  a "≥ epic" and a normal request all spilled the rare plate; now it goes in); a player's fast
  replace at another quality left the removal's undo action without the depot's settings (now the
  quality scenario finds them there); a quality asked for again from robots joined its earlier ask,
  so a freighter put in by hand cancelled the wrong one (rare, normal, rare and a rare by hand
  brought 2 rare; now 1 rare and 1 normal); and a freighter whose promise a request change dropped
  searched for a provider again after every answer (now it goes home empty).
- A fifth review (of `0e0a596`) found two more, and the owner one in the panel, all fixed with
  checks that fail before the fix: freighters asked of robots at several qualities were cancelled
  in the order the game reads plans back (sorted by quality), not the order asked (in the engine,
  rare then normal asked and a normal put in by hand left a normal asked and dropped the rare; now
  the rare stays asked); a freighter out had no stack kept to come back to (in the engine, 90 normal
  and 1 rare, the rare sent and an epic put in meanwhile: the rare was spilled; now all 92 are home);
  and the panel's comparator stood between the item and its amount, reading "uncommon wood > 9600"
  (now a "Quality" row under them reads "Quality > uncommon"). `info.json` now lists `quality` as an
  optional dependency.
- A sixth review (of `9e4e25f`) found two more, both fixed with checks that fail before the fix: a
  depot replaced by itself at a lower quality kept a request for more than its smaller chest holds, so
  with "Full loads only" it waited for a load that never fits (in the engine, a rare request depot a
  player builds a normal one over kept its rare chest's request; now it is cut to the normal chest,
  `logistics.replaced` using `set_request`'s limit for every replacement, role swaps included); and a
  request panel still open in a save kept its quality drop-down's index while the qualities changed,
  so the request took another quality than the one shown (now open panels are built again at a mod
  change; checked with the real handlers, a save and load of the panel in the engine was not).
  The branch now includes `main` with the request and buffer depots replacing each other (#103,
  `be2531b`): `tools/test_mod.py` passes again with base game and Space Age, the quality and undo
  scenarios included, and all 16 setup tests pass.
- A seventh review (of `aaaa62e`) found one more, fixed with a check that fails before the fix: an
  open request panel's Quality row never followed a quality set outside it (another player, Copy and
  Paste settings, the remote interface), so choosing another item put the row's old quality back over
  the request's (with the real handlers, an `uncommon ≥` request became normal `=`). The row now
  follows the request at each refresh, and choosing another item keeps the request's quality (checked
  with the real handlers; the panel was not checked in the engine).
- StyLua 2.5.2, Luacheck 1.2.0 and Ruff 0.17.3 passed; the emulator tests passed.
- Not checked: the request panel and freighter slot tooltip in the graphical client.

The deterministic standard emulator comparison against `016bc60` reports +2.7% mean Lua
instructions (+3.6% p99, +3.7% worst tick), +0.4% API calls, and identical paths, commands, vehicles
and deliveries. In game, standard preset, five alternating runs per revision against `016bc60`, on
an AMD Ryzen 9 6900HX (Linux):

| | Mean update (ms) | UPS | Script (ms) | Pathfinder (ms) | p99 (ms) | Max (ms) | Run spread (ms) | Vehicles out | Delivered/min |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Before | 1.983 | 504 | 0.676 | 0.069 | 5.626 | 11.380 | 0.086 | 1510 | 264720 |
| After | 1.953 | 512 | 0.668 | 0.063 | 5.514 | 9.283 | 0.108 | 1510 | 264720 |

## Explicit runtime states: passed (automated)

**November 9, 2026.** Refactor against `af0429cd7673a3674e3b8a50d301616fd572a3de`,
Factorio 2.1.24 headless on Linux. Saved freighter flags become independent named movement,
search, service and fuel states; fleet, undo and road ownership have compatible migrations.
See [Runtime state and transition ownership](runtime-state.md).

- `tools/test_mod_setup.py`: all 14 setup tests passed, including the Lua logistics,
  control-event and depot-road harnesses and the runtime compiler/local-limit checks.
- Lifecycle invariants run at each logistics checkpoint. New sequences exercise saved loading
  and underground-search states, repeated migration, stale answers after exit, repaint identity,
  once-only refunds, old fleet targets, undo records and road ownership.
- A delayed approach failure ending a newer tunnel crossing reproduced on the base and passed
  after adding the command-generation guard to the underground failure branch.
- `tools/test_mod.py`: packaged mod passed with the base game and Space Age, including the
  automated undo scenario. These engine runs use fresh scenarios; migration callback ordering
  is covered by the Lua harness, not by a captured player save.
- StyLua 2.5.2, Luacheck 1.2.0 and Ruff 0.17.3 passed; release/package and emulator tests passed.
- A focused independent static review found no actionable regression in transitions or migrations.

The deterministic standard emulator comparison reports +3.3% mean Lua instructions (+2.1% p99,
+3.0% worst tick), with identical API calls, paths, commands, vehicles and deliveries. The
in-game standard comparison below has three alternating runs per revision. Run-to-run variation
is larger than the median change, so it establishes no speed improvement.

| | Mean update (ms) | UPS | Script (ms) | Pathfinder (ms) | p99 (ms) | Max (ms) | Run spread (ms) | Vehicles out | Delivered/min |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Before | 1.276 | 784 | 0.499 | 0.056 | 4.146 | 11.678 | 0.272 | 1510 | 264720 |
| After | 1.214 | 824 | 0.488 | 0.053 | 3.517 | 9.975 | 0.132 | 1510 | 264720 |

## Mod: passed (automated)

**November 3, 2026.** `tools/test_mod.py` with Factorio 2.1.24 (build 87808) headless on Linux, loading the packaged `jatz-distribution_0.1.0.zip`. It ran once with the base game only and once with Space Age, and both passed:

| Check | Result |
| --- | --- |
| All 9 recipes (seven depots, the freighter, road) available from the start and free | Passed |
| Each of the 7 depots placed in all 4 directions, as a ghost and for real (28 each) | Passed |
| Full rotation of every placed depot (112 steps) | Passed |
| All 20 pipe ports connect; containers hold items, tanks hold fluid | Passed |
| A character enters the fuelled freighter and drives it (28.5 tiles in 2 seconds) | Passed |
| Freighter at 75% size in the graphical client | Seen in play by the owner up to November 3, 2026, who then asked for 60% |
| Freighter at 60% size (sprites and boxes; box 0.9 × 2.7 tiles, stored by the engine as 0.898 × 2.695, checked headless) in the graphical client | Untested |
| New 64 px icons in the graphical client: depots face south and the freighter heads south-east | **Passed:** checked by the owner on November 3, 2026, in the inventory and Factoriopedia |
| Loading zone marking in the graphical client: one tile beyond the footprint on the loading side, south when placed unrotated, worn rather than bright white | **Passed:** checked by the owner on November 3, 2026 (Provider depots on desert) |
| Marking drawn above decoratives (plants, ground cover): moved from `decals` to `ground-patch-higher2` after the owner saw plants drawn over it | Untested since the change |
| Decorative rocks drawn over the marking (`floor`/`object` layers): building or turning a depot now clears decoratives overlapping its loading zone tile. Covered by the automated check (28 zones cleared, decoratives beyond kept) | Untested in the graphical client |
| Menu placement in the graphical client: our row directly above the car and tank row, ordered provider, request, buffer, liquid provider, liquid request, liquid buffer, fuel, freighter | **Passed:** checked by the owner on November 3, 2026, alongside the Yuoki mods |
| Delivery over road: a provider with 50 iron plates and a request for 30, 20 tiles apart, joined by a U-shaped road with concrete on the straight line. A freighter drove out and back along the road (10-tile detour) and the request depot received exactly 30; the provider kept 20 | Passed |
| Freighters stay on road: every 10 ticks, all four corners of every delivering freighter stood on road (45 samples) | Passed |
| A request depot whose loading zone is an isolated road tile receives nothing and reports no route; one without road at its loading zone sends no freighter and says so | Passed |
| Cargo keeps item data: modular armor arrives with its solar panel; with Space Age, food that left 50% spoiled arrives at least as spoiled | Passed |
| A request depot with no room fetches nothing (provider keeps all 50 copper, status "full") | Passed |
| A freighter destroyed on its way is replaced, and the request is filled (30 steel) | Passed |
| Enemies (November 4, 2026, Factorio 2.1.24 headless, base game and Space Age): a medium biter held still on the road is killed by the freighter's impact damage, the 10 iron ore is still delivered, and a player beside the road is unhurt. Behemoth biters kill another freighter (physical damage), which explodes and leaves the car's wreck (`car-explosion`, `car-remnants`; neither appeared before this change); its depot is left with 2, asks robots for 1 at once, gets 10 copper ore from its other freighters, and robots bring the replacement (3 again). The destroyed-freighter depot above is restocked to 3 by robots too. Freighters show up in the pollution statistics. With the code before this change, a freighter killed by biters went back into the slot and nothing was requested | Passed headless; graphical retest pending |
| A freighter killed by enemies fails its command at 0 health before it is gone: it is lost, not taken home, and its provider isn't put on cooldown (Lua checks against a fake runtime) | Passed headless |
| A freighter killed by a script (`LuaEntity::die`, as from the console) fails its command with its health still showing (500): it is lost, not put back into its depot's slot, and the depot asks robots for a replacement (Lua checks; and November 6, 2026, Factorio 2.1.24 headless: a probe killing a freighter just after it left home and while it loaded at the provider, storage empty: slot 1, out 0, 1 requested; before the fix, slot 2 and nothing requested, the owner's "instant restock"; `tools/test_mod.py`'s destroyed pair now uses `die()` and requires the request, base game and Space Age) | Passed headless |
| A failed command is acted on the tick after only while it is still the freighter's latest: a loaded freighter whose way home fails, its request depot then removed in the same tick, takes its cargo back to the provider; one re-planned meanwhile keeps its route and puts no provider on cooldown (Lua checks; and November 7, 2026, Factorio 2.1.24 headless, a temporary probe mod destroying the request depot from inside the freighter's failure event, after this mod's handler: 100 iron plates back in the provider, none spilled; with the deferral alone, all 100 spilled, as Pullfrog's review of 66d57e9 found) | Passed headless |
| Construction robots repair a damaged freighter: one at 100 of 500 health within a roboport's reach, with repair packs in storage, is repaired to full (`tools/test_mod.py`, base game and Space Age, November 6, 2026); a probe saw a robot follow a delivering freighter and repair it while it stood at the provider (200 to 232, carried over to its repainted unit); on the road the freighter outruns the robot. Before, the freighter was `not-repairable` and no robot came | Passed headless |
| A freighter lost while its depot's chest has no free stack: the depot keeps its target and robots are asked for the replacement once a stack is free (Lua checks; and November 5, 2026, Factorio 2.1.24 headless, base game and Space Age, a temporary probe filling the chest at the loss: target 3 kept, request made once cleared, depot back to 3; without the fix, target nil and no request) | Passed headless |
| Freighters asked for while the chest has no free stack add up: 5 then 1 more keep a target of 6, a match to 6 adds nothing, and once a stack is free all 6 are requested in one plan, the target staying 6 (Lua checks; and November 5, 2026, Factorio 2.1.24 headless, a temporary probe: coming 6, target 6; without the fix, coming 1, target 1) | Passed headless |
| An enemy removed by another's death while a freighter runs them over is skipped, not read; nothing is hit once the freighter is gone (Lua checks; and November 5, 2026, Factorio 2.1.24 headless, a temporary probe whose death handler removes the neighboring biter: no error; without the fix, "LuaEntity API call when LuaEntity was invalid" in `on_nth_tick(10)`) | Passed headless |
| A request changed from plastic to circuits mid-trip loads no plastic | Passed |
| Freighters stop to load and unload: November 4, 2026 repair of PR #25, based on `52388cb`, with `LOADING_TICKS = 60`. Factorio 2.1.24 headless, Linux, base and Space Age: 63 ticks measured at both loading zones (bounds 50–70). The same unit stays valid through loading, driving home and unloading; all 3 freighters return to the slot. The one-second checks fail on the original 120-tick code (123 ticks measured). The owner reported the original pause was too long and the truck disappeared; premature loss did not reproduce headless. Removal after unloading returns the freighter item to its slot. | Passed headless; graphical retest pending |
| Cargo paint: November 4, 2026, Factorio 2.1.24 headless, Linux, base and Space Age. The connected pair's freighter reaches the provider as `jatz-freighter-drone` (empty, light grey), and loading iron plates replaces it, where it stood, with `jatz-freighter-drone-233` (iron ore's map color), which drives home, unloads and parks. Since this change the freighter is a new unit from loading onward, so the row above's "same unit" now holds up to loading and from loading to unloading. Water's paint is `jatz-freighter-drone-023`. 218 freighter prototypes load. Stickers: a freighter loading with a fire-like sticker (10-tick damage interval) stuck to it is not swapped, so the same sticker stays on the same freighter, and it takes iron plates' paint on the road home once the sticker wears off (90 ticks), delivering its 10 plates. Swapping lost stickers at first (Pullfrog's review of `a2c4274`), and recreating them restarted their damage cycle (its review of `14c2d32`); this check fails on both versions | Passed headless; colors untested in the graphical client |
| Cargo colors with overhaul mods (data stage only, scratch copies, not shipped): Bob's mods and Angel's refining, petrochem, smelting and bioprocessing from their `dev2.1` branches (November 4, 2026). Non-placeable items with a color: 476 of 514 with Bob's and Space Age, 842 of 923 with Bob's and Angel's (no Space Age); base game ores and plates keep their colors under Angel's. Krastorio 2 has no 2.1 version yet and its data stage fails on 2.1, so it is unmeasured | Measured headless |
| Delivering freighters slowed to Transport Drones' default speed: November 5, 2026, merged with `c7c1b65`, with `movement_speed = 0.066` (was 0.2; Transport Drones sets 0.066 before speed research, `script/transport_drone.lua` at `15c42d1`), about 4 tiles a second instead of 12. Factorio 2.1.24 headless, Linux, base and Space Age: deliveries finish at tick 1441, before the 1700-tick deadline. The check waits for the U-road depot's status, which updates at its next once-a-second dispatch, and the mended-road bound now scales with the drone's speed (535 ticks measured, bound 764; 520 at the old speed, as before) | Passed headless; graphical check of the slower driving pending |
| Road cut behind a loaded freighter: all 30 gears go back to the provider, none to the request, provider cooled down; the gears are back in the provider 63 ticks after the cut, the freighter's 1 s stop to unload included (2 ticks before freighters stopped; it used to take about 6 s of standing stuck) | Passed |
| Mending a gap in a road: delivery done 318 ticks (about 5 s, round trip and its two 1 s stops included; 195 ticks before the stops) after the repair, instead of waiting out the retry cooldown | Passed |
| Nearer of two providers removed mid-trip: the same freighter goes on to the other one and delivers | Passed |
| Request depot removed mid-trip: its freighter leaves at once and the provider keeps its stock | Passed |
| Provider nearest by road chosen: 8 tiles away in a straight line but 34 by road loses to 16 tiles on a straight road (all 10 coal from the farther one) | Passed |
| No road route to any provider or buffer depot: no freighter is sent at all | Passed |
| Depot road: laid under each depot's loading zone (over grass, which it hides); road ending one tile short of both depots' zones delivers (5 poles) | Passed |
| Depot road removed with its depot, putting back concrete and grass; existing road and a tile laid over depot road stay; a shared tile keeps its road until the second depot goes; nothing laid on water | Passed |
| Depot road when turning a depot, and mining or covering it by hand (Lua checks against a fake runtime; needs a player in game) | Passed headless; untested in the graphical client |
| Depot road art blending into player road, in the graphical client | Untested |
| Freighter slot: two freighters sent 60 ticks apart, one to each of two providers (30 + 30 sticks), all 5 back in the slot; no freighters, no trips (status "Waiting: no freighters"); freighters in the chest move to the slot; a destroyed request depot drops all 102 of its freighters (full slot of 100 plus 2 still in its chest) and a script-removed one its 3; the remote interface adds only up to the slot's limit of 100; 25 freighters are requested and taken away across several chest stacks | Passed |
| Mining a request depot hands all its freighters (slot and out) to the miner; the slot's one-stack limit counts freighters out; a freighter destroyed on the road is lost (Lua checks against a fake runtime) | Passed headless |
| Freighters requested as from remote view: 4 requested, a further request capped at the 5 that fit, cancelled (9) and 3 requested again; construction robots deliver them from storage into the slot (4 there, 2 left in storage) | Passed |
| Freighters taken away by robots (remote-view right-click): a removal marked and cancelled puts its freighter back; 2 marked are carried back to storage (slot 2, storage 4) | Passed |
| Slot clicks routed through control.lua: a freighter ghost requests (right-click: one), an empty cursor in remote view cancels, a remote right-click removes (again: cancels), remote view never moves items by hand; pipette over the slot picks up a freighter or its ghost, and only over the slot (Lua checks against a fake runtime) | Passed headless |
| Status light in the request panel (green, yellow, red, grey, with the status as tooltip), in the graphical client | Untested |
| Blueprint of a request depot keeps its request (tag) and freighters (insert plan for 3); the ghost built from it asks for 7 wood with 3 freighters requested; matching 1 to 3 requests 2; requests over the limit after filling by hand are trimmed (6 + 7 in → 3) | Passed |
| Copy and Paste settings, blueprint setup and building from a tagged ghost, routed through control.lua (Lua checks against a fake runtime) | Passed headless |
| Undo of a removed depot: its settings as it went (on robot pre-mining, or before mining by hand, chest freighters counted) go on the right removal action, newest to newest at one spot; undo puts them on the ghost (keeping its other tags), also when undone before the tag; the depot built from it has its request and asks for its freighters; a cancelled deconstruction forgets it, a mining attempt that leaves it standing doesn't (robots taking it later still save it as it goes, set back to defaults too), a failed hand mining leaves nothing waiting, three depots cut in one item are located with one read of it and their removals read none, a platform taking one before it is located and a stack trimmed under one still find their action, a depot mined by hand keeps its own action when a replacement at its spot is marked before the tagging (in the mining's tick or the tagging's), an undo bringing no ghost back leaves waiting settings alone, undoing anything else searches for no ghost, and with the history at its limit (100 items, the oldest dropped as one is pushed) two hand minings at one spot each keep their own, as does one with a replacement marked at its spot, and robots then find the replacement's action by its mark without reading an undo item, and two hand minings at one spot in adjacent ticks, the second before the tagging, each keep their own (Lua checks against a fake runtime). Real engine with a player (`--test-scenario jatz-distribution-check/undo`, Factorio 2.1.24): a cut depot changed to 8 wood and 5 freighters before robots took it is saved with 8 and 5 (the first version saved its 5 and 3 from marking), a depot mined by hand with 1 in its slot and 2 in its chest is saved with 3 (the first version: 1), their ghosts are rebuilt by robots and by the player with their request and freighters, and a cut depot the player then fails to mine (a full inventory) and changes to 9 wood is saved with 9 when robots take it (the second version saved 5); with Space Age, a liquid request depot cut on a space platform is saved with its water request and 2 freighters (the third version saved nothing) and rebuilt by the platform from its ghost with both; a depot mined by hand with 2 freighters and a bare replacement marked at its spot in the same tick keep 2 and 0 on their own actions (the fifth version lost the 2); with the history filled to 99 items, two depots mined by hand at one spot in a tick (2 freighters, then bare) keep 2 and 0 (the sixth version lost the 2); a depot mined by hand with 2 freighters and a bare one at its spot mined the next tick keep 2 and 0 (the seventh version swapped them) | Passed headless. The undo key press itself can't be scripted (test scenarios aren't simulations; no call applies an undo item): graphical client untested |
| Copy and Paste settings, copy and paste, and blueprints of request depots, in the graphical client | Untested |
| Ctrl+click of freighters into a request depot: 95 + 15 fills the slot to 100 and gives 10 back, none left in the chest; iron plates moved in with them stay in the chest; routed through control.lua for inventory changes and ctrl+click on the depot | Passed headless |
| A freighter request Factorio drops when part of it is filled by hand (5 asked, 1 put in) is requested again for the rest (4), also for a depot built over a blueprint ghost without its tags; taking freighters away stops topping up | Passed headless. In the owner's game (checked with `/jatz-freighters`): the request stays at 4 after 1 is put in by hand; the chest slot's ghost only came back slowly, because a freighter placed from the cursor waited for the next dispatch to move to the slot. Placing from the cursor now moves it at once |
| Ctrl+click of freighters, and of other items, into a request depot, in the graphical client | Untested |
| Buffer depots: a request depot set to request from buffers takes its 20 from a buffer 20 tiles away, not a provider 10 away; a buffer fills from the provider only (15); buffers have no request-from-buffers setting; the checkbox and Copy and Paste settings route through control.lua | Passed |
| Fallback to buffer depots with "Request from buffer depots" unticked (November 4, 2026, Factorio 2.1.24 headless, base game and Space Age): a liquid request depot takes its 300 crude oil from a liquid buffer 30 tiles away when the liquid provider 10 tiles away is empty (700 left in the buffer). Before the fix it got nothing and showed "no provider" | Passed |
| Fallback against a fake runtime: unticked, the provider still comes first with the buffer not asked; an empty provider, or one with no road route, leaves it to the buffer, for item and liquid request depots | Passed headless |
| Buffer depot panel and the "Request from buffer depots" checkbox, in the graphical client | **Passed:** checked by the owner on November 3, 2026 |
| Priority: a request depot takes its 10 stone from a provider 30 tiles away at priority 9, none from one 10 tiles away at priority 2; providers start at 5; request depots have none | Passed |
| Priority ordering against a fake runtime: a higher priority first however near a lower one is, the lower one when the higher has no road, nearest among equals, a priority 1 buffer before priority 10 providers, a changed priority restarting a waiting search; the slider panels, Copy and Paste settings, clones and blueprint tags, routed through control.lua | Passed headless |
| Priority slider on provider and buffer depot panels, in the graphical client | Buffer panel seen by the owner on November 3, 2026 (slider moved above the request at their request); provider panel untested |
| Liquid depots: 1200 water from a liquid provider holding 2000, in loads of 500 (800 left); 300 steam from a liquid buffer 30 tiles away at its 500 degrees, not from a liquid provider 10 tiles away; only liquid request and buffer depots get a truck chest; robots bring a liquid depot's 2 freighters through it into its slot; liquid depots refuse items and item depots fluids | Passed |
| Liquid depots against a fake runtime: kinds never mix (no item provider asked for a fluid, no liquid provider for an item, no paste across kinds); other fluid in the tank; fluid that no longer fits, or whose way back is lost, returns to the provider; mining hands over freighters and removes the truck chest; the liquid panels, fluid chooser and blueprint tags through control.lua | Passed headless |
| Liquid depot panels, fluid deliveries and robot-delivered freighters, in the graphical client | **Failed** for the owner on November 3, 2026: the liquid provider showed no panel, and opening a liquid request depot crashed (`Unknown filter type: is-parameter`). Fixed: panels anchor to `pipe_gui` (2.1 removed `storage_tank_gui`), and the fluid chooser uses fluid filters only. Retest pending |
| Compact freighter line: the slot shows freighters at home, the line beside it how many are out ("3 out", always) and a green "+N" while N are requested; full breakdown as tooltip, in the graphical client | Untested |
| Request ghosts in an open depot window after a freighter is put in by hand: Factorio doesn't redraw them for script changes; reopening the window by script fixed it but flashed the window, so (owner's choice) the ghost updates on the next open and the panel's "+N" shows the live count | Owner checked the flash version on November 3, 2026; panel version untested |
| Freighter slot in the request panel in the graphical client: ghost requests and robot removal in remote view, pipette (Q) over the slot | **Passed:** checked by the owner on November 3, 2026 |
| Fuel (November 4, 2026, Factorio 2.1.24 headless, Linux, base game and Space Age): a freighter with fuel for 10 tiles, sent to a provider 20 tiles east, stops first at a Fuel depot 4 tiles west, takes 5 of its 10 coal (20 MJ), then fetches its 10 iron ore and parks with 19 MJ; another fills up with 20 of 100 petroleum gas (made burnable by the check mod) and fetches 10 copper ore; one with an empty tank, whose Fuel depot holds only stone, stays home with status "no fuel" (nothing received at tick 300), then crawls to the depot once 5 coal are put in, fills up and fetches 10 sulfur. Every Fuel depot gets its hidden tank facing as it does, its pipe port connects in all 4 directions, and a Fuel depot turned by script turns its tank | Passed headless |
| No fuel to get (November 5, 2026, Factorio 2.1.24 headless, Linux, base game and Space Age): the empty-tank freighter above, whose road reaches only its stone-filled Fuel depot while Fuel depots with coal and petroleum gas stand on other roads, stays home with the yellow status `no-fuel` (not red), and its depot is delivering by tick 420, a second after coal arrives, instead of after its 10-second wait | Passed headless |
| No fuel to get against a fake runtime: no Fuel depot at all, or one with fuel but no road route, is red `no-fuel-depot` and searches nothing more until a Fuel depot is built (then it goes at once); an empty Fuel depot on its road is yellow `no-fuel`, never a place to wait, even with a stocked one on another road; fuel put in sends it at once | Passed headless |
| Fuel display and petroleum gas (November 5, 2026, Factorio 2.1.24 headless, Linux, base game and Space Age): the low freighter's hover status (`custom_status`, read back) is `jatz-gui.freighter-fuel` with a yellow dot when it reaches the Fuel depot; the liquid freighter fills up with 50 of 100 petroleum gas at the mod's own 0.4 MJ (the check mod no longer sets a value) | Passed headless |
| Fuel display and big fuel items against a fake runtime: hover status green, yellow when low, red when dry, refreshed after filling up and after repainting, none with fuel off; a 10 GJ item taken whole, shown in GJ, kept parked and sent first; the request panel's fuel line and tooltip | Passed headless |
| Freighter fuel on hover and the request panel's fuel line in the graphical client (whether the status line shows on a unit's hover) | Untested |
| Cloning a Fuel depot (November 5, 2026, Factorio 2.1.24 headless, Linux, base game and Space Age): with 10 coal and 1,234 water, cloned alone (`LuaEntity::clone`) and with its hidden tank (`LuaSurface::clone_entities`), each clone holds water 1234 and 10 coal with exactly one tank, and the original is unchanged. The previous code kept the coal but lost all the water in both cases | Passed headless |
| Cloning a Fuel depot against a fake runtime: alone it gets the original's fluid and temperature; with its tank, either event order, it adopts that tank and makes none; a second tank cloned onto it, or one cloned without its depot, is removed | Passed headless |
| Fuel against a fake runtime: burning by the tile, the nearest Fuel depot by road first, liquid fuel before items, a fuel cell leaving its used cell, overfill by one item, staying home or going without, cooldown after no route, running dry (crawling, then full speed after filling up), a removed Fuel depot, fuel turned off, the Fuel depot panel and flush button through control.lua | Passed headless |
| Fuel depot panel (liquid fuel and flush), freighters refuelling, and a dry freighter crawling, in the graphical client | Untested |
| Nothing left on the ground by any check | Passed |
| Unknown items and non-numeric counts are refused without changing the request; a cloned request depot keeps its request; clearing works | Passed |
| Road laid from a ghost on grass; refused on water | Passed |
| A save made by the PR's first version, with a freighter on its way, loads and finishes the delivery | Passed (one-off check) |
| Road tile art, transitions and the item icon in the graphical client | Untested |
| Alt-mode cargo icons (November 4, 2026; Factorio 2.1.24 headless, Linux, base and Space Age): the tracked freighter has no icon on reaching the provider empty and `utility/entity_info_dark_background` + `item/iron-plate` (alt mode only) on getting home loaded; a freighter carrying water showed `fluid/water`. Both checks fail with the icon call removed | Passed headless |
| Alt-mode cargo icon size and placement on the freighter in the graphical client (0.6 scale, centred on the truck) | Untested |
| Request panel beside the request depot's window (item, amount, status), and Copy and Paste settings between request depots | **Passed:** the owner reported the first version working in game on November 3, 2026; the panel is unchanged since |
| Mining Drones depots as item providers (November 5, 2026, on `3267fc0`; Factorio 2.1.24 headless, Linux, base and Space Age; `tools/test_mod.py --mod` with each of Mining_Drones 2.1.1, Mining_Drones_Remastered 2.3.0 and Mining_Drones_Mod 2.1.1, zips matching the mod portal's SHA-1): a north-facing mining depot set to mine iron ore, with 40 ore in its output, lays depot road behind its southern end, and a request depot 12 tiles along the road receives 30 of it (10 left); every other check passes unchanged with each mod and without any. Without the change the delivery never happens and the run fails at the deadline. The ore was put in the output by script, not mined by drones | Passed headless; mining depot priority panel and real drone-mined stock untested in the graphical client |
| Milestones preset addon (November 5, 2026, on `d0caa8f`; Factorio 2.1.24 headless, Linux, base and Space Age; `tools/test_mod.py --mod` with Milestones 1.5.2, zipped from its GitHub release commit `45532bd` since the portal zip needs a login): Milestones logs `Preset addons loaded: {"Jat'z Distribution"}` on the new game (`{}` without the change, which also lacks the interface the check calls), with no validation warnings, and the addon's three item milestones are all real items; every other check passes unchanged with Milestones and without it | Passed headless; milestones being reached and shown in the Milestones window untested in the graphical client (Milestones tracks only forces with players) |
| Corner turns with the delivering freighter's box narrowed from 0.8 to 0.4 tiles (November 6, 2026, on `226010f` plus this change; Factorio 2.1.24 headless, Linux): a probe mod logged one freighter's position and heading every tick, driving north and turning west on one-tile roads. At a crossroads the 0.8-tile box overshot 0.29 tiles north, stood pinned against the off-road corner for about 25 ticks while sliding sideways, then drove back about 12° off west; the 0.4-tile box never stops, swerves past the centre line (up to about 40°, 0.12 tiles) and settles within about 1.5 tiles. `rotation_speed` (0.05 to 0.5) and splitting the command at the corner left the path unchanged. `tools/test_mod.py`, base and Space Age: passed, every freighter on road | Passed headless |
| Corner turns with the 0.4-tile box in the graphical client | Untested. The owner chose the swerve as more natural from a replay of the measured paths, November 6, 2026 |
| Wrecks (November 8, 2026, Factorio 2.1.24 headless, Linux, base game and Space Age; `tools/test_mod.py`): each of the seven depots destroyed (`die`) facing east, south and west leaves one corpse, its own (`jatz-<role>-depot-remnants`), facing as the depot did (21 wrecks); biters destroy a delivering freighter, which explodes and leaves `jatz-freighter-remnants` facing the way it drove (orientation 0.75, corpse direction west). With `main`'s prototypes the same checks fail on `steel-chest-remnants` and `storage-tank-remnants` | Passed |
| Wrecks in the graphical client (look, size, shadow, paint, the half-turned depots' facing) | Untested: headless runs don't draw. The packaged frames are in `assets/depots/remnants/*/previews/directions.png` |

## Depots: passed

**November 7, 2026: depots lowered to 0.6 of their height above 0.75** (`assets/depots/tools/lower_depots.py`), with the item and Fuel depots' circuit connector 3 px lower. Factorio 2.1.24 headless on Linux: `tools/test_depot_art.py` passed (28 depots placed, 28 ghosts, 112 rotation steps, 20 pipe connections, reload), and `tools/test_mod.py` passed with the base game and with Space Age, its undo scenario included. The geometry and junction inspectors passed on the lowered masters.

| Check | Result |
| --- | --- |
| Lowered depots in the graphical client: all seven in four rotations, what stands behind them visible, pipes seated, shadows, cargo openings, ghosts | Untested |
| Item and Fuel depots' circuit connector on the pillar, below the painted band, with wires attached | Untested in the graphical client (placed from the sprite sheets) |

The screenshots below, in the README and on the Mod Portal page still show the depots at their old height.

**November 3, 2026.** Tested artwork commit `b3159d0`. Environment: Factorio 2.1.24 (build 87808) full client, Windows 11, Direct3D 11, AMD Radeon 780M.

![All seven depots in four rotations, in game](images/depots-all-rotations.jpg)

| Check | Result |
| --- | --- |
| All seven designs in all four rotations | Passed |
| Pipes: all 20 vanilla pipe connections join the building; the 172 unused edge positions stay unconnected; covers and connector overlap match the vanilla assembler | Passed |
| Placement: 28 held placements, 112 rotation steps, 28 blueprint ghosts, adjacent fit, overlap rejection | Passed |
| Save and reload, with a second launch | Passed |
| Independent role, clamp and housing colors; grayscale masks | Passed |
| Shadows (including at night), cargo openings, freighter and player beside every loading face | Passed |
| Liquid Buffer bolted pipe adapters, at play zoom and in four housing colors | Passed |
| Fuel depot hopper interior (hidden behind a closed hatch) | Untested |
| Automated dispatch, cargo transfer and one-way fluid flow | Not implemented yet |

![Paint layers changed one at a time](images/depots-paint-channels.jpg)

## Freighter: passed, with one known issue

**November 1, 2026.** Tested artwork commit `bc9dfc0`. Environment: Factorio 2.1.24 (build 87808) full client, Windows 11, Direct3D 11, AMD Radeon 780M.

![Default, alternate and single-layer colors](images/freighter-palettes.jpg)

| Check | Result |
| --- | --- |
| All 64 directions at two zoom levels match the exported frames, including the 63→0 wrap | Passed |
| In-game size (20% smaller than the first version) | Passed |
| Armored cab, fan, glass and wear details | Passed |
| Tint isolation (default, alternate, white, black and each layer alone) | Passed |
| Shadows at eight compass headings and at night | Passed |
| Driving forward, in full circles and in reverse | Passed |
| Selection and collision boxes | **Failed** in this artwork fixture, which inherits the base car's boxes (they cover only the middle of the truck). The mod's freighter now uses a 1.5 × 4.5 tile box measured from the sprites (scaled with the sprites to 60% in game); that still needs a graphical check (see Mod above). |
| Wheel animation | Not implemented yet (one static frame per direction) |

![Default and alternate trucks driving](images/freighter-driving.jpg)
