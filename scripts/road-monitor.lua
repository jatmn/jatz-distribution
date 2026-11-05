-- SPDX-License-Identifier: LGPL-3.0-only
-- The road network monitor (prototypes/road-monitor.lua): a constant combinator built on or beside
-- road. Once a second it puts on its wires one reading of the depots on its road network, like a
-- roboport reading its logistic network, item depots' items (each quality its own signal) and
-- liquid depots' fluids. Wire a depot's circuit condition to it to switch the depot on or off by
-- what the road network has. The reading (`READINGS`, chosen in its panel,
-- scripts/road-monitor-gui.lua; the owner's request, November 5, 2026, so a condition reads one
-- thing at a time):
-- - "supply", the default: what provider and buffer depots hold, what freighters can fetch;
-- - "providers": what provider depots hold;
-- - "requests": what request depots hold;
-- - "needs": what request depots still need, their request less what they hold and what
--   freighters are bringing (logistics.missing).
-- Request depots are the item and liquid request depots, never buffer depots.
--
-- Its road network is the road (road and depot road, the tiles freighters drive on) joined, side
-- by side, to the tile it stands on or to one of the four beside it; a depot is on it when its
-- loading zone tile is. Depots disabled by their circuit condition are left out of every reading,
-- since no freighter comes to or goes from them; freighters out on trips aren't counted.
--
-- Which depots are on each monitor's network is worked out again, with the engine's own flood
-- fill (LuaSurface.get_connected_tiles), only after road, a depot or a monitor on that surface
-- changed. Opening the monitor shows its panel instead of the combinator's own window, so players
-- choose its reading but can't edit its signals.
--
-- A depot whose condition reads the circuit network leaves out its own contents, so each monitor
-- remembers what it counted for each depot (`counted`, and `previous`: what its signals still show
-- in the tick it changes them, as a combinator's output reaches the wire a tick later). Fluids are
-- whole units per depot, so what a depot leaves out is exactly what it added.
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
-- The readings in the order the panel lists them; nil is stored for the default, "supply". Which
-- depot roles (logistics.depots) each reads, and whether it reads what they still need.
local READINGS = { "supply", "providers", "requests", "needs" }
road_monitor.readings = READINGS
local ROLES = {
  supply = { provider = true, buffer = true },
  providers = { provider = true },
  requests = { request = true },
  needs = { request = true },
}
-- The blueprint tag that keeps a monitor's reading (when it isn't the default).
local TAG = "jatz_monitor_reading"

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

local function monitor_of(entity)
  return entity
    and entity.valid
    and entity.name == NAME
    and entity.unit_number
    and storage.road_monitors
    and storage.road_monitors[entity.unit_number]
end

-- A monitor's reading ("supply", "providers", "requests" or "needs"), or nil for anything else.
function road_monitor.get_reading(entity)
  local monitor = monitor_of(entity)
  return monitor and (monitor.reading or READINGS[1]) or nil
end

-- Set a monitor's reading; its signals follow at the next update. Returns false, changing
-- nothing, for anything else or another reading.
function road_monitor.set_reading(entity, reading)
  local monitor = monitor_of(entity)
  if not (monitor and ROLES[reading]) then
    return false
  end
  monitor.reading = reading ~= READINGS[1] and reading or nil
  return true
end

