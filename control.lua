-- SPDX-License-Identifier: LGPL-3.0-only
-- Jat'z Distribution runtime: loading zones (scripts/loading-zone.lua), the road each depot lays
-- under its loading zone (scripts/depot-road.lua), deliveries between provider and request depots
-- (scripts/logistics.lua) and the request panel (scripts/request-gui.lua).
local loading_zone = require("scripts.loading-zone")
local depot_road = require("scripts.depot-road")
local logistics = require("scripts.logistics")
local request_gui = require("scripts.request-gui")

-- Lay road under a depot's loading zone (lifting the road of its old one, if turned), clear the
-- zone's decoratives, and let deliveries know the roads changed.
local function settle(entity)
  local laid, removed = depot_road.lay(entity)
  loading_zone.clear(entity)
  if removed then
    logistics.on_roads_changed(removed, false, true)
  end
  if laid then
    logistics.on_roads_changed(laid, true, false)
  end
end

local function on_built(event)
  local entity = event.entity or event.destination
  if entity and entity.valid then
    if loading_zone.depots[entity.name] then
      settle(entity)
    end
    logistics.add(entity)
    -- Built from a blueprint ghost: the request it was blueprinted with.
    logistics.apply_tags(entity, event.tags)
    logistics.on_depot_changed(entity)
  end
end

-- Turning or flipping a depot moves its loading zone.
local function on_turned(event)
  local entity = event.entity
  if entity and entity.valid and loading_zone.depots[entity.name] then
    settle(entity)
    logistics.on_depot_changed(entity)
  end
end

