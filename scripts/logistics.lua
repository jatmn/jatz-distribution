-- SPDX-License-Identifier: LGPL-3.0-only
-- Deliveries between provider and request depots.
--
-- A request depot asks to keep at least `count` of one item (normal quality), and holds the
-- freighters that fetch it: up to 100 of them, in its freighter slot. Once a second, while what it
-- still needs (less what freighters are already bringing) is more than nothing, it sends one more
-- freighter, so freighters leave one after another rather than all at once. Each goes from the
-- depot's loading zone to the provider depot nearest by road that has some of the item not
-- already promised to another freighter, and promises itself what it will load there (up to ten
-- stacks); once one provider's stock is all promised, the next freighter goes to the next
-- provider, so a large request is gathered from several. Road distance comes from the engine's pathfinder (surface.request_path, with the
-- freighter's own size and collision mask), asked one provider at a time in order of straight-line
-- distance until no remaining provider could be nearer by road than the best found; a provider
-- with no road route at all is skipped for a while, and no freighter is sent towards it. The freighter
-- loads what is needed (no more than fits at the request depot, and at most ten stacks), drives
-- back, unloads and leaves the map. Freighters are units whose only collision layer is on every
-- tile except roads (prototypes/off-road.lua), so the engine's pathfinder keeps them on roads;
-- both loading zones must be road for a trip to start.
--
-- Cargo travels as real item stacks in a script inventory, so item data (equipment in armor,
-- spoilage, health) arrives intact. If the way back is lost, the freighter returns its cargo to
-- the provider; only when that fails too is the cargo left on the ground, marked for
-- deconstruction. A freighter destroyed on the way is lost with its cargo, like any destroyed
-- vehicle; otherwise every freighter goes back into its depot's slot when its trip ends.
--
-- Depots are registered when built or cloned (control.lua), found again on load, and forgotten
-- when destroyed. A request depot mined by a player or robot hands over all its freighters, in the
-- slot and out on trips; one destroyed leaves them on the ground where it stood. Fuel is not used
-- yet.
local loading_zone = require("scripts.loading-zone")

local logistics = {}

local PROVIDER = "jatz-provider-depot"
local REQUEST = "jatz-request-depot"
local ROAD = "jatz-road"
-- The road a depot lays under its own loading zone (scripts/depot-road.lua).
local DEPOT_ROAD = "jatz-depot-road"
local DRONE = "jatz-freighter-drone"
-- The freighter item: what a request depot's freighter slot holds.
local FREIGHTER = "jatz-quinityn-freighter"
-- A request depot holds up to this many freighters (in its slot and out on trips together). The
-- freighter item stacks to 10, so the slot is that many stacks, shown as one slot in the panel.
local FREIGHTER_CAPACITY = 100
logistics.depots = { [PROVIDER] = "provider", [REQUEST] = "request" }
logistics.drone = DRONE
logistics.freighter = FREIGHTER

local DISPATCH_INTERVAL = 60
-- A request depot sends at most one freighter this often, so they leave one after another.
local SEND_SPACING = 60
-- A freighter carries at most this many stacks.
local CAPACITY_STACKS = 10
-- After a provider can't be reached, a request depot ignores it for this long; after a freighter
-- can't be created, the depot waits this long before trying again. Laying road, or building or
-- turning a depot, ends every wait on that surface at once (logistics.on_roads_changed and
-- logistics.on_depot_changed), so this only matters for changes the game doesn't report.
local RETRY_TICKS = 10 * 60
-- How close a freighter must get to a loading zone's centre to load or unload there.
local ARRIVAL_RADIUS = 0.5
-- A search for the nearest provider by road that hasn't answered in this long (a save loaded
-- mid-search, say) is started again.
local SEARCH_TIMEOUT = 10 * 60
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
  no_trucks = "no-trucks",
  searching = "searching",
  delivering = "delivering",
}

-- Trip states: driving out to the provider, bringing cargo to the request depot, or taking cargo
-- back to the provider after the way to the request depot was lost.
local TO_PROVIDER, TO_REQUEST, RETURNING = "to-provider", "to-request", "returning"

-- Defined further down; dispatch and the search need them first.
local end_trip, load, freighter_requests

local function init_storage()
  storage.depots = storage.depots or {}
  storage.trips = storage.trips or {}
  -- Provider searches waiting for the pathfinder, by path request id.
  storage.searches = storage.searches or {}
end

-- Drop a request depot's current search; the next dispatch, within a second, starts a fresh one.
local function cancel_search(depot)
  depot.search_token = nil
  depot.searching = nil
end

local function inventory(entity)
  return entity.get_inventory(defines.inventory.chest)
end

local function item_id(item)
  return { name = item, quality = QUALITY }
end

-- Freighters of every quality in an inventory: any freighter can be sent out.
local function count_freighters(inventory_)
  local total = 0
  for index = 1, #inventory_ do
    local stack = inventory_[index]
    if stack.valid_for_read and stack.name == FREIGHTER then
      total = total + stack.count
    end
  end
  return total
end

-- The loading zone tile's centre, and whether it is road.
local function loading_tile(entity)
  local x, y = loading_zone.tile_centre(entity)
  local tile = entity.surface.get_tile(math.floor(x), math.floor(y))
  return { x = x, y = y }, tile.valid and (tile.name == ROAD or tile.name == DEPOT_ROAD)
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
    -- Where it stands, for handing back freighters once the entity is gone.
    position = entity.position,
    surface_index = entity.surface_index,
    -- Request depots only: { item = name, count = n }, retry cooldowns per provider, the tick
    -- before which no freighter is sent, the freighters out (trip ids), the freighter slot (a
    -- one-slot script inventory, made on first use), and the status shown.
    request = nil,
    cooldowns = {},
    retry_at = 0,
    trips = {},
    trucks = nil,
    status = logistics.status.none,
  }
  script.register_on_object_destroyed(entity)
end

-- A request depot's freighter slot: room for FREIGHTER_CAPACITY freighters, as real items, in as
-- many stacks as that takes. Slots from saves when it held one stack are made bigger.
local function trucks_of(depot)
  local stacks = math.ceil(FREIGHTER_CAPACITY / prototypes.item[FREIGHTER].stack_size)
  if not (depot.trucks and depot.trucks.valid) then
    depot.trucks = game.create_inventory(stacks)
  elseif #depot.trucks < stacks then
    depot.trucks.resize(stacks)
  end
  return depot.trucks
end

