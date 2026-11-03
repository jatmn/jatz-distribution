-- SPDX-License-Identifier: LGPL-3.0-only
-- Deliveries between provider and request depots.
--
-- A request depot asks to keep at least `count` of one item (normal quality). Once a second,
-- each request depot that is short, has room for more and has no freighter on the way sends a
-- freighter from its loading zone to the nearest provider depot holding that item. The freighter
-- loads what is needed (no more than fits at the request depot, and at most ten stacks), drives
-- back, unloads and leaves the map. Freighters are units whose only collision layer is on every
-- tile except roads (prototypes/off-road.lua), so the engine's pathfinder keeps them on roads;
-- both loading zones must be road for a trip to start.
--
-- Cargo travels as real item stacks in a script inventory, so item data (equipment in armor,
-- spoilage, health) arrives intact. If the way back is lost, the freighter returns its cargo to
-- the provider; only when that fails too is the cargo left on the ground, marked for
-- deconstruction. A freighter destroyed on the way loses its cargo, like any destroyed vehicle.
--
-- Depots are registered when built or cloned (control.lua), found again on load, and forgotten
-- when destroyed. Fuel is not used yet, and freighters are created for each trip free of charge.
local loading_zone = require("scripts.loading-zone")

local logistics = {}

local PROVIDER = "jatz-provider-depot"
local REQUEST = "jatz-request-depot"
local ROAD = "jatz-road"
local DRONE = "jatz-freighter-drone"
logistics.depots = { [PROVIDER] = "provider", [REQUEST] = "request" }
logistics.drone = DRONE

local DISPATCH_INTERVAL = 60
-- A freighter carries at most this many stacks.
local CAPACITY_STACKS = 10
-- After a provider can't be reached, a request depot ignores it for this long; after a freighter
-- can't be created, the depot waits this long before trying again.
local RETRY_TICKS = 30 * 60
-- How close a freighter must get to a loading zone's centre to load or unload there.
local ARRIVAL_RADIUS = 0.5
-- Requests are for normal-quality items.
local QUALITY = "normal"

-- Status of a request depot, shown in its window: a key in the [jatz-request-status] locale section.
logistics.status = {
  none = "none",
  satisfied = "satisfied",
  full = "full",
  no_road = "no-road",
  no_provider = "no-provider",
  unreachable = "unreachable",
  no_freighter = "no-freighter",
  delivering = "delivering",
}

-- Trip states: driving out to the provider, bringing cargo to the request depot, or taking cargo
-- back to the provider after the way to the request depot was lost.
local TO_PROVIDER, TO_REQUEST, RETURNING = "to-provider", "to-request", "returning"

local function init_storage()
  storage.depots = storage.depots or {}
  storage.trips = storage.trips or {}
end

local function inventory(entity)
  return entity.get_inventory(defines.inventory.chest)
end

local function item_id(item)
  return { name = item, quality = QUALITY }
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
    -- Request depots only: { item = name, count = n }, retry cooldowns per provider, the tick
    -- before which no freighter is sent, the freighter on the way, and the status shown.
    request = nil,
    cooldowns = {},
    retry_at = 0,
    trip = nil,
    status = logistics.status.none,
  }
  script.register_on_object_destroyed(entity)
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

-- Set a request depot's request, or clear it with a nil item. Returns false, changing nothing,
-- for anything but a request depot, an item that doesn't exist, or a count that isn't a number.
function logistics.set_request(entity, item, count)
  local depot = request_depot(entity)
  if not depot then
    return false
  end
  if item == nil then
    depot.request = nil
  else
    count = tonumber(count or 0)
    if type(item) ~= "string" or not prototypes.item[item] or not count then
      return false
    end
    depot.request = { item = item, count = math.max(0, math.floor(count)) }
  end
  depot.cooldowns = {}
  depot.retry_at = 0
  return true
end

function logistics.get_status(entity)
  local depot = request_depot(entity)
  return depot and depot.status
end

-- How many of the requested item a request depot still wants, and how many of those it has room
-- for now. Requests above what the depot can hold are filled as far as it can hold.
local function need(depot)
  local request = depot.request
  if not request or request.count <= 0 or not prototypes.item[request.item] then
    return 0, 0
  end
  local chest, id = inventory(depot.entity), item_id(request.item)
  local wanted = request.count - chest.get_item_count(id)
  if wanted <= 0 then
    return 0, 0
  end
  return wanted, math.min(wanted, chest.get_insertable_count(id))
end

