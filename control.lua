-- SPDX-License-Identifier: LGPL-3.0-only
-- Jat'z Distribution runtime: loading zones (scripts/loading-zone.lua), the road each depot lays
-- under its loading zone (scripts/depot-road.lua), deliveries between provider and request depots
-- (scripts/logistics.lua), the request panel (scripts/request-gui.lua) and the road network
-- monitor (scripts/road-monitor.lua).
local loading_zone = require("scripts.loading-zone")
local depot_road = require("scripts.depot-road")
local logistics = require("scripts.logistics")
local depot_settings = require("scripts.depot-settings")
local request_gui = require("scripts.request-gui")
local research = require("scripts.research")
local road_monitor = require("scripts.road-monitor")
local undo = require("scripts.undo")

-- Road laid (`added`) or removed or covered (`removed`) on a surface: deliveries re-plan, and road
-- network monitors there work out their networks again.
local function roads_changed(surface_index, added, removed)
  logistics.on_roads_changed(surface_index, added, removed)
  if added or removed then
    road_monitor.changed(surface_index)
  end
end

-- A depot built, turned or flipped.
local function depot_changed(entity)
  logistics.on_depot_changed(entity)
  road_monitor.changed(entity.surface_index)
end

-- Lay road under a depot's loading zone (lifting the road of its old one, if turned), clear the
-- zone's decoratives, and let deliveries know the roads changed.
local function settle(entity)
  local laid, removed = depot_road.lay(entity)
  loading_zone.clear(entity)
  if removed then
    roads_changed(removed, false, true)
  end
  if laid then
    roads_changed(laid, true, false)
  end
end

local function on_built(event)
  local entity = event.entity or event.destination
  local settings = depot_settings.name
  if
    entity
    and entity.valid
    and (entity.name == settings or (entity.type == "entity-ghost" and entity.ghost_name == settings))
  then
    -- A blueprint's depot request settings: the request and freighters, which parametrisation may
    -- have changed, go to the depot.
    depot_settings.built(entity, event.tags)
  elseif entity and entity.valid then
    if loading_zone.depots[entity.name] then
      settle(entity)
    end
    logistics.add(entity)
    -- Built from a blueprint ghost: the request it was blueprinted with.
    logistics.apply_tags(entity, event.tags)
    if entity.name == road_monitor.name then
      -- With the reading it was blueprinted with.
      road_monitor.add(entity, event.tags)
    else
      depot_changed(entity)
    end
  end
end

-- Turning or flipping a depot moves its loading zone.
local function on_turned(event)
  local entity = event.entity
  if entity and entity.valid and loading_zone.depots[entity.name] then
    settle(entity)
    depot_changed(entity)
  end
end

