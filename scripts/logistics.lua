-- SPDX-License-Identifier: LGPL-3.0-only
-- Deliveries between provider and request depots.
--
-- A request depot asks to keep at least `count` of one item. Once a second, each request depot
-- that is short, and has no freighter on the way, sends a freighter from its loading zone to the
-- nearest provider depot holding that item. The freighter loads what is needed (up to ten
-- stacks), drives back and unloads, then leaves the map. Freighters are units whose only
-- collision layer is on every tile except roads (prototypes/off-road.lua), so the engine's
-- pathfinder keeps them on roads; both loading zones must be road for a trip to start.
--
-- Depots are registered when built (control.lua) and found again on load, and forgotten when
-- destroyed. Fuel is not used yet, and freighters are created for each trip free of charge.
local loading_zone = require("scripts.loading-zone")

local logistics = {}

local PROVIDER = "jatz-provider-depot"
local REQUEST = "jatz-request-depot"
local ROAD = "jatz-road"
local DRONE = "jatz-freighter-drone"
logistics.depots = { [PROVIDER] = "provider", [REQUEST] = "request" }

local DISPATCH_INTERVAL = 60
-- A freighter carries at most this many stacks of the requested item.
local CAPACITY_STACKS = 10
-- After a provider can't be reached, a request depot ignores it for this long.
local RETRY_TICKS = 30 * 60
-- How close a freighter must get to a loading zone's centre to load or unload there.
local ARRIVAL_RADIUS = 0.5

-- Status of a request depot, shown in its window: a key in the [jatz-request-status] locale section.
logistics.status = {
  none = "none",
  satisfied = "satisfied",
  no_road = "no-road",
  no_provider = "no-provider",
  unreachable = "unreachable",
  delivering = "delivering",
}

local function init_storage()
  storage.depots = storage.depots or {}
  storage.trips = storage.trips or {}
end

local function inventory(entity)
  return entity.get_inventory(defines.inventory.chest)
end

-- The loading zone tile's centre, and whether it is road.
local function loading_tile(entity)
  local x, y = loading_zone.tile_centre(entity)
  local tile = entity.surface.get_tile(math.floor(x), math.floor(y))
  return { x = x, y = y }, tile.valid and tile.name == ROAD
end

-- Remember a provider or request depot. Safe to call again for one already known.
function logistics.add(entity)
  local role = logistics.depots[entity.name]
  if not role or not entity.unit_number then
    return
  end
  init_storage()
  local depot = storage.depots[entity.unit_number]
  if depot then
    depot.entity = entity
    return
  end
  storage.depots[entity.unit_number] = {
    entity = entity,
    role = role,
    -- Request depots only: { item = name, count = n }, retry cooldowns per provider, the
    -- freighter on the way, and the status shown to the player.
    request = nil,
    cooldowns = {},
    trip = nil,
    status = logistics.status.none,
  }
  script.register_on_object_destroyed(entity)
end

-- Find every provider and request depot already in the game (new saves and updated ones).
function logistics.add_all()
  init_storage()
  local names = {}
  for name in pairs(logistics.depots) do
    names[#names + 1] = name
  end
  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered({ name = names })) do
      logistics.add(entity)
    end
  end
  -- Make trips and freighters agree: forget trips whose freighter is gone, remove freighters
  -- without a trip, and free request depots whose trip no longer exists.
  for id, trip in pairs(storage.trips) do
    if not (trip.drone and trip.drone.valid) then
      storage.trips[id] = nil
    end
  end
  for _, surface in pairs(game.surfaces) do
    for _, drone in pairs(surface.find_entities_filtered({ name = DRONE })) do
      if not storage.trips[drone.unit_number] then
        drone.destroy()
      end
    end
  end
  for _, depot in pairs(storage.depots) do
    if depot.trip and not storage.trips[depot.trip] then
      depot.trip = nil
    end
  end
end

local function request_depot(entity)
  local depot = entity and entity.valid and entity.unit_number and storage.depots[entity.unit_number]
  return depot and depot.role == "request" and depot or nil
end

-- The request of a request depot: { item = name, count = n }, or nil.
function logistics.get_request(entity)
  local depot = request_depot(entity)
  return depot and depot.request and { item = depot.request.item, count = depot.request.count }
end

-- Set (or with no item, clear) a request depot's request. Returns false for other entities.
function logistics.set_request(entity, item, count)
  local depot = request_depot(entity)
  if not depot then
    return false
  end
  count = math.max(0, math.floor(tonumber(count) or 0))
  if item and prototypes.item[item] then
    depot.request = { item = item, count = count }
  else
    depot.request = nil
  end
  depot.cooldowns = {}
  return true
end

function logistics.get_status(entity)
  local depot = request_depot(entity)
  return depot and depot.status
end

-- How many more of the requested item a request depot wants.
local function shortfall(depot)
  local request = depot.request
  if not request or request.count <= 0 then
    return 0
  end
  return request.count - inventory(depot.entity).get_item_count(request.item)
end

-- The nearest provider on the same surface and force, with road at its loading zone, holding the
-- item and not on cooldown for this request.
local function find_provider(depot, from)
  local entity, item = depot.entity, depot.request.item
  local best, best_distance, waiting = nil, math.huge, false
  for id, provider in pairs(storage.depots) do
    local candidate = provider.entity
    if
      provider.role == "provider"
      and candidate.valid
      and candidate.surface == entity.surface
      and candidate.force == entity.force
      and inventory(candidate).get_item_count(item) > 0
    then
      local position, on_road = loading_tile(candidate)
      if on_road then
        if (depot.cooldowns[id] or 0) > game.tick then
          waiting = true
        else
          local dx, dy = position.x - from.x, position.y - from.y
          local distance = dx * dx + dy * dy
          if distance < best_distance then
            best, best_distance = provider, distance
          end
        end
      end
    end
  end
  return best, waiting