-- The nearest provider on the same surface and force, with road at its loading zone, holding the
-- item and not on cooldown for this request. Also says whether one was skipped for cooldown.
local function find_provider(depot, from)
  local entity, id = depot.entity, item_id(depot.request.item)
  local best, best_distance, waiting = nil, math.huge, false
  for unit_number, provider in pairs(storage.depots) do
    local candidate = provider.entity
    if
      provider.role == "provider"
      and candidate.valid
      and candidate.surface == entity.surface
      and candidate.force == entity.force
      and inventory(candidate).get_item_count(id) > 0
    then
      local position, on_road = loading_tile(candidate)
      if on_road then
        if (depot.cooldowns[unit_number] or 0) > game.tick then
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

local function start_trip(depot, provider, from)
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
    request = depot.entity.unit_number,
    provider = provider.entity.unit_number,
    item = depot.request.item,
    cargo = game.create_inventory(CAPACITY_STACKS),
    state = TO_PROVIDER,
  }
  -- on_object_destroyed reports an entity's unit_number as its useful_id, the key used here.
  storage.trips[drone.unit_number] = trip
  script.register_on_object_destroyed(drone)
  depot.trip = drone.unit_number
  drive(trip, (loading_tile(provider.entity)))
  return true
end

local function dispatch(depot)
  if depot.trip then
    depot.status = logistics.status.delivering
    return
  end
  local wanted, room = need(depot)
  if wanted <= 0 then
    depot.status = depot.request and logistics.status.satisfied or logistics.status.none
    return
  end
  if room <= 0 then
    depot.status = logistics.status.full
    return
  end
  local from, on_road = loading_tile(depot.entity)
  if not on_road then
    depot.status = logistics.status.no_road
    return
  end
  if (depot.retry_at or 0) > game.tick then
    depot.status = logistics.status.no_freighter
    return
  end
  local provider, waiting = find_provider(depot, from)
  if not provider then
    depot.status = waiting and logistics.status.unreachable or logistics.status.no_provider
  elseif start_trip(depot, provider, from) then
    depot.status = logistics.status.delivering
  else
    depot.retry_at = game.tick + RETRY_TICKS
    depot.status = logistics.status.no_freighter
  end
end

function logistics.on_tick()
  for id, depot in pairs(storage.depots) do
    if not depot.entity.valid then
      storage.depots[id] = nil
    elseif depot.role == "request" then
      dispatch(depot)
    end
  end
end

-- Move up to `limit` items of `item` (normal quality) from one inventory into another, stack by
-- stack, keeping each stack's data. Returns how many moved.
local function load(from, to, item, limit)
  local moved = 0
  for index = 1, #from do
    local stack = from[index]
    if moved >= limit then
      break
    end
    if stack.valid_for_read and stack.name == item and stack.quality.name == QUALITY then
      for slot = 1, #to do
        local target = to[slot]
        if moved >= limit or not stack.valid_for_read then
          break
        end
        if not target.valid_for_read or target.name == item then
          local before = stack.count
          target.transfer_stack(stack, math.min(before, limit - moved))
          moved = moved + before - (stack.valid_for_read and stack.count or 0)
        end
      end
    end
  end
  return moved
end

-- Insert all cargo into an inventory, keeping each stack's data; what doesn't fit stays aboard.
local function unload(cargo, into)
  for index = 1, #cargo do
    local stack = cargo[index]
    if stack.valid_for_read then
      local inserted = into.insert(stack)
      if inserted >= stack.count then
        stack.clear()
      elseif inserted > 0 then
        stack.count = stack.count - inserted
      end
    end
  end
end

-- Leave anything still aboard on the ground, marked for deconstruction so construction robots
-- can collect it.
local function spill(trip, position)
  local surface, force = trip.drone.surface, trip.drone.force
  for index = 1, #trip.cargo do
    local stack = trip.cargo[index]
    if stack.valid_for_read then
      surface.spill_item_stack({
        position = position or trip.drone.position,
        stack = stack,
        enable_looted = true,
        force = force,
        allow_belts = false,
      })
      stack.clear()
    end
  end
end

-- Saves from this PR's first version carried cargo as a plain count, and the mod version didn't
-- change, so no configuration change converts them: carry such cargo as stacks from here on.
local function upgrade(trip)
  if type(trip.cargo) == "number" then
    local count = trip.cargo
    trip.cargo = game.create_inventory(CAPACITY_STACKS)
    if count > 0 and prototypes.item[trip.item] then
      trip.cargo.insert({ name = trip.item, count = count })
    end
  end
  return trip
end

local function end_trip(id, trip)
  storage.trips[id] = nil
  local depot = storage.depots[trip.request]
  if depot and depot.trip == id then
    depot.trip = nil
  end
  if trip.cargo.valid then
    trip.cargo.destroy()
  end
  if trip.drone.valid then
    trip.drone.destroy()
  end
