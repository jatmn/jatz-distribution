-- SPDX-License-Identifier: LGPL-3.0-only
-- The road network monitor (prototypes/road-monitor.lua): a constant combinator built on or beside
-- road. Once a second it puts on its wires what the provider and buffer depots on its road network
-- hold, item depots their items (each quality its own signal) and liquid depots their fluids,
-- like a roboport reading its logistic network's contents. Wire a depot's circuit condition to it
-- to switch the depot on or off by what the road network has.
--
-- Its road network is the road (road and depot road, the tiles freighters drive on) joined, side
-- by side, to the tile it stands on or to one of the four beside it; a depot is on it when its
-- loading zone tile is. Depots disabled by their circuit condition are left out, since no
-- freighter fetches from them; requests and freighters out on trips aren't counted.
--
-- Which depots are on each monitor's network is worked out again, with the engine's own flood
-- fill (LuaSurface.get_connected_tiles), only after road, a depot or a monitor on that surface
-- changed. Players can't open the monitor to edit its signals.
local loading_zone = require("scripts.loading-zone")
local logistics = require("scripts.logistics")

local road_monitor = {}

local NAME = "jatz-road-monitor"
road_monitor.name = NAME
-- The tiles freighters drive on (prototypes/off-road.lua gives every other tile the off-road layer).
local ROADS = { "jatz-road", "jatz-depot-road" }
local ROAD = { ["jatz-road"] = true, ["jatz-depot-road"] = true }
local NEIGHBOURS = { { 0, 0 }, { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
-- A constant combinator section holds up to this many signals.
local SECTION_SIZE = 1000
local INT_MAX = 2147483647
local QUALITY = "normal"

local function init_storage()
  storage.road_monitors = storage.road_monitors or {}
  -- Surfaces whose monitors must work out their networks again.
  storage.road_monitor_dirty = storage.road_monitor_dirty or {}
end

-- Road, a depot or a monitor changed on a surface: its monitors' networks may have too.
function road_monitor.changed(surface_index)
  if surface_index then
    init_storage()
    storage.road_monitor_dirty[surface_index] = true
  end
end

-- Remember a monitor (built, cloned or found on load); players can't edit its signals.
function road_monitor.add(entity)
  if not (entity and entity.valid and entity.name == NAME and entity.unit_number) then
    return
  end
  init_storage()
  entity.operable = false
  if not storage.road_monitors[entity.unit_number] then
    storage.road_monitors[entity.unit_number] = { entity = entity, depots = {} }
    script.register_on_object_destroyed(entity)
  end
  road_monitor.changed(entity.surface_index)
end

-- A monitor or a depot removed (on_object_destroyed, before the depot is forgotten).
function road_monitor.on_object_destroyed(event)
  if event.type ~= defines.target_type.entity or not event.useful_id then
    return
  end
  init_storage()
  local id = event.useful_id
  local monitor = storage.road_monitors[id]
  if monitor then
    storage.road_monitors[id] = nil
    return
  end
  local depot = storage.depots and storage.depots[id]
  if depot then
    road_monitor.changed(depot.surface_index)
  end
end

local function tile_key(x, y)
  return x .. "," .. y
end

-- Work out which provider and buffer depots are on each monitor's road network on a surface: those
-- of the monitor's own force, as deliveries only use those.
local function connect(surface, monitors)
  -- Supplying depots by the tile they load from.
  local depots = {}
  for unit_number, depot in pairs(storage.depots or {}) do
    local entity = depot.entity
    if
      (depot.role == "provider" or depot.role == "buffer")
      and entity.valid
      and entity.surface_index == surface.index
    then
      local x, y = loading_zone.tile_centre(entity)
      local key = tile_key(math.floor(x), math.floor(y))
      depots[key] = depots[key] or {}
      table.insert(depots[key], unit_number)
    end
  end
  -- The road tiles each monitor touches, and which monitors touch each tile.
  local seeds, seeded = {}, {}
  for _, monitor in ipairs(monitors) do
    monitor.depots = {}
    local position = monitor.entity.position
    local x, y = math.floor(position.x), math.floor(position.y)
    for _, offset in ipairs(NEIGHBOURS) do
      local tx, ty = x + offset[1], y + offset[2]
      local tile = surface.get_tile(tx, ty)
      if tile.valid and ROAD[tile.name] then
        local key = tile_key(tx, ty)
        if not seeded[key] then
          seeded[key] = {}
          seeds[#seeds + 1] = { x = tx, y = ty, key = key }
        end
        table.insert(seeded[key], monitor)
      end
    end
  end
  -- Flood each network once, from the first seed not reached yet; every monitor touching it gets
  -- its depots.
  local reached = {}
  for _, seed in ipairs(seeds) do
    if not reached[seed.key] then
      local found, touching = {}, {}
      for _, position in ipairs(surface.get_connected_tiles({ seed.x, seed.y }, ROADS)) do
        local key = tile_key(position.x, position.y)
        if seeded[key] then
          reached[key] = true
          for _, monitor in ipairs(seeded[key]) do
            touching[monitor] = true
          end
        end
        for _, unit_number in ipairs(depots[key] or {}) do
          found[unit_number] = true
        end
      end
      for monitor in pairs(touching) do
        for unit_number in pairs(found) do
          if storage.depots[unit_number].entity.force == monitor.entity.force then
            monitor.depots[unit_number] = true
          end
        end
      end
    end
  end
end

-- What the enabled depots among `members` hold, as constant combinator filters.
local function contents(members)
  local totals, order = {}, {}
  local function add(kind, name, quality, amount)
    local key = kind .. "/" .. name .. "/" .. quality
    if not totals[key] then
      totals[key] = { type = kind, name = name, quality = quality, count = 0 }
      order[#order + 1] = key
    end
    totals[key].count = totals[key].count + amount
  end
  -- In a fixed order: fluid amounts aren't whole, and their sum must come out the same everywhere.
  local ids = {}
  for unit_number in pairs(members) do
    ids[#ids + 1] = unit_number
  end
  table.sort(ids)
  for _, unit_number in ipairs(ids) do
    local depot = storage.depots and storage.depots[unit_number]
    if depot and depot.entity.valid and logistics.enabled(depot) then
      if depot.fluid then
        for name, amount in pairs(depot.entity.get_fluid_contents()) do
          add("fluid", name, QUALITY, amount)
        end
      else
        for _, item in ipairs(logistics.inventory(depot.entity).get_contents()) do
          add("item", item.name, item.quality, item.count)
        end
      end
    end
  end
  table.sort(order)
  local filters = {}
  for _, key in ipairs(order) do
    local total = totals[key]
    local count = math.min(INT_MAX, math.floor(total.count))
    if count > 0 then
      filters[#filters + 1] = {
        value = { type = total.type, name = total.name, quality = total.quality, comparator = "=" },
        min = count,
      }
    end
  end
  return filters
end

-- Put `filters` on the monitor's signals: its first sections, SECTION_SIZE signals each, and no
-- others.
local function show(entity, filters)
  local behavior = entity.get_or_create_control_behavior()
  if not behavior then
    return
  end
  local needed = math.ceil(#filters / SECTION_SIZE)
  for index = behavior.sections_count, math.max(needed, 1) + 1, -1 do
    behavior.remove_section(index)
  end
  for index = 1, math.max(needed, 1) do
    local section = behavior.get_section(index) or behavior.add_section()
    local part = {}
    for slot = (index - 1) * SECTION_SIZE + 1, math.min(#filters, index * SECTION_SIZE) do
      part[#part + 1] = filters[slot]
    end
    if section and section.is_manual then
      section.filters = part
    end
  end
end

-- Once a second: networks worked out again where something changed, then every monitor's signals.
function road_monitor.update()
  if not storage.road_monitors or next(storage.road_monitors) == nil then
    return
  end
  init_storage()
  local dirty = {}
  for id, monitor in pairs(storage.road_monitors) do
    local entity = monitor.entity
    if not entity.valid then
      storage.road_monitors[id] = nil
    elseif storage.road_monitor_dirty[entity.surface_index] then
      dirty[entity.surface_index] = dirty[entity.surface_index] or {}
      table.insert(dirty[entity.surface_index], monitor)
    end
  end
  for surface_index, monitors in pairs(dirty) do
    connect(game.surfaces[surface_index], monitors)
  end
  storage.road_monitor_dirty = {}
  for _, monitor in pairs(storage.road_monitors) do
    show(monitor.entity, contents(monitor.depots))
  end
end

-- Every monitor already in the game (new saves and updated ones); all work out their networks.
function road_monitor.add_all()
  init_storage()
  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered({ name = NAME })) do
      road_monitor.add(entity)
    end
    road_monitor.changed(surface.index)
  end
end

return road_monitor