-- The first stack of freighters in a depot's slot, or nil.
local function a_freighter(depot)
  local slot = trucks_of(depot)
  for index = 1, #slot do
    if slot[index].valid_for_read then
      return slot[index]
    end
  end
end

-- The ids of a request depot's trips. Saves from before depots sent several freighters kept one.
local function trips_of(depot)
  if not depot.trips then
    depot.trips = {}
    if depot.trip then
      depot.trips[depot.trip] = true
      depot.trip = nil
    end
  end
  return depot.trips
end

-- What a trip will bring: what it promised to load while on its way out, its cargo on the way back.
local function bringing(trip)
  if trip.state == TO_PROVIDER then
    return trip.planned or 0
  elseif trip.state == TO_REQUEST and trip.cargo.valid then
    return trip.cargo.get_item_count(item_id(trip.item))
  end
  return 0
end

-- What a request depot's freighters, except trip `except`, are bringing.
local function committed(depot, except)
  local total = 0
  local item = depot.request and depot.request.item
  for id in pairs(trips_of(depot)) do
    local trip = storage.trips[id]
    -- Trips for an item the depot no longer asks for bring nothing it needs.
    if trip and id ~= except and trip.item == item then
      total = total + bringing(trip)
    end
  end
  return total
end

-- How much of `item` a provider has that no freighter on its way there has promised to load.
local function available(provider, item)
  local count = inventory(provider.entity).get_item_count(item_id(item))
  for _, trip in pairs(storage.trips) do
    if trip.provider == provider.entity.unit_number and trip.item == item and trip.state == TO_PROVIDER then
      count = count - (trip.planned or 0)
    end
  end
  return count
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
  -- A search under way was for the old request.
  cancel_search(depot)
  -- Freighters on their way out for another item will load nothing (arrived_at_provider checks
  -- the request), so their promises no longer hold that provider's stock.
  for id in pairs(trips_of(depot)) do
    local trip = storage.trips[id]
    if trip and trip.state == TO_PROVIDER and trip.item ~= (depot.request and depot.request.item) then
      trip.planned = 0
    end
  end
  return true
end

function logistics.get_status(entity)
  local depot = request_depot(entity)
  return depot and depot.status
end

-- How many of the requested item a request depot still wants, and how many of those it has room
-- for, counting what its freighters (except trip `except`) are already bringing. Requests above
-- what the depot can hold are filled as far as it can hold.
local function need(depot, except)
  local request = depot.request
  if not request or request.count <= 0 or not prototypes.item[request.item] then
    return 0, 0
  end
  local chest, id = inventory(depot.entity), item_id(request.item)
  local coming = committed(depot, except)
  local wanted = request.count - chest.get_item_count(id) - coming
  if wanted <= 0 then
    return 0, 0
  end
  return wanted, math.max(0, math.min(wanted, chest.get_insertable_count(id) - coming))
end

-- Every provider that could serve a request depot: on the same surface and force, with road at its
-- loading zone, holding the item and not on cooldown for this request; nearest first in a straight
-- line from `from`. Also says whether one was skipped for cooldown.
local function candidates(depot, from)
  local entity = depot.entity
  local found, waiting = {}, false
  for unit_number, provider in pairs(storage.depots) do
    local candidate = provider.entity
    if
      provider.role == "provider"
      and candidate.valid
      and candidate.surface == entity.surface
      and candidate.force == entity.force
      and available(provider, depot.request.item) > 0
    then
      local position, on_road = loading_tile(candidate)
      if on_road then
        if (depot.cooldowns[unit_number] or 0) > game.tick then
          waiting = true
        else
          local dx, dy = position.x - from.x, position.y - from.y
          found[#found + 1] = { id = unit_number, position = position, distance = math.sqrt(dx * dx + dy * dy) }
        end
      end
    end
  end
  table.sort(found, function(a, b)
    return a.distance < b.distance or (a.distance == b.distance and a.id < b.id)
  end)
  return found, waiting
end

local function drive(trip, destination)
  trip.destination = destination
  trip.drone.commandable.set_command({
    type = defines.command.go_to_location,
    destination = destination,
    radius = ARRIVAL_RADIUS,
    distraction = defines.distraction.none,
    pathfind_flags = { no_break = true },
  })
end

-- Send one of a request depot's freighters to `provider`, to load `planned` of the item.
local function start_trip(depot, provider, from, planned)
  local slot = a_freighter(depot)
  if not slot then
    return false
  end
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
    -- The freighter item it was, taken from the depot's slot; it goes back there afterwards.
    truck = game.create_inventory(1),
    planned = planned,
    state = TO_PROVIDER,
  }
  trip.truck[1].transfer_stack(slot, 1)
  -- on_object_destroyed reports an entity's unit_number as its useful_id, the key used here.
  storage.trips[drone.unit_number] = trip
  script.register_on_object_destroyed(drone)
  trips_of(depot)[drone.unit_number] = true
  depot.next_send = game.tick + SEND_SPACING
  drive(trip, (loading_tile(provider.entity)))
  return true
end

-- Searches belong to a request depot (finding a provider to send a freighter to) or to a trip (a
-- freighter whose provider was removed). Each search has a token, and its owner keeps the token of
-- its one current search. Whatever makes a search stale (road or depot changes, a new request, a
-- busy pathfinder, a timeout) takes the owner's token away or replaces it, so the old search's
-- answers are ignored: they neither put providers on cooldown nor send freighters, and the old
-- search asks the pathfinder nothing more.
local function new_token()
  storage.search_count = (storage.search_count or 0) + 1
  return storage.search_count
end

-- The depot or trip a search belongs to, if it is still that owner's current search.
local function owner_of(search)
  if search.trip then
    local trip = storage.trips[search.trip]
    return trip and trip.search_token == search.token and trip or nil
  end
  local depot = storage.depots[search.request]
  return depot and depot.search_token == search.token and depot or nil
end

-- Ask the pathfinder for the road route from the search's start to its current candidate, as the
-- freighter would drive it.
local function ask_route(search, surface, force)
  local drone = prototypes.entity[DRONE]
  local id = surface.request_path({
    bounding_box = drone.collision_box,
    collision_mask = drone.collision_mask,
    start = search.from,
    goal = search.candidates[search.index].position,
    force = force,
    radius = ARRIVAL_RADIUS,
    pathfind_flags = { no_break = true },
  })
  -- Saves from before searches existed have no table yet, and their mod version is the same.
  storage.searches = storage.searches or {}
  storage.searches[id] = search
end