-- Remember a monitor (built, cloned or found on load), with the reading from its blueprint tags
-- or the monitor it was cloned from. It opens to its panel (operable; monitors from before the
-- panel weren't).
function road_monitor.add(entity, tags, source)
  if not (entity and entity.valid and entity.name == NAME and entity.unit_number) then
    return
  end
  init_storage()
  entity.operable = true
  if not storage.road_monitors[entity.unit_number] then
    storage.road_monitors[entity.unit_number] = { entity = entity, depots = {} }
    script.register_on_object_destroyed(entity)
  end
  local reading = (tags and tags[TAG]) or road_monitor.get_reading(source)
  if type(reading) == "string" then
    road_monitor.set_reading(entity, reading)
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

-- Work out which delivery depots are on each monitor's road network on a surface: those of the
-- monitor's own force, as deliveries only use those. Its reading picks among them.
local function connect(surface, monitors)
  -- Depots by the tile they load from.
  local depots = {}
  for unit_number, depot in pairs(storage.depots or {}) do
    local entity = depot.entity
    if
      (depot.role == "provider" or depot.role == "buffer" or depot.role == "request")
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

-- A reading of the enabled depots among `members`, as constant combinator filters, and what each
-- one added (by unit_number, counts by key).
local function contents(members, reading)
  local roles = ROLES[reading or READINGS[1]]
  local totals, order, counted = {}, {}, {}
  local function add(unit_number, kind, name, quality, amount)
    local key = kind .. "/" .. name .. "/" .. quality
    if not totals[key] then
      totals[key] = { type = kind, name = name, quality = quality, count = 0 }
      order[#order + 1] = key
    end
    totals[key].count = totals[key].count + amount
    counted[unit_number] = counted[unit_number] or {}
    counted[unit_number][key] = (counted[unit_number][key] or 0) + amount
  end
  -- In a fixed order, so the sums come out the same everywhere.
  local ids = {}
  for unit_number in pairs(members) do
    ids[#ids + 1] = unit_number
  end
  table.sort(ids)
  for _, unit_number in ipairs(ids) do
    local depot = storage.depots and storage.depots[unit_number]
    if not (depot and depot.entity.valid and roles[depot.role] and logistics.enabled(depot)) then
      depot = nil
    end
    if depot and reading == "needs" then
      local wanted = depot.request and logistics.missing(depot) or 0
      if wanted >= 1 then
        add(unit_number, depot.fluid and "fluid" or "item", depot.request.item, QUALITY, math.floor(wanted))
      end
    elseif depot then
      if depot.fluid then
        for name, amount in pairs(depot.entity.get_fluid_contents()) do
          add(unit_number, "fluid", name, QUALITY, math.floor(amount))
        end
      else
        for _, item in ipairs(logistics.inventory(depot.entity).get_contents()) do
          add(unit_number, "item", item.name, item.quality, item.count)
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
  return filters, counted
end

-- What the monitors whose signals are on `network` (a LuaCircuitNetwork) show for depot
-- `unit_number` now: a list of counts by key (depot_circuit.key), for its condition to leave out.
function road_monitor.counted(unit_number, network)
  local found = {}
  for _, monitor in pairs(storage.road_monitors or {}) do
    -- Changed this tick, its signals still show what it counted before (nothing, if it is new).
    local counted = monitor.counted
    if monitor.counted_tick == game.tick then
      counted = monitor.previous
    end
    local counts = counted and counted[unit_number]
    if counts and monitor.entity.valid then
      for _, wire in ipairs({ defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green }) do
        local on = monitor.entity.get_circuit_network(wire)
        if on and on.network_id == network.network_id then
          found[#found + 1] = counts
        end
      end
    end
  end
  return found
end
logistics.monitor_counts = road_monitor.counted

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
    local filters, counted = contents(monitor.depots, monitor.reading)
    if monitor.counted_tick ~= game.tick then
      monitor.previous = monitor.counted
    end
    monitor.counted, monitor.counted_tick = counted, game.tick
    show(monitor.entity, filters)
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

-- Copy and Paste settings from one monitor to another copies its reading.
function road_monitor.on_settings_pasted(event)
  local reading = road_monitor.get_reading(event.source)
  if reading and monitor_of(event.destination) then
    road_monitor.set_reading(event.destination, reading)
  end
end

-- Blueprints keep a monitor's reading as a tag when it isn't the default (logistics.setup_blueprint
-- asks through this hook); road_monitor.add applies it to the monitor built from the ghost.
logistics.monitor_tag = function(entity)
  local reading = road_monitor.get_reading(entity)
  if reading then
    return TAG, reading ~= READINGS[1] and reading or nil
  end
end

-- For other mods and the tests: read and set a monitor's reading.
logistics.remote_extra.get_monitor_reading = road_monitor.get_reading
logistics.remote_extra.set_monitor_reading = road_monitor.set_reading

return road_monitor