end

local function drive(trip, destination)
  trip.drone.commandable.set_command({
    type = defines.command.go_to_location,
    destination = destination,
    radius = ARRIVAL_RADIUS,
    distraction = defines.distraction.none,
    pathfind_flags = { no_break = true },
  })
end

local function start_trip(id, depot, provider, from)
  local drone = depot.entity.surface.create_entity({
    name = DRONE,
    position = from,
    force = depot.entity.force,
  })
  if not drone then
    return false
  end
  local trip = {
    drone = drone,
    request = id,
    provider = provider.entity.unit_number,
    item = depot.request.item,
    cargo = 0,
    state = "to-provider",
  }
  storage.trips[drone.unit_number] = trip
  script.register_on_object_destroyed(drone)
  depot.trip = drone.unit_number
  drive(trip, (loading_tile(provider.entity)))
  return true
end

local function dispatch(id, depot)
  if depot.trip then
    depot.status = logistics.status.delivering
    return
  end
  if shortfall(depot) <= 0 then
    depot.status = depot.request and logistics.status.satisfied or logistics.status.none
    return
  end
  local from, on_road = loading_tile(depot.entity)
  if not on_road then
    depot.status = logistics.status.no_road
    return
  end
  local provider, waiting = find_provider(depot, from)
  if not provider then
    depot.status = waiting and logistics.status.unreachable or logistics.status.no_provider
    return
  end
  if start_trip(id, depot, provider, from) then
    depot.status = logistics.status.delivering
  end
end

function logistics.on_tick()
  for id, depot in pairs(storage.depots) do
    if not depot.entity.valid then
      storage.depots[id] = nil
    elseif depot.role == "request" then
      dispatch(id, depot)
    end
  end
end

-- Leave anything still on board on the ground where the freighter stands, marked for
-- deconstruction so construction robots can collect it.
local function spill(trip, position)
  if trip.cargo > 0 then
    trip.drone.surface.spill_item_stack({
      position = position or trip.drone.position,
      stack = { name = trip.item, count = trip.cargo },
      enable_looted = true,
      force = trip.drone.force,
      allow_belts = false,
    })
    trip.cargo = 0
  end
end

local function end_trip(id, trip)
  storage.trips[id] = nil
  local depot = storage.depots[trip.request]
  if depot and depot.trip == id then
    depot.trip = nil
  end
  if trip.drone.valid then
    trip.drone.destroy()
  end
end

local function arrived_at_provider(id, trip, depot)
  local provider = storage.depots[trip.provider]
  local need = depot and depot.entity.valid and shortfall(depot) or 0
  if provider and provider.entity.valid and need > 0 then
    local stack_size = prototypes.item[trip.item].stack_size
    local wanted = math.min(need, CAPACITY_STACKS * stack_size)
    trip.cargo = inventory(provider.entity).remove({ name = trip.item, count = wanted })
  end
  if not (depot and depot.entity.valid) then
    -- The request depot is gone: nothing to bring back.
    return end_trip(id, trip)
  end
  trip.state = "to-request"
  drive(trip, (loading_tile(depot.entity)))
end

local function arrived_at_request(id, trip, depot)
  if depot and depot.entity.valid and trip.cargo > 0 then
    trip.cargo = trip.cargo - inventory(depot.entity).insert({ name = trip.item, count = trip.cargo })
  end
  spill(trip, depot and depot.entity.valid and (loading_tile(depot.entity)) or nil)
  end_trip(id, trip)
end

function logistics.on_ai_command_completed(event)
  local trip = storage.trips and storage.trips[event.unit_number]
  if not trip then
    return
  end
  local id = event.unit_number
  if not trip.drone.valid then
    storage.trips[id] = nil
    return
  end
  local depot = storage.depots[trip.request]
  if event.result ~= defines.behavior_result.success then
    -- No road route: try another provider (or this one later), and drop any cargo here.
    if depot and trip.state == "to-provider" then
      depot.cooldowns[trip.provider] = game.tick + RETRY_TICKS
    end
    spill(trip)
    return end_trip(id, trip)
  end
  if trip.state == "to-provider" then
    arrived_at_provider(id, trip, depot)
  else
    arrived_at_request(id, trip, depot)
  end
end

function logistics.on_object_destroyed(event)
  local id = event.useful_id
  if not id or not storage.depots then
    return
  end
  if storage.depots[id] then
    -- A request depot's freighter finishes its trip; arriving, it finds the depot gone.
    storage.depots[id] = nil
  elseif storage.trips[id] then
    -- A freighter destroyed on the way (by enemies, say): its cargo is lost.
    end_trip(id, storage.trips[id])
  end
end

-- Copying a request depot's settings onto another copies its request.
function logistics.on_entity_settings_pasted(event)
  if request_depot(event.source) and request_depot(event.destination) then
    local source = logistics.get_request(event.source)
    logistics.set_request(event.destination, source and source.item, source and source.count)
  end
end

function logistics.init()
  init_storage()
  logistics.add_all()
end

function logistics.register()
  script.on_nth_tick(DISPATCH_INTERVAL, logistics.on_tick)
  script.on_event(defines.events.on_ai_command_completed, logistics.on_ai_command_completed)
  script.on_event(defines.events.on_object_destroyed, logistics.on_object_destroyed)
  remote.add_interface("jatz-distribution", {
    -- For other mods and the tests: read and write a request depot's request and status.
    set_request = logistics.set_request,
    get_request = logistics.get_request,
    get_status = logistics.get_status,
  })
end

return logistics