-- Start looking for the provider nearest by road. With `trip`, the search is for a freighter
-- already out (its provider was removed) and starts where it stands. Returns false, with whether
-- a provider was skipped for cooldown, if there is nothing to look for.
local function search_providers(depot, from, trip)
  local found, waiting = candidates(depot, from)
  if #found == 0 then
    return false, waiting
  end
  local search = {
    token = new_token(),
    request = depot.entity.unit_number,
    item = depot.request.item,
    from = from,
    candidates = found,
    index = 1,
    trip = trip,
  }
  local owner = trip and storage.trips[trip] or depot
  owner.search_token = search.token
  owner.searching = game.tick
  ask_route(search, depot.entity.surface, depot.entity.force)
  return true
end

-- Find a new provider, nearest by road from where it stands, for a freighter whose provider is
-- gone or no longer suitable. It waits while the search runs, and leaves if there is none.
local function reroute(id, trip)
  local depot = storage.depots[trip.request]
  local request = depot and depot.entity.valid and depot.request
  trip.search_token, trip.searching = nil, nil
  if
    trip.drone.valid
    and request
    and request.item == trip.item
    and search_providers(depot, trip.drone.position, id)
  then
    trip.drone.commandable.set_command({ type = defines.command.stop, distraction = defines.distraction.none })
  elseif trip.drone.valid and depot and depot.entity.valid then
    -- No provider for it any more: home empty, to park.
    trip.planned = nil
    trip.state = TO_REQUEST
    drive(trip, (loading_tile(depot.entity)))
  else
    end_trip(id, trip)
  end
end

local function path_length(from, path)
  local length, x, y = 0, from.x, from.y
  for _, waypoint in ipairs(path) do
    local position = waypoint.position
    length = length + math.sqrt((position.x - x) ^ 2 + (position.y - y) ^ 2)
    x, y = position.x, position.y
  end
  return length
end

-- Freighters put into a request depot's chest (by hand, inserters or robots) go into its slot, as
-- far as it has room, unless freighters are what it requests.
local function absorb_freighters(depot)
  if depot.request and depot.request.item == FREIGHTER then
    return
  end
  local chest = inventory(depot.entity)
  if count_freighters(chest) == 0 then
    depot.chest_seen = 0
    return
  end
  local slot = trucks_of(depot)
  local out = 0
  for id in pairs(trips_of(depot)) do
    local trip = storage.trips[id]
    if trip and trip.truck and trip.truck.valid and not trip.truck.is_empty() then
      out = out + 1
    end
  end
  local room = FREIGHTER_CAPACITY - slot.get_item_count() - out
  if room > 0 then
    -- Freighters waiting in the chest for robots to take them away stay there.
    load(chest, slot, FREIGHTER, room, logistics.leaving(depot.entity), true)
  end
  -- What the chest holds now, so freighters a player puts in later can be told apart.
  depot.chest_seen = count_freighters(chest)
end

local function dispatch(depot)
  absorb_freighters(depot)
  logistics.trim_freighter_requests(depot.entity)
  -- "On its way" only while a freighter is bringing some of the requested item: not one taking
  -- cargo back to its provider, nor one driving home empty.
  local out = committed(depot) > 0
  local wanted, room = need(depot)
  if wanted <= 0 then
    depot.status = out and logistics.status.delivering
      or (depot.request and logistics.status.satisfied or logistics.status.none)
    return
  end
  if room <= 0 then
    depot.status = out and logistics.status.delivering or logistics.status.full
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
  if trucks_of(depot).is_empty() then
    depot.status = out and logistics.status.delivering or logistics.status.no_trucks
    return
  end
  if (depot.next_send or 0) > game.tick then
    -- The last freighter left less than SEND_SPACING ago.
    return
  end
  if depot.searching and game.tick - depot.searching < SEARCH_TIMEOUT then
    return
  end
  local started, waiting = search_providers(depot, from)
  if started then
    depot.status = out and logistics.status.delivering or logistics.status.searching
  else
    cancel_search(depot)
    depot.status = out and logistics.status.delivering
      or (waiting and logistics.status.unreachable or logistics.status.no_provider)
  end
end

function logistics.on_tick()
  -- A freighter whose reroute search never answered (or met a busy pathfinder) searches again.
  for id, trip in pairs(storage.trips) do
    if trip.searching and game.tick - trip.searching >= SEARCH_TIMEOUT then
      reroute(id, trip)
    end
  end
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
-- `leave`, if given, maps `from` stack indices to how many items to leave in that stack. With
-- `any_quality`, items of every quality move (freighters do), not only normal quality (cargo).
function load(from, to, item, limit, leave, any_quality)
  local moved = 0
  for index = 1, #from do
    local stack = from[index]
    if moved >= limit then
      break
    end
    if stack.valid_for_read and stack.name == item and (any_quality or stack.quality.name == QUALITY) then
      local kept = leave and leave[index] or 0
      for slot = 1, #to do
        local target = to[slot]
        local movable = (stack.valid_for_read and stack.count or 0) - kept
        if moved >= limit or movable <= 0 then
          break
        end
        if not target.valid_for_read or target.name == item then
          local before = stack.count
          target.transfer_stack(stack, math.min(movable, limit - moved))
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

-- End a trip: its freighter leaves the map and goes back into its depot's slot as an item, unless
-- it was `lost` (destroyed on the way). If the depot is gone it has already handed its freighters
-- over; one somehow still aboard is left where the freighter stands.
function end_trip(id, trip, lost)
  storage.trips[id] = nil
  local depot = storage.depots[trip.request]
  if depot and depot.trips then
    depot.trips[id] = nil
  end
  local truck = trip.truck and trip.truck.valid and trip.truck[1]
  if truck and truck.valid_for_read and not lost then
    if depot and depot.entity.valid then
      local inserted = trucks_of(depot).insert(truck)
      if inserted >= truck.count then
        truck.clear()
      else
        truck.count = truck.count - inserted
      end
    end
    if truck.valid_for_read and trip.drone.valid then
      trip.drone.surface.spill_item_stack({
        position = trip.drone.position,
        stack = truck,
        enable_looted = true,
        force = trip.drone.force,
        allow_belts = false,
      })
    end
  end
  if trip.truck and trip.truck.valid then
    trip.truck.destroy()
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
    -- What it promised, as far as the depot (counting its other freighters) still needs it.
    local _, room = need(depot, id)
    load(inventory(provider), trip.cargo, trip.item, math.min(trip.planned or room, room))
  end
  trip.planned = nil
  if not (depot and depot.entity.valid) then
    return end_trip(id, trip)
  end
  -- Home, loaded or (if there was nothing to load) empty, to unload and park.
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
  -- A command replaced by a newer one (see replan) is not the end of anything, and a freighter
  -- waiting for a reroute search has nowhere to arrive.
  if not trip or event.result == defines.behavior_result.deleted or trip.searching then
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

