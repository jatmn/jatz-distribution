# Compatibility: Mining Drones and Milestones

Both are optional dependencies in `info.json` (the owner's request, November 5, 2026); without them none of this loads. The Transport Drones mods are marked incompatible. What players see is in the [guide](../guide.md).

## Code

- `info.json`: `? Mining_Drones`, `? Mining_Drones_Remastered`, `? Mining_Drones_Mod`, `? Milestones`.
- `scripts/loading-zone.lua`, `scripts/logistics.lua`, `scripts/request-gui.lua`: the mining depot.
- `control.lua`: the `jatz-distribution-milestones` remote interface.

## Mining Drones

All three Mining Drones mods name their depot `mining-depot`, an `assembling-machine`. It is an item provider depot.

- It is added only when `prototypes.entity["mining-depot"]` exists. Engine trap: event filters and entity searches refuse unknown names.
- Its loading zone is just past its back end, opposite its mining area, where Transport Drones puts its road node.
- Its stock is its output inventory (`inventory()`).
- In "network" mode, what it sends on its own wires isn't subtracted: an assembling machine's control behavior isn't worked out ([circuit network](circuit-network.md)).
- It is not a logistic container, so it has no robot access setting.

## Milestones

`control.lua` answers Milestones' `milestones_preset_addons` call with the addon "Jat'z Distribution", added to whichever preset is in use.

- Engine trap: Milestones drops names that aren't prototypes without a word, so keep them our real item names.
- Milestones tracks only forces with players, so reaching a milestone is checked in the graphical client.

## Tests

`tests/lua/logistics.lua`, `tests/lua/control-events.lua`, and the check mod (`setup_mining`, `check_milestones`). Run `tools/test_mod.py --mod <zip>` with the other mod ([testing](../testing.md)); CI doesn't download these mods, so these runs are local.