local filters = {}
for name in pairs(loading_zone.depots) do
  filters[#filters + 1] = { filter = "name", name = name }
end
-- Every way a depot can be built: by hand, robots, other mods' scripts, revived ghosts, platforms.
for _, event in ipairs({
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive,
  defines.events.on_space_platform_built_entity,
}) do
  script.on_event(event, on_built, filters)
end
local clone_filters = { { filter = "name", name = logistics.drone } }
for _, filter in ipairs(filters) do
  clone_filters[#clone_filters + 1] = filter
end
-- Another mod cloning a depot (or a whole area): the clone is a new depot with the original's
-- request. A cloned freighter has no trip, so it is removed.
script.on_event(defines.events.on_entity_cloned, function(event)
  local entity = event.destination
  if entity.valid then
    if loading_zone.depots[entity.name] then
      settle(entity)
    end
    logistics.on_cloned(event.source, entity)
    if entity.valid then
      logistics.on_depot_changed(entity)
    end
  end
end, clone_filters)
-- A request depot mined by a player, robot or platform hands its freighters (in its slot and out
-- on trips) to the miner; the mining buffer goes to their inventory.
for _, event in ipairs({
  defines.events.on_player_mined_entity,
  defines.events.on_robot_mined_entity,
  defines.events.on_space_platform_mined_entity,
}) do
  script.on_event(event, logistics.on_depot_mined, { { filter = "name", name = "jatz-request-depot" } })
end
-- One about to be destroyed (died, or removed by a script that says so) leaves all its freighters,
-- including any still in its chest, where it stands.
for _, event in ipairs({ defines.events.on_entity_died, defines.events.script_raised_destroy }) do
  script.on_event(event, logistics.on_depot_destroyed, { { filter = "name", name = "jatz-request-depot" } })
end
script.on_event(defines.events.on_player_rotated_entity, on_turned)
script.on_event(defines.events.on_player_flipped_entity, on_turned)
script.on_event(defines.events.on_entity_settings_pasted, logistics.on_entity_settings_pasted)
-- Blueprints and copy and paste of request depots keep their request and freighters.
script.on_event(defines.events.on_player_setup_blueprint, logistics.on_player_setup_blueprint)

-- A depot removed by any means takes the road it laid with it.
script.on_event(defines.events.on_object_destroyed, function(event)
  logistics.on_object_destroyed(event)
  if event.type == defines.target_type.entity and event.useful_id then
    local surface_index = depot_road.lift(event.useful_id)
    if surface_index then
      logistics.on_roads_changed(surface_index, false, true)
    end
  end
end)

-- Road laid or removed, by anyone: freighters re-plan, and waiting requests try again at once.
-- A tile placed over a depot's road makes that spot the player's; a depot's road mined by hand
-- puts back the ground it covered.
local ROADS = { ["jatz-road"] = true, [depot_road.name] = true }
local function on_tiles_built(event)
  local removed = false
  for _, tile in pairs(event.tiles) do
    removed = removed or ROADS[tile.old_tile.name] or false
    if tile.old_tile.name == depot_road.name then
      depot_road.covered(event.surface_index, tile.position)
    end
  end
  local added = ROADS[event.tile.name] or false
  logistics.on_roads_changed(event.surface_index, added, removed and not added)
end
local function on_tiles_mined(event)
  local removed = false
  for _, tile in pairs(event.tiles) do
    removed = removed or ROADS[tile.old_tile.name] or false
    if tile.old_tile.name == depot_road.name then
      depot_road.mined(event.surface_index, tile.position)
    end
  end
  if removed then
    logistics.on_roads_changed(event.surface_index, false, true)
  end
end
for _, event in ipairs({
  defines.events.on_player_built_tile,
  defines.events.on_robot_built_tile,
  defines.events.on_space_platform_built_tile,
}) do
  script.on_event(event, on_tiles_built)
end
for _, event in ipairs({
  defines.events.on_player_mined_tile,
  defines.events.on_robot_mined_tile,
  defines.events.on_space_platform_mined_tile,
}) do
  script.on_event(event, on_tiles_mined)
end
-- Scripts report only the new tiles: road among them was laid; anything else may have covered road.
-- Another tile set over a depot's road by a script is that script's: the depot won't restore it.
script.on_event(defines.events.script_raised_set_tiles, function(event)
  local added, other = false, false
  for _, tile in pairs(event.tiles) do
    if ROADS[tile.name] then
      added = true
    else
      other = true
    end
    if tile.name ~= depot_road.name then
      depot_road.covered(event.surface_index, tile.position)
    end
  end
  logistics.on_roads_changed(event.surface_index, added, other)
end)
logistics.register()
request_gui.register()
-- Freighters ctrl+ or shift+clicked from a player's inventory into a request depot fill its
-- freighter slot (scripts/request-gui.lua).
script.on_event(defines.events.on_player_main_inventory_changed, request_gui.on_player_main_inventory_changed)
script.on_event(defines.events.on_selected_entity_changed, request_gui.on_selected_entity_changed)
script.on_event(defines.events.on_player_cursor_stack_changed, request_gui.on_player_cursor_stack_changed)

local function setup()
  logistics.init()
  -- Depots that were in the game before this mod laid road under them (it was added to a save,
  -- or updated) get theirs now.
  local names = {}
  for name in pairs(loading_zone.depots) do
    names[#names + 1] = name
  end
  for surface_index in pairs(depot_road.lay_all(names)) do
    logistics.on_roads_changed(surface_index, true, false)
  end
  loading_zone.clear_all()
end
script.on_init(setup)
script.on_load(request_gui.on_load)
script.on_configuration_changed(setup)

-- /jatz-freighters: what the freighter slot's requests are worked out from, for the request depot
-- the player has open or points at.
commands.add_command("jatz-freighters", { "jatz-gui.freighters-command-help" }, function(command)
  local player = command.player_index and game.get_player(command.player_index)
  if not player then
    return
  end
  local opened = player.opened
  local entity = (opened and opened.object_name == "LuaEntity" and opened) or player.selected
  local description = entity and entity.valid and logistics.describe_freighters(entity)
  player.print(description or { "jatz-gui.freighters-command-none" })
end)