end

local function depot_entity(unit_number)
  local depot = storage.depots[unit_number]
  return depot and depot.entity.valid and depot.entity or nil
end

local function arrived_at_provider(id, trip, depot)
  local provider = depot_entity(trip.provider)
  local request = depot and depot.entity.valid and depot.request
  -- Load only what the request depot still asks for, and has room for: the request may have
  -- changed to another item, or been filled some other way, since the freighter set off.
  if provider and request and request.item == trip.item then
    local _, room = need(depot)
    load(inventory(provider), trip.cargo, trip.item, room)
  end
  if trip.cargo.is_empty() then
    return end_trip(id, trip)
  end
  trip.state = TO_REQUEST
  drive(trip, (loading_tile(depot.entity)))
end

local function arrived_at_request(id, trip, depot)
  local entity = depot and depot.entity.valid and depot.entity
  if entity then
    unload(trip.cargo, inventory(entity))
  end
  spill(trip, entity and (loading_tile(entity)) or nil)
  end_trip(id, trip)
end

local function returned_to_provider(id, trip)
  local provider = depot_entity(trip.provider)
  if provider then
    unload(trip.cargo, inventory(provider))
  end
  spill(trip, provider and (loading_tile(provider)) or nil)
  end_trip(id, trip)
end

-- The way was lost (no road route, or road removed on the way): don't try this provider again
-- for a while, and bring any cargo back to it, or leave it where the freighter stands.
local function route_failed(id, trip, depot)
  if depot then
    depot.cooldowns[trip.provider] = game.tick + RETRY_TICKS
  end
  local provider = depot_entity(trip.provider)
  if trip.state == TO_REQUEST and provider and not trip.cargo.is_empty() then
    trip.state = RETURNING
    return drive(trip, (loading_tile(provider)))
  end
  spill(trip)
  end_trip(id, trip)
end

function logistics.on_ai_command_completed(event)
  local id = event.unit_number
  local trip = storage.trips and storage.trips[id]
  if not trip then
    return
  end
  upgrade(trip)
  if not trip.drone.valid then
    return end_trip(id, trip)
  end
  local depot = storage.depots[trip.request]
  if event.result ~= defines.behavior_result.success then
    route_failed(id, trip, depot)
  elseif trip.state == TO_PROVIDER then
    arrived_at_provider(id, trip, depot)
  elseif trip.state == TO_REQUEST then
    arrived_at_request(id, trip, depot)
  else
    returned_to_provider(id, trip)
  end
end

function logistics.on_object_destroyed(event)
  -- For entities, useful_id is the unit_number: the key of storage.depots and storage.trips.
  local id = event.useful_id
  if event.type ~= defines.target_type.entity or not id or not storage.depots then
    return
  end
  if storage.depots[id] then
    -- A request depot's freighter finishes its trip; arriving, it finds the depot gone.
    storage.depots[id] = nil
  elseif storage.trips[id] then
    -- A freighter destroyed on the way (by enemies, say): its cargo is lost with it.
    end_trip(id, upgrade(storage.trips[id]))
  end
end

-- Copy one request depot's request onto another (Copy and Paste settings, and clones).
local function copy_request(source, destination)
  if request_depot(source) and request_depot(destination) then
    local request = logistics.get_request(source)
    logistics.set_request(destination, request and request.item, request and request.count)
  end
end

function logistics.on_entity_settings_pasted(event)
  copy_request(event.source, event.destination)
end

-- A cloned depot is a new depot with the original's request; a cloned freighter has no trip.
function logistics.on_cloned(source, destination)
  if destination.name == DRONE then
    destination.destroy()
    return
  end
  logistics.add(destination)
  copy_request(source, destination)
end

-- Find every provider and request depot already in the game (new saves and updated ones), and
-- make trips, freighters and requests agree with the game as loaded.
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
  for id, depot in pairs(storage.depots) do
    if not depot.entity.valid then
      storage.depots[id] = nil
    elseif depot.request and not prototypes.item[depot.request.item] then
      -- The requested item's mod was removed.
      depot.request = nil
    end
  end
  for id, trip in pairs(storage.trips) do
    upgrade(trip)
    -- Trips whose freighter, cargo or item is gone end; the engine already removed any cargo of
    -- a removed item from the cargo inventory.
    if not (trip.drone.valid and trip.cargo.valid and prototypes.item[trip.item]) then
      if trip.drone.valid and trip.cargo.valid then
        spill(trip)
      end
      end_trip(id, trip)
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
