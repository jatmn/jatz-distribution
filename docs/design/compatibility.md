# Compatibility: Mining Drones and Milestones

The mod works with two other mods when they are installed, as optional dependencies in `info.json`: Mining Drones' mining depot is an item provider depot, and Milestones gets a preset addon with our milestones. Neither mod is needed; without them nothing of this loads. (The Transport Drones mods are marked incompatible in `info.json`.)

For what players see, read the player guide's [Mining Drones](../guide.md#mining-drones) and [Milestones](../guide.md#milestones) sections.

## Code

- `info.json`: `? Mining_Drones`, `? Mining_Drones_Remastered`, `? Mining_Drones_Mod`, `? Milestones`.
- `scripts/loading-zone.lua`: the mining depot's loading zone (`mining_depot`, `MINING_SHIFT`).
- `scripts/logistics.lua`: its provider role and its stock (`inventory`).
- `scripts/request-gui.lua`: its panel's anchor.
- `control.lua`: the `jatz-distribution-milestones` remote interface.

## Mining Drones

The owner's request, November 5, 2026, as Transport Drones does.

- Mining_Drones, Mining_Drones_Remastered and Mining_Drones_Mod all name their depot `mining-depot`, a 5 × 8 `assembling-machine` whose drones mine the area in front of it.
- `scripts/loading-zone.lua` adds it to `loading_zone.depots` only when `prototypes.entity["mining-depot"]` exists. Engine trap: event filters and entity searches refuse unknown names.
- Its loading zone is 4.5 tiles from its centre, just past its back end, opposite its mining area (where Transport Drones puts its road node). From there it lays depot road, clears decoratives, follows turns and registers like any depot.
- `logistics.depots` gives it the `provider` role. Its stock is its output inventory, where the drones put what they mine (`inventory()` returns `get_output_inventory()` for it). Road network monitors count it through the same call.
- Its panel (priority slider and circuit condition) anchors to `assembling_machine_gui`.
- Its circuit condition works as any provider's, except that in "network" mode what it sends on its own wires isn't subtracted: an assembling machine's control behavior isn't worked out ([Circuit network](circuit-network.md#leaving-the-depots-own-share-out)).
- It is not a logistic container, so it has no robot access setting.

## Milestones

The owner's request, November 5, 2026.

- Milestones calls every remote interface's `milestones_preset_addons` on a new game and when mods change. `control.lua`'s interface `jatz-distribution-milestones` answers with the addon "Jat'z Distribution" (`required_mods = { "jatz-distribution" }`), which Milestones adds to whichever preset is in use.
- Its milestones, in the Progress group: the freighter item (`jatz-quinityn-freighter`) at 1, and at 100 then `x10`; `jatz-road` at 1000, then `x10`.
- Engine trap: Milestones drops names that aren't prototypes without a word, so keep them our real item names.
- Milestones tracks only forces with players, so reaching a milestone is checked in the graphical client.

## Tests

- `tests/lua/logistics.lua`: the mining depot with and without a Mining Drones mod (no depot without one; with one, a provider of its output inventory).
- `tests/lua/control-events.lua`: loads `control.lua` as with a Mining Drones mod installed; the mining depot's build filter, road behind it and priority panel.
- The check mod (`tests/factorio/jatz-distribution-check_0.1.0/control.lua`):
  - `setup_mining`: with a Mining Drones mod, a request depot fetches 30 of 40 iron ore from a mining depot's output, at the road it lays behind the depot (skipped without the mod);
  - `check_milestones`: reports every item in our addon, and `tools/test_mod.py` requires each to exist.
- `tools/test_mod.py --mod <zip>` loads another mod's zip too ([testing](../testing.md)). With a Mining Drones mod it requires the mining delivery; with Milestones it also requires Milestones' log line that it loaded our addon. CI doesn't download these mods, so these runs are local.