-- Where a trip is heading: the provider's loading zone, or the request depot's with cargo.
local function target(trip)
  local depot = depot_entity(trip.state == TO_REQUEST and trip.request or trip.provider)
  return depot and (loading_tile(depot)) or trip.destination
end

-- Plan a freighter's route again from where it stands. A route that no longer exists fails at
-- once (on_ai_command_completed), instead of after the freighter stands stuck for seconds.
local function replan(trip)
  -- A freighter waiting for a reroute search stays put; the search decides where it goes.
  if trip.drone.valid and trip.destination and not trip.searching then
    drive(trip, target(trip))
  end
end

-- Forget cooldowns of the request depots on a surface: their routes may exist now.
local function retry_now(surface_index)
  for _, depot in pairs(storage.depots) do
    if depot.role == "request" and depot.entity.valid and depot.entity.surface_index == surface_index then
      depot.cooldowns = {}
      depot.retry_at = 0
    end
  end
end

-- Searches on a surface may have used roads or depots that changed since: start them again.
local function restart_searches(surface_index)
  for _, depot in pairs(storage.depots) do
    if depot.search_token and depot.entity.valid and depot.entity.surface_index == surface_index then
      cancel_search(depot)
    end
  end
  for id, trip in pairs(storage.trips) do
    if trip.search_token and trip.drone.valid and trip.drone.surface_index == surface_index then
      reroute(id, trip)
    end
  end
end

-- Road was laid (`added`) or removed or covered (`removed`) on a surface.
function logistics.on_roads_changed(surface_index, added, removed)
  if not storage.depots then
    return
  end
  restart_searches(surface_index)
  if added then
    retry_now(surface_index)
  end
  if removed then
    for _, trip in pairs(storage.trips) do
      if trip.drone.valid and trip.drone.surface_index == surface_index then
        replan(upgrade(trip))
      end
    end
  end
end

-- A depot was built, turned or flipped: routes to and from it changed.
function logistics.on_depot_changed(entity)
  if not storage.depots or not logistics.depots[entity.name] then
    return
  end
  retry_now(entity.surface_index)
  restart_searches(entity.surface_index)
  for _, trip in pairs(storage.trips) do
    if trip.provider == entity.unit_number or trip.request == entity.unit_number then
      replan(upgrade(trip))
    end
  end
end

-- A depot was removed: trips to it go elsewhere now, rather than finding it gone on arrival.
local function depot_removed(id)
  for trip_id, trip in pairs(storage.trips) do
    upgrade(trip)
    if not trip.drone.valid then
      end_trip(trip_id, trip)
    elseif trip.request == id then
      -- Nobody to deliver to: cargo goes back to the provider, an empty freighter just leaves.
      if trip.state == TO_REQUEST and depot_entity(trip.provider) then
        trip.state = RETURNING
        replan(trip)
      elseif trip.state == TO_PROVIDER or trip.cargo.is_empty() then
        end_trip(trip_id, trip)
      end
    elseif trip.provider == id and trip.state == RETURNING then
      -- Bringing cargo back to a provider that is gone: try the request depot again.
      if depot_entity(trip.request) then
        trip.state = TO_REQUEST
        replan(trip)
      else
        spill(trip)
        end_trip(trip_id, trip)
      end
    elseif trip.provider == id and trip.state == TO_PROVIDER then
      reroute(trip_id, trip)
    end
  end
end