local filters = { { filter = "name", name = road_monitor.name } }
for name in pairs(loading_zone.depots) do
  filters[#filters + 1] = { filter = "name", name = name }
end
-- And a blueprint's depot request settings, or their ghost (scripts/depot-settings.lua).
local built_filters = {
  { filter = "name", name = depot_settings.name },
  { filter = "ghost_name", name = depot_settings.name },
}
for _, filter in ipairs(filters) do
  built_filters[#built_filters + 1] = filter
end
-- Every way a depot or a road network monitor can be built: by hand, robots, other mods' scripts, revived ghosts, platforms.
for _, event in ipairs({
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive,
  defines.events.on_space_platform_built_entity,
}) do
  script.on_event(event, on_built, built_filters)
end
-- Freighters and request and buffer depots' truck chests cloned along with an area are removed: they belong to
-- the original's trips and depots, and a cloned depot makes its own. A Fuel depot's tank cloned with
-- its depot stays with the clone, fluid and all; one cloned without its depot is removed.
local clone_filters = {
  { filter = "name", name = logistics.truck_chest },
  { filter = "name", name = logistics.fuel_tank },
}
for _, name in ipairs(logistics.drones) do
  clone_filters[#clone_filters + 1] = { filter = "name", name = name }
end
for _, filter in ipairs(filters) do
  clone_filters[#clone_filters + 1] = filter
end
-- Another mod cloning a depot (or a whole area): the clone is a new depot with the original's
-- request, and a cloned Fuel depot keeps the original's liquid fuel. A cloned freighter has no
-- trip, and a cloned truck chest no depot, so they are removed (logistics.on_cloned).
script.on_event(defines.events.on_entity_cloned, function(event)
  local entity = event.destination
  if entity.valid then
    if loading_zone.depots[entity.name] then
      settle(entity)
    end
    logistics.on_cloned(event.source, entity)
    if entity.valid and entity.name == road_monitor.name then
      road_monitor.add(entity, nil, event.source)
    elseif entity.valid then
      depot_changed(entity)
    end
  end
end, clone_filters)
-- Request and buffer depots: the depots that hold freighters.
local requesting_filters = {}
for name in pairs(logistics.requesting) do
  requesting_filters[#requesting_filters + 1] = { filter = "name", name = name }
end
-- A request depot mined by a player, robot or platform hands its freighters (in its slot and out
-- on trips) to the miner; the mining buffer goes to their inventory.
for _, event in ipairs({
  defines.events.on_robot_mined_entity,
  defines.events.on_space_platform_mined_entity,
}) do
  script.on_event(event, logistics.on_depot_mined, requesting_filters)
end
-- Mined by a player: also the removal undo.player_removing's settings were read for (below).
script.on_event(defines.events.on_player_mined_entity, function(event)
  undo.player_removed(event.entity, event.player_index)
  logistics.on_depot_mined(event)
end, filters)
-- A depot or road network monitor a player removes keeps its settings on the removal's undo action
-- (scripts/undo.lua), read just before it goes, freighters in its chest still counted: marked for
-- deconstruction (as cutting does) by a player, then taken by robots or a space platform; or mined
-- by hand.
script.on_event(defines.events.on_marked_for_deconstruction, function(event)
  undo.marked(event.entity, event.player_index)
end, filters)
script.on_event(defines.events.on_cancelled_deconstruction, function(event)
  undo.forget(event.entity.unit_number)
end, filters)
-- Taken by robots, or by a space platform (liquid depots and the monitor can stand on one).
for _, event in ipairs({ defines.events.on_robot_pre_mined, defines.events.on_space_platform_pre_mined }) do
  script.on_event(event, function(removing)
    undo.removing_marked(removing.entity)
  end, filters)
end
script.on_event(defines.events.on_pre_player_mined_item, function(event)
  undo.player_removing(event.entity, event.player_index)
end, filters)
script.on_event(defines.events.on_undo_applied, undo.on_undo_applied)
-- One about to be destroyed (died, or removed by a script that says so) leaves all its freighters,
-- including any still in its chest, where it stands.
for _, event in ipairs({ defines.events.on_entity_died, defines.events.script_raised_destroy }) do
  script.on_event(event, logistics.on_depot_destroyed, requesting_filters)
end
script.on_event(defines.events.on_player_rotated_entity, on_turned)
script.on_event(defines.events.on_player_flipped_entity, on_turned)
script.on_event(defines.events.on_entity_settings_pasted, function(event)
  logistics.on_entity_settings_pasted(event)
  road_monitor.on_settings_pasted(event)
end)
-- Blueprints and copy and paste of request depots keep their request and freighters.
script.on_event(defines.events.on_player_setup_blueprint, logistics.on_player_setup_blueprint)

-- A depot removed by any means takes the road it laid with it.
script.on_event(defines.events.on_object_destroyed, function(event)
  -- First, while deliveries still know where the depot stood.
  road_monitor.on_object_destroyed(event)
  logistics.on_object_destroyed(event)
  if event.type == defines.target_type.entity and event.useful_id then
    -- Gone some other way while marked for deconstruction (destroyed, say): no robot removal.
    undo.forget(event.useful_id)
    local surface_index = depot_road.lift(event.useful_id)
    if surface_index then
      roads_changed(surface_index, false, true)
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
  roads_changed(event.surface_index, added, removed and not added)
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
    roads_changed(event.surface_index, false, true)
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
  roads_changed(event.surface_index, added, other)
end)
logistics.register()
request_gui.register()
-- Every tick, first: what depots whose condition reads the circuit network hold, as the wires carry
-- it this tick (logistics.sample_circuits). Then the share of the once-a-second work whose turn it
-- is (request depots sending freighters, freighters burning fuel: logistics.on_tick_share), and of
-- the freighters looking for enemies to run over every 20 ticks (logistics.on_impact_share), so
-- none of it lands all on the same tick. Once a second: road network monitors show their
-- networks. The game raises on_tick before on_nth_tick. Before all that, the commands freighters
-- failed since the last tick (logistics.failed_commands).
script.on_event(defines.events.on_tick, function(event)
  if storage.failed_trips then
    logistics.failed_commands()
  end
  logistics.sample_circuits()
  logistics.on_tick_share(event.tick)
  logistics.on_impact_share(event.tick)
  if storage.undo_pending or storage.undo_locating then
    undo.tag_pending(event.tick)
  end
end)
script.on_nth_tick(logistics.dispatch_interval, road_monitor.update)
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
    roads_changed(surface_index, true, false)
  end
  loading_zone.clear_all()
  road_monitor.add_all()
end
script.on_init(function()
  research.init()
  setup()
end)
script.on_configuration_changed(function()
  research.on_configuration_changed()
  setup()
end)

-- Milestones (optional) calls every remote interface with this function, on a new game and when
-- mods change, and adds the milestones of each addon whose required mods are all active to the
-- preset in use. It drops names that aren't prototypes, so keep these our real item names.
remote.add_interface("jatz-distribution-milestones", {
  milestones_preset_addons = function()
    return {
      ["Jat'z Distribution"] = {
        required_mods = { "jatz-distribution" },
        milestones = {
          { type = "group", name = "Progress" },
          { type = "item", name = "jatz-quinityn-freighter", quantity = 1 },
          { type = "item", name = "jatz-quinityn-freighter", quantity = 100, next = "x10" },
          { type = "item", name = "jatz-road", quantity = 1000, next = "x10" },
        },
      },
    }
  end,
})

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