-- The search is over: send a freighter to the provider nearest by road (or redirect the freighter
-- the search was for), if the request still wants the item.
local function finish_search(depot, search, owner)
  local provider = search.best and storage.depots[search.best]
  local still = depot.request
    and depot.request.item == search.item
    and provider
    and provider.entity.valid
    and available(provider, search.item) > 0
  if search.trip then
    if still then
      owner.search_token, owner.searching = nil, nil
      -- Promise only what the new provider has unpromised (this trip's old promise was at the
      -- removed provider, so `available` doesn't count it).
      owner.planned = math.min(owner.planned or 0, available(provider, search.item))
      owner.provider = search.best
      drive(owner, (loading_tile(provider.entity)))
    else
      -- The provider found was emptied or removed meanwhile: look again among the rest.
      reroute(search.trip, owner)
    end
    return
  end
  cancel_search(depot)
  if not search.best then
    -- No provider with the item has a road route: each is on cooldown now.
    depot.status = logistics.status.unreachable
    return
  end
  local from, on_road = loading_tile(depot.entity)
  local _, room = need(depot)
  if not still or not on_road or room <= 0 then
    -- Something changed while searching; the next dispatch looks again.
    return
  end
  -- This freighter promises to load what the depot still needs, as far as the provider has it
  -- unpromised and it can carry; the next freighter covers the rest, from here or elsewhere.
  local capacity = CAPACITY_STACKS * prototypes.item[search.item].stack_size
  local planned = math.min(room, available(provider, search.item), capacity)
  if start_trip(depot, provider, from, planned) then
    depot.status = logistics.status.delivering
  else
    depot.retry_at = game.tick + RETRY_TICKS
    depot.status = logistics.status.no_freighter
  end
end

function logistics.on_script_path_request_finished(event)
  local search = storage.searches and storage.searches[event.id]
  if not search then
    return
  end
  storage.searches[event.id] = nil
  local owner = owner_of(search)
  local depot = storage.depots[search.request]
  if not (owner and depot and depot.entity.valid) then
    return
  end
  if event.try_again_later then
    -- The pathfinder is busy: this search ends, and a new one starts at the next dispatch (or, for
    -- a freighter, the next once-a-second check), so a busy pathfinder is asked at most once a
    -- second per owner.
    if search.trip then
      owner.search_token, owner.searching = nil, game.tick - SEARCH_TIMEOUT
    else
      cancel_search(depot)
    end
    return
  end
  local candidate = search.candidates[search.index]
  if event.path then
    local length = path_length(search.from, event.path)
    if length < (search.best_length or math.huge) then
      search.best, search.best_length = candidate.id, length
    end
  else
    depot.cooldowns[candidate.id] = game.tick + RETRY_TICKS
  end
  -- A road is never shorter than the straight line, so stop at the first candidate that is
  -- already farther away in a straight line than the best road found.
  search.index = search.index + 1
  local next_candidate = search.candidates[search.index]
  if next_candidate and next_candidate.distance < (search.best_length or math.huge) then
    return ask_route(search, depot.entity.surface, depot.entity.force)
  end
  finish_search(depot, search, owner)
end

-- Hand over every freighter a request depot holds, in its slot and out on trips: into `buffer`
-- (what a player or robot receives for mining it), or, without one or past its room, onto the
-- ground where the depot stood. Freighters out finish their trips, then just leave.
local function refund(depot, buffer, chest)
  local stacks = {}
  if depot.trucks and depot.trucks.valid then
    for index = 1, #depot.trucks do
      stacks[#stacks + 1] = depot.trucks[index]
    end
  end
  -- Freighters still in the chest of a depot about to be destroyed (its slot may be full).
  if chest then
    for index = 1, #chest do
      local stack = chest[index]
      if stack.valid_for_read and stack.name == FREIGHTER then
        stacks[#stacks + 1] = stack
      end
    end
  end
  for id in pairs(trips_of(depot)) do
    local trip = storage.trips[id]
    if trip and trip.truck and trip.truck.valid then
      stacks[#stacks + 1] = trip.truck[1]
    end
  end
  local surface = game.surfaces[depot.surface_index or (depot.entity.valid and depot.entity.surface_index)]
  for _, stack in ipairs(stacks) do
    if stack.valid_for_read and buffer then
      local inserted = buffer.insert(stack)
      if inserted >= stack.count then
        stack.clear()
      else
        stack.count = stack.count - inserted
      end
    end
    if stack.valid_for_read and surface then
      surface.spill_item_stack({
        position = depot.position or depot.entity.position,
        stack = stack,
        enable_looted = true,
        allow_belts = false,
      })
    end
    stack.clear()
  end
end

-- A request depot about to be destroyed (died, or a script raising script_raised_destroy): all its
-- freighters, in the slot, out on trips and still in its chest, are left where it stands.
function logistics.on_depot_destroyed(event)
  local depot = request_depot(event.entity)
  if depot then
    refund(depot, nil, inventory(event.entity))
  end
end

-- A request depot mined by a player, robot or platform: its freighters go with it.
function logistics.on_depot_mined(event)
  local depot = request_depot(event.entity)
  if depot then
    refund(depot, event.buffer)
  end
end

function logistics.on_object_destroyed(event)
  -- For entities, useful_id is the unit_number: the key of storage.depots and storage.trips.
  local id = event.useful_id
  if event.type ~= defines.target_type.entity or not id or not storage.depots then
    return
  end
  local depot = storage.depots[id]
  if depot then
    if depot.role == "request" then
      -- Destroyed rather than mined (or by a script): its freighters are left where it stood.
      refund(depot, nil)
      if depot.trucks and depot.trucks.valid then
        depot.trucks.destroy()
      end
    end
    storage.depots[id] = nil
    depot_removed(id)
  elseif storage.trips[id] then
    -- A freighter destroyed on the way (by enemies, say): it is lost, with its cargo.
    end_trip(id, upgrade(storage.trips[id]), true)
  end
end

-- Copy one request depot's request onto another (Copy and Paste settings, and clones).
local function copy_request(source, destination)
  if request_depot(source) and request_depot(destination) then
    local request = logistics.get_request(source)
    logistics.set_request(destination, request and request.item, request and request.count)
  end
end

-- Copy and Paste settings: the request, and the freighters. The destination asks robots for as
-- many more freighters as it takes to match the source's (in its slot, out and coming); a player
-- can fill them in by hand instead.
function logistics.on_entity_settings_pasted(event)
  copy_request(event.source, event.destination)
  if request_depot(event.source) and request_depot(event.destination) then
    -- All the source has or will have: slot, out, chest (not leaving) and coming.
    logistics.match_freighters(event.destination, logistics.freighter_total(event.source))
  end
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
  -- Searches still waiting for the pathfinder start again from scratch.
  storage.searches = {}
  for id, depot in pairs(storage.depots) do
    cancel_search(depot)
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
  for id, trip in pairs(storage.trips) do
    if trip.searching then
      reroute(id, trip)
    end
  end
  for _, depot in pairs(storage.depots) do
    if depot.role == "request" then
      for id in pairs(trips_of(depot)) do
        if not storage.trips[id] then
          depot.trips[id] = nil
        end
      end
      depot.position = depot.position or (depot.entity.valid and depot.entity.position)
      depot.surface_index = depot.surface_index or (depot.entity.valid and depot.entity.surface_index)
    end
  end
end

-- A request depot's freighters: how many are in its slot, how many are out on trips, and the most
-- it can hold in all (FREIGHTER_CAPACITY). Nil for anything but a request depot.
function logistics.freighter_counts(entity)
  local depot = request_depot(entity)
  if not depot then
    return nil
  end
  local out = 0
  for id in pairs(trips_of(depot)) do
    local trip = storage.trips[id]
    if trip and trip.truck and trip.truck.valid and not trip.truck.is_empty() then
      out = out + 1
    end
  end
  return trucks_of(depot).get_item_count(), out, FREIGHTER_CAPACITY
end

-- Freighters can also be requested, like modules or fuel: an item request proxy asks construction
-- robots to deliver them into the depot's chest, from where they move into the slot. This is how a
-- player in remote view (or anywhere without freighters in hand) stocks a depot.
local PROXY = "item-request-proxy"

local function item_name(id)
  return type(id) == "string" and id or id.name
end

-- The item request proxies targeting a request depot; how many freighters they still ask robots to
-- bring, and to take away; and the chest stacks (0-based) freighters are to be taken from.
function freighter_requests(entity)
  local proxies, requested, removing, marked = {}, 0, 0, {}
  local x, y = entity.position.x, entity.position.y
  for _, proxy in
    pairs(entity.surface.find_entities_filtered({
      name = PROXY,
      area = { { x - 0.5, y - 0.5 }, { x + 0.5, y + 0.5 } },
    }))
  do
    if proxy.proxy_target == entity then
      proxies[#proxies + 1] = proxy
      for _, request in pairs(proxy.item_requests) do
        if item_name(request.name) == FREIGHTER then
          requested = requested + request.count
        end
      end
      for _, plan in pairs(proxy.removal_plan) do
        if item_name(plan.id.name) == FREIGHTER then
          for _, position in pairs(plan.items.in_inventory or {}) do
            removing = removing + (position.count or 1)
            marked[position.stack] = (marked[position.stack] or 0) + (position.count or 1)
          end
        end
      end
    end
  end
  return proxies, requested, removing, marked
end

-- How many freighters a request depot has asked robots to bring, and to take away.
function logistics.requested_freighters(entity)
  if not request_depot(entity) then
    return 0, 0
  end
  local _, requested, removing = freighter_requests(entity)
  return requested, removing
end

-- Chest stacks (0-based) that are empty and in no request's plan, as a list.
local function free_chest_stacks(chest, proxies)
  local taken = {}
  for _, proxy in ipairs(proxies) do
    for _, plans in ipairs({ proxy.insert_plan, proxy.removal_plan }) do
      for _, plan in pairs(plans) do
        for _, position in pairs(plan.items.in_inventory or {}) do
          taken[position.stack] = true
        end
      end
    end
  end
  local free = {}
  for index = 1, #chest do
    if not chest[index].valid_for_read and not taken[index - 1] then
      free[#free + 1] = index - 1
    end
  end
  return free
end

-- Positions for `amount` freighters, a stack at a time, in the given chest stacks (0-based); the
-- amount that fits, and the positions.
local function spread(amount, stacks)
  local stack_size = prototypes.item[FREIGHTER].stack_size
  local positions, placed = {}, 0
  for _, stack in ipairs(stacks) do
    if placed >= amount then
      break
    end
    local count = math.min(stack_size, amount - placed)
    positions[#positions + 1] = { inventory = defines.inventory.chest, stack = stack, count = count }
    placed = placed + count
  end
  return placed, positions
end

-- Add an insert or removal plan to a depot's request proxy, making one if it has none.
local function add_plan(entity, proxies, plan, removal)
  local proxy = proxies[1]
  if proxy then
    local plans = removal and proxy.removal_plan or proxy.insert_plan
    plans[#plans + 1] = plan
    if removal then
      proxy.removal_plan = plans
    else
      proxy.insert_plan = plans
    end
  else
    entity.surface.create_entity({
      name = PROXY,
      position = entity.position,
      force = entity.force,
      target = entity,
      modules = removal and {} or { plan },
      removal_plan = removal and { plan } or nil,
    })
  end
end

-- Ask construction robots to bring `count` freighters (or as many as the slot has room for,
-- counting freighters out, in the chest and already requested) into a request depot's chest.
-- Returns how many were requested.
function logistics.request_freighters(entity, count)
  local in_slot, out, capacity = logistics.freighter_counts(entity)
  if not in_slot then
    return 0
  end
  local chest = inventory(entity)
  local proxies, requested, removing = freighter_requests(entity)
  -- Freighters in the chest count, except those waiting to be taken away.
  local in_chest = count_freighters(chest) - removing
  local room = capacity - in_slot - out - requested - in_chest
  local amount = math.min(math.floor(tonumber(count) or room), room)
  if amount <= 0 then
    return 0
  end
  -- A stack at a time, into chest stacks that are empty and in no other plan.
  local positions
  amount, positions = spread(amount, free_chest_stacks(chest, proxies))
  if amount <= 0 then
    return 0
  end
  add_plan(entity, proxies, {
    id = { name = FREIGHTER, quality = QUALITY },
    items = { in_inventory = positions },
  })
  -- What these requests are for: the depot ending up with this many. Freighters arriving some
  -- other way (put in by hand) count towards it, and requests beyond it are cancelled.
  request_depot(entity).freighter_target = in_slot + out + in_chest + requested + amount
  return amount
end

-- Have construction robots take `count` freighters (or all) out of a request depot's slot, as
-- from remote view: they move into an empty chest stack marked for removal, and robots carry them
-- to storage. Returns how many were marked.
function logistics.remove_freighters(entity, count)
  local depot = request_depot(entity)
  if not depot then
    return 0
  end
  -- Taking freighters away on purpose: no longer top the depot up to an earlier target.
  depot.freighter_target = nil
  local slot = trucks_of(depot)
  local wanted = math.min(math.floor(tonumber(count) or slot.get_item_count()), slot.get_item_count())
  if wanted <= 0 then
    return 0
  end
  local chest = inventory(entity)
  local proxies = freighter_requests(entity)
  -- A stack at a time from the slot into empty chest stacks, each marked for removal.
  local positions, moved = {}, 0
  for _, index in ipairs(free_chest_stacks(chest, proxies)) do
    local from = a_freighter(depot)
    if moved >= wanted or not from then
      break
    end
    local into = chest[index + 1]
    into.transfer_stack(from, math.min(from.count, wanted - moved))
    if into.valid_for_read then
      positions[#positions + 1] = { inventory = defines.inventory.chest, stack = index, count = into.count }
      moved = moved + into.count
    end
  end
  if moved > 0 then
    add_plan(
      entity,
      proxies,
      { id = { name = FREIGHTER, quality = QUALITY }, items = { in_inventory = positions } },
      true
    )
  end
  return moved
end

-- Cancel the robots' removal of a request depot's freighters; they go back into its slot at the
-- next dispatch. Returns how many were waiting to be taken.
-- Freighters a request depot has or will have: in its slot, out on trips, in its chest (except
-- those being taken away) and coming. Also the slot's limit and how many are coming.
local function freighter_total(entity)
  local in_slot, out, capacity = logistics.freighter_counts(entity)
  local _, coming, removing = freighter_requests(entity)
  local in_chest = count_freighters(inventory(entity)) - removing
  return in_slot + out + in_chest + coming, capacity, coming
end
logistics.freighter_total = freighter_total

-- Ask robots for as many freighters as it takes for a request depot to have `total` (within its
-- slot's limit). Returns how many were requested.
function logistics.match_freighters(entity, total)
  local depot = request_depot(entity)
  if not depot then
    return 0
  end
  total = math.max(0, math.floor(tonumber(total) or 0))
  local have = freighter_total(entity)
  if total > have then
    return logistics.request_freighters(entity, total - have)
  end
  -- Already as many or more: freighter requests beyond `total` are cancelled. Freighters already
  -- in the depot stay; they are the player's, and taking them away is the player's call.
  depot.freighter_target = total
  logistics.trim_freighter_requests(entity)
  return 0
end

-- Keep a request depot's freighter requests to what they are for (`depot.freighter_target`: the
-- total the depot should end up with), until it has them:
-- * beyond the target (freighters arrived some other way, put in by hand, say): the excess
--   requests are cancelled, so robots never bring more, nor overfill the slot;
-- * short of it with nothing requested to cover it: the shortfall is requested again. Factorio
--   drops an item request a player fills by hand even when they only put in part of it; the
--   target is what remembers the rest;
-- * once the depot has them all: the target is forgotten.
-- Without a target, requests are only kept within the slot's limit. Runs with every dispatch and
-- whenever freighters are put in by hand.
function logistics.trim_freighter_requests(entity)
  local depot = request_depot(entity)
  local total, capacity, coming = freighter_total(entity)
  local wanted = depot.freighter_target and math.min(depot.freighter_target, capacity)
  if not wanted then
    if coming > 0 and total > capacity then
      local keep = math.max(0, coming - (total - capacity))
      logistics.cancel_freighter_requests(entity)
      if keep > 0 then
        logistics.request_freighters(entity, keep)
      end
      depot.freighter_target = nil
    end
    return
  end
  if total - coming >= wanted then
    -- All there, without the requests: they are done.
    if coming > 0 then
      logistics.cancel_freighter_requests(entity)
    end
    depot.freighter_target = nil
  elseif total > wanted then
    -- More coming than still needed: cancel the excess (request_freighters sets the target
    -- again, to the same total).
    logistics.cancel_freighter_requests(entity)
    logistics.request_freighters(entity, coming - (total - wanted))
  elseif total < wanted then
    -- Short, with nothing requested to cover it: ask again for the rest.
    logistics.request_freighters(entity, wanted - total)
  end
end

-- Blueprints (and copy and paste) of request depots keep their request, as a tag, and their
-- freighters (in the slot, out and coming), as an insert plan into the chest: the ghost asks for
-- them, robots or a player bring them, and they move into the slot.
local REQUEST_TAG = "jatz_request"
local FREIGHTERS_TAG = "jatz_freighters"
logistics.request_tag = REQUEST_TAG

function logistics.setup_blueprint(blueprint, mapping)
  local entities = blueprint and mapping and blueprint.get_blueprint_entities()
  if not entities then
    return 0
  end
  local changed = 0
  for _, planned in pairs(entities) do
    local entity = mapping[planned.entity_number]
    local depot = entity and entity.valid and request_depot(entity)
    if depot then
      -- The depot's settings as they are now, replacing any from setting this blueprint up
      -- before; other tags and other items' insert plans are kept.
      planned.tags = planned.tags or {}
      planned.tags[REQUEST_TAG] = depot.request and { item = depot.request.item, count = depot.request.count } or nil
      local freighters = freighter_total(entity)
      planned.tags[FREIGHTERS_TAG] = freighters > 0 and freighters or nil
      if next(planned.tags) == nil then
        planned.tags = nil
      end
      local items, used = {}, {}
      for _, plan in pairs(planned.items or {}) do
        if item_name(plan.id.name) ~= FREIGHTER then
          items[#items + 1] = plan
          for _, position in pairs(plan.items.in_inventory or {}) do
            if position.inventory == defines.inventory.chest then
              used[position.stack] = true
            end
          end
        end
      end
      if freighters > 0 then
        -- Chest stacks the other plans don't use, a stack of freighters at a time.
        local stacks = {}
        for index = 0, #inventory(entity) - 1 do
          if not used[index] then
            stacks[#stacks + 1] = index
          end
        end
        local _, positions = spread(freighters, stacks)
        items[#items + 1] = { id = { name = FREIGHTER, quality = QUALITY }, items = { in_inventory = positions } }
      end
      planned.items = #items > 0 and items or nil
      changed = changed + 1
    end
  end
  if changed > 0 then
    blueprint.set_blueprint_entities(entities)
  end
  return changed
end

-- The blueprint being set up: a library record, the stack the event names, the one being set up,
-- or the cursor (copy and paste), whichever holds the blueprint's entities.
local function blueprint_of(candidate)
  if not (candidate and candidate.valid) then
    return nil
  end
  if candidate.object_name == "LuaItemStack" then
    if not (candidate.valid_for_read and candidate.is_blueprint) then
      return nil
    end
  elseif candidate.type ~= "blueprint" then
    return nil
  end
  local entities = candidate.get_blueprint_entities()
  return entities and #entities > 0 and candidate or nil
end

function logistics.on_player_setup_blueprint(event)
  local player = game.get_player(event.player_index)
  local mapping = event.mapping and event.mapping.valid and event.mapping.get()
  if not (player and mapping) then
    return
  end
  -- Any of these may be nil, so not ipairs (it stops at the first nil).
  local sources = { event.record, event.stack, player.blueprint_to_setup, player.cursor_stack }
  for index = 1, 4 do
    local blueprint = blueprint_of(sources[index])
    if blueprint then
      return logistics.setup_blueprint(blueprint, mapping)
    end
  end
end

-- A request depot built from a blueprint ghost takes its request from the ghost's tags (its
-- freighters arrive through the ghost's insert plan).
function logistics.apply_tags(entity, tags)
  local depot = tags and request_depot(entity)
  if not depot then
    return
  end
  -- Tags can come from anywhere (other mods, edited blueprint strings): use them only if well formed.
  local request = tags[REQUEST_TAG]
  if type(request) == "table" and type(request.item) == "string" and type(request.count) == "number" then
    logistics.set_request(entity, request.item, request.count)
  end
  -- The ghost's insert plan asks robots for the freighters; this is how many it is for.
  local freighters = tags[FREIGHTERS_TAG]
  if type(freighters) == "number" and freighters >= 0 then
    depot.freighter_target = math.floor(freighters)
  end
end

function logistics.cancel_freighter_removal(entity)
  if not request_depot(entity) then
    return 0
  end
  local proxies, _, removing = freighter_requests(entity)
  for _, proxy in ipairs(proxies) do
    local kept = {}
    for _, plan in pairs(proxy.removal_plan) do
      if item_name(plan.id.name) ~= FREIGHTER then
        kept[#kept + 1] = plan
      end
    end
    if #kept == 0 and #proxy.insert_plan == 0 then
      proxy.destroy()
    else
      proxy.removal_plan = kept
    end
  end
  return removing
end

-- Cancel a request depot's freighter requests (other requests on it stay). Returns how many.
function logistics.cancel_freighter_requests(entity)
  local depot = request_depot(entity)
  if not depot then
    return 0
  end
  depot.freighter_target = nil
  local proxies, requested = freighter_requests(entity)
  for _, proxy in ipairs(proxies) do
    local kept = {}
    for _, plan in pairs(proxy.insert_plan) do
      if item_name(plan.id.name) ~= FREIGHTER then
        kept[#kept + 1] = plan
      end
    end
    if #kept == 0 and #proxy.removal_plan == 0 then
      proxy.destroy()
    else
      proxy.insert_plan = kept
    end
  end
  return requested
end

-- Chest stacks (1-based) with freighters waiting for robots to take them away, and how many of
-- each stack's freighters are waiting: those stay; any more merged into the stack don't.
function logistics.leaving(entity)
  local _, _, _, marked = freighter_requests(entity)
  local leave = {}
  for stack, count in pairs(marked) do
    leave[stack + 1] = count
  end
  return leave
end

-- Freighters a player has just put into a request depot's chest (ctrl+click or shift+click in its
-- window, ctrl+click on the depot itself) go into its freighter slot at once, filling it; those
-- that don't fit go back to `give_back` (the player's inventory) rather than staying in the chest.
-- Only freighters the player just put in: at most `moved` (how many left their inventory), and no
-- more than the chest gained since it was last seen, so freighters already in the chest, put
-- there by an inserter, say, stay. Every other item put in stays in the chest, as in any
-- container. Not if freighters are what the depot requests: then they are cargo. Returns how many
-- went into the slot and how many went back.
function logistics.take_in_freighters(entity, give_back, moved)
  local depot = request_depot(entity)
  if not depot or (depot.request and depot.request.item == FREIGHTER) then
    return 0, 0
  end
  local chest = inventory(entity)
  local now = count_freighters(chest)
  local new = math.min(math.max(0, now - (depot.chest_seen or 0)), math.floor(tonumber(moved) or 0))
  if new <= 0 then
    depot.chest_seen = now
    return 0, 0
  end
  local slot = trucks_of(depot)
  local in_slot, out, capacity = logistics.freighter_counts(entity)
  local leave = logistics.leaving(entity)
  local taken = load(chest, slot, FREIGHTER, math.min(new, math.max(0, capacity - in_slot - out)), leave, true)
  local returned = 0
  if give_back then
    for index = 1, #chest do
      local stack = chest[index]
      local movable = stack.valid_for_read and stack.name == FREIGHTER and stack.count - (leave[index] or 0) or 0
      local amount = math.min(movable, new - taken - returned)
      if amount > 0 then
        local inserted
        if amount >= stack.count then
          inserted = give_back.insert(stack)
        else
          inserted = give_back.insert({ name = FREIGHTER, quality = stack.quality.name, count = amount })
        end
        returned = returned + inserted
        if inserted >= stack.count then
          stack.clear()
        elseif inserted > 0 then
          stack.count = stack.count - inserted
        end
      end
    end
  end
  depot.chest_seen = count_freighters(chest)
  if taken > 0 then
    logistics.trim_freighter_requests(entity)
  end
  return taken, returned
end

logistics.count_freighters = count_freighters

-- Put freighters from `stack` (a player's cursor, say) into a request depot's slot: `count` of
-- them, or all, as far as it has room counting those out on trips. Returns how many went in.
function logistics.put_freighters(entity, stack, count)
  local in_slot, out, capacity = logistics.freighter_counts(entity)
  if not in_slot or not stack.valid_for_read or stack.name ~= FREIGHTER then
    return 0
  end
  local amount = math.min(count or stack.count, stack.count, capacity - in_slot - out)
  if amount <= 0 then
    return 0
  end
  local slot, moved = trucks_of(request_depot(entity)), 0
  for index = 1, #slot do
    local into = slot[index]
    if moved >= amount or not stack.valid_for_read then
      break
    end
    if not into.valid_for_read or into.name == stack.name then
      local before = stack.count
      into.transfer_stack(stack, math.min(before, amount - moved))
      moved = moved + before - (stack.valid_for_read and stack.count or 0)
    end
  end
  -- Freighters put in by hand count towards what robots were asked for: cancel the rest now,
  -- before robots deliver it.
  if moved > 0 then
    logistics.trim_freighter_requests(entity)
  end
  return moved
end

-- Take freighters out of a request depot's slot: `count` of them (or all) into `stack` (a
-- player's cursor), or all into `into` (an inventory). Returns how many came out.
function logistics.take_freighters(entity, stack, count, into)
  local depot = request_depot(entity)
  if not depot then
    return 0
  end
  -- Taking freighters out on purpose: no longer top the depot up to an earlier target.
  depot.freighter_target = nil
  local slot = trucks_of(depot)
  local before = slot.get_item_count()
  local wanted = math.min(count or before, before)
  for index = 1, #slot do
    local from = slot[index]
    local taken = before - slot.get_item_count()
    if taken >= wanted then
      break
    end
    if from.valid_for_read then
      if into then
        local inserted = into.insert(from)
        if inserted >= from.count then
          from.clear()
        else
          from.count = from.count - inserted
        end
      else
        -- Into the cursor: as much as it takes, at most one stack.
        local had = stack.valid_for_read and stack.count or 0
        stack.transfer_stack(from, math.min(from.count, wanted - taken))
        if (stack.valid_for_read and stack.count or 0) == had then
          break
        end
      end
    end
  end
  return before - slot.get_item_count()
end

function logistics.init()
  init_storage()
  logistics.add_all()
end

function logistics.register()
  script.on_nth_tick(DISPATCH_INTERVAL, logistics.on_tick)
  script.on_event(defines.events.on_ai_command_completed, logistics.on_ai_command_completed)
  script.on_event(defines.events.on_script_path_request_finished, logistics.on_script_path_request_finished)
  remote.add_interface("jatz-distribution", {
    -- For other mods and the tests: read and write a request depot's request and status.
    set_request = logistics.set_request,
    get_request = logistics.get_request,
    get_status = logistics.get_status,
    -- Give a request depot new freighters, within its slot's limit (counting freighters out);
    -- returns how many it took. And read its freighter counts.
    add_freighters = function(entity, count)
      local depot = request_depot(entity)
      if not depot or type(count) ~= "number" then
        return 0
      end
      local in_slot, out, capacity = logistics.freighter_counts(entity)
      local amount = math.max(0, math.min(math.floor(count), capacity - in_slot - out))
      local added = amount > 0 and trucks_of(depot).insert({ name = FREIGHTER, count = amount }) or 0
      if added > 0 then
        logistics.trim_freighter_requests(entity)
      end
      return added
    end,
    freighter_counts = logistics.freighter_counts,
    -- Ask construction robots to bring freighters (as from remote view), and cancel that.
    request_freighters = logistics.request_freighters,
    requested_freighters = logistics.requested_freighters,
    cancel_freighter_requests = logistics.cancel_freighter_requests,
    remove_freighters = logistics.remove_freighters,
    match_freighters = logistics.match_freighters,
    take_in_freighters = logistics.take_in_freighters,
    setup_blueprint = logistics.setup_blueprint,
    cancel_freighter_removal = logistics.cancel_freighter_removal,
  })
end

return logistics
