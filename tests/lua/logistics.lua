-- SPDX-License-Identifier: LGPL-3.0-only
-- Deliveries in scripts/logistics.lua, against a small fake of the Factorio runtime: provider
-- searches, whose races depend on the order of engine callbacks within a tick, and request
-- depots' freighters (sending several one after another, returning, losing and handing them back),
-- which the headless check mod can't mine or click without a player.
-- Run from the repository root with Lua 5.2 (tools/test_mod_setup.py does): lua5.2 tests/lua/logistics.lua
package.path = "./?.lua;" .. package.path

defines = {
  direction = { north = 0, east = 4, south = 8, west = 12 },
  inventory = { chest = 1 },
  command = { go_to_location = 1, stop = 2 },
  distraction = { none = 0 },
  behavior_result = { in_progress = 0, fail = 1, success = 2, deleted = 3 },
  target_type = { entity = 1 },
}
prototypes = {
  entity = { ["jatz-freighter-drone"] = { collision_box = {}, collision_mask = {} } },
  item = { a = { stack_size = 50 }, b = { stack_size = 50 }, ["jatz-quinityn-freighter"] = { stack_size = 10 } },
}
script = { register_on_object_destroyed = function() end }

local function inventory(contents)
  local self = { contents = contents or {} }
  function self.get_item_count(id)
    return self.contents[type(id) == "table" and id.name or id] or 0
  end
  function self.get_insertable_count()
    return 1000
  end
  return self
end

local surface, requests, next_unit

-- An item stack and a script inventory, as far as the dispatcher uses them.
local function stack(name, count)
  local self = { name = name, count = count or 0, valid_for_read = (count or 0) > 0 }
  function self.clear()
    self.name, self.count, self.valid_for_read = nil, 0, false
  end
  function self.transfer_stack(from, amount)
    amount = math.min(amount or from.count, from.count)
    if self.valid_for_read and self.name ~= from.name then
      return false
    end
    self.name, self.count, self.valid_for_read = from.name, self.count + amount, true
    from.count = from.count - amount
    if from.count == 0 then
      from.clear()
    end
    return true
  end
  return self
end

local function script_inventory(size)
  local self = { valid = true }
  for index = 1, size do
    self[index] = stack()
  end
  function self.is_empty()
    return self.get_item_count() == 0
  end
  function self.get_item_count()
    local total = 0
    for index = 1, size do
      total = total + self[index].count
    end
    return total
  end
  function self.insert(from)
    for index = 1, size do
      local slot = self[index]
      if not slot.valid_for_read or slot.name == from.name then
        slot.name, slot.count, slot.valid_for_read = from.name, slot.count + from.count, true
        return from.count
      end
    end
    return 0
  end
  function self.destroy()
    self.valid = false
  end
  return self
end

local function entity(name, x, y, contents)
  next_unit = next_unit + 1
  local chest = inventory(contents)
  return {
    valid = true,
    name = name,
    unit_number = next_unit,
    position = { x = x, y = y },
    direction = defines.direction.north,
    surface = surface,
    surface_index = 1,
    force = "player",
    get_inventory = function()
      return chest
    end,
    chest = chest,
  }
end

local function reset()
  next_unit = 0
  requests = {}
  surface = { index = 1 }
  function surface.get_tile()
    return { valid = true, name = "jatz-road" }
  end
  function surface.request_path(parameters)
    requests[#requests + 1] = parameters
    return #requests
  end
  surface.spilled = {}
  function surface.spill_item_stack(parameters)
    surface.spilled[#surface.spilled + 1] = { name = parameters.stack.name, count = parameters.stack.count }
    return {}
  end
  function surface.create_entity(parameters)
    local drone = entity(parameters.name, parameters.position.x, parameters.position.y)
    drone.commands = {}
    drone.commandable = {
      set_command = function(command)
        drone.commands[#drone.commands + 1] = command
      end,
    }
    drone.force = "player"
    function drone.destroy()
      drone.valid = false
    end
    return drone
  end
  storage = {}
  function surface.find_entities_filtered()
    return {}
  end
  game = {
    tick = 0,
    surfaces = { surface },
    create_inventory = script_inventory,
  }
  package.loaded["scripts.logistics"] = nil
  local logistics = require("scripts.logistics")
  logistics.init()
  return logistics
end

-- Answer path request `id`: "route" (straight to the goal), "none" or "busy".
local function answer(logistics, id, result)
  logistics.on_script_path_request_finished({
    id = id,
    try_again_later = result == "busy",
    path = result == "route" and { { position = requests[id].goal } } or nil,
  })
end

-- The (first) trip of a request depot, and whether it has any.
local function trip_of(depot)
  return storage.trips[next(storage.depots[depot.unit_number].trips) or 0]
end

local function has_trip(depot)
  return next(storage.depots[depot.unit_number].trips) ~= nil
end

local function check(name, condition)
  if not condition then
    error("FAILED: " .. name, 2)
  end
  print("ok   " .. name)
end

-- A request depot for 10 of item a, and a provider holding 20.
local function setup(logistics)
  local request = entity("jatz-request-depot", 0.5, 0.5)
  local provider = entity("jatz-provider-depot", 10.5, 0.5, { a = 20 })
  logistics.add(request)
  logistics.add(provider)
  assert(logistics.set_request(request, "a", 10))
  assert(logistics.put_freighters(request, stack("jatz-quinityn-freighter", 5)) == 5)
  return request, provider
end

do -- A request changed while its search waits: the old search's answer changes nothing.
  local logistics = reset()
  local request, provider = setup(logistics)
  logistics.on_tick()
  check("a dispatch asks the pathfinder", #requests == 1)
  assert(logistics.set_request(request, "b", 5))
  answer(logistics, 1, "none")
  local depot = storage.depots[request.unit_number]
  check("a stale 'no route' puts no provider on cooldown", next(depot.cooldowns) == nil)
  check("a stale search sends no freighter and asks nothing more", next(depot.trips) == nil and #requests == 1)
  check("the provider is untouched", provider.chest.contents.a == 20)
end

do -- Roads change while a search waits: its answer is ignored, and a fresh search follows.
  local logistics = reset()
  local request = setup(logistics)
  logistics.on_tick()
  logistics.on_roads_changed(1, true, false)
  answer(logistics, 1, "none")
  local depot = storage.depots[request.unit_number]
  check("a search from before a road change puts no provider on cooldown", next(depot.cooldowns) == nil)
  game.tick = 60
  logistics.on_tick()
  check("the next dispatch searches again", #requests == 2)
  answer(logistics, 2, "route")
  check("and sends a freighter", next(depot.trips) ~= nil)
end

do -- A busy pathfinder is not asked again at once; the next dispatch asks again.
  local logistics = reset()
  local request = setup(logistics)
  logistics.on_tick()
  answer(logistics, 1, "busy")
  check("a busy answer does not resubmit immediately", #requests == 1)
  check("the depot is free to search again", storage.depots[request.unit_number].searching == nil)
  game.tick = 60
  logistics.on_tick()
  check("the next dispatch asks again", #requests == 2)
end

do -- A save from before searches existed has no search table: dispatching must still work.
  local logistics = reset()
  local request = setup(logistics)
  storage.searches = nil
  logistics.on_tick()
  answer(logistics, 1, "route")
  check("a save without a search table dispatches", has_trip(request))
end

-- A freighter on its way to `provider`, which is then removed while `spare` (farther) remains.
-- Requests: 1 = dispatch to `provider` (the spare is farther in a straight line than that road,
-- so it is never asked), 2 = the reroute search, which can only find the spare.
local function rerouting(logistics)
  local request, provider = setup(logistics)
  local spare = entity("jatz-provider-depot", 30.5, 0.5, { a = 20 })
  logistics.add(spare)
  logistics.on_tick()
  answer(logistics, 1, "route")
  check("only the nearest provider is asked when its road is short", #requests == 1)
  local trip = trip_of(request)
  check("the freighter heads for the provider nearest by road", trip.provider == provider.unit_number)
  provider.valid = false
  logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = provider.unit_number })
  check("a removed provider starts a reroute search", trip.searching ~= nil and #requests == 2)
  local stop = trip.drone.commands[#trip.drone.commands]
  check("the freighter waits while it runs", stop.type == defines.command.stop)
  return request, spare, trip
end

do -- The reroute finds the spare provider and the freighter drives there.
  local logistics = reset()
  local _, spare, trip = rerouting(logistics)
  answer(logistics, 2, "route")
  local drive = trip.drone.commands[#trip.drone.commands]
  check("the reroute picks the spare provider", trip.provider == spare.unit_number and not trip.searching)
  check("and the freighter drives on", drive.type == defines.command.go_to_location)
end

do -- A reroute search that never answers is started again, not given up with the freighter.
  local logistics = reset()
  local request, _, trip = rerouting(logistics)
  game.tick = 10 * 60
  logistics.on_tick()
  check("a timed-out reroute searches again", #requests == 3)
  check("the freighter is kept", trip.drone.valid and has_trip(request))
end

do -- The provider a reroute found is emptied before the answer arrives: look again, keep the truck.
  local logistics = reset()
  local request, spare, trip = rerouting(logistics)
  spare.chest.contents.a = 0
  local fourth = entity("jatz-provider-depot", 50.5, 0.5, { a = 20 })
  logistics.add(fourth)
  answer(logistics, 2, "route")
  check("an emptied pick starts another search", trip.drone.valid and trip.searching ~= nil and #requests == 3)
  check("among the providers that still qualify", requests[3].goal.x == 50.5)
  check("the request depot keeps its freighter", has_trip(request))
end

do -- A freighter waiting on a reroute stays put through road changes and stale completions.
  local logistics = reset()
  local _, _, trip = rerouting(logistics)
  local commands = #trip.drone.commands
  logistics.on_ai_command_completed({ unit_number = trip.drone.unit_number, result = defines.behavior_result.success })
  check("a stale arrival does not end a rerouting trip", trip.drone.valid and trip.searching ~= nil)
  logistics.on_roads_changed(1, false, true)
  local last = trip.drone.commands[#trip.drone.commands]
  check("a road change restarts the reroute and keeps the freighter stopped", last.type == defines.command.stop)
  check("with a fresh search", #trip.drone.commands > commands and #requests == 3)
  answer(logistics, 2, "none")
  check(
    "the replaced search's answer is ignored",
    trip.searching ~= nil and next(storage.depots[trip.request].cooldowns) == nil
  )
end

-- Freighters: a request for 100 of item a; a near provider holds 30, a far one 80.
local function supplied(logistics, trucks)
  local request = entity("jatz-request-depot", 0.5, 0.5)
  local near = entity("jatz-provider-depot", 10.5, 0.5, { a = 30 })
  local far = entity("jatz-provider-depot", 40.5, 0.5, { a = 80 })
  for _, depot in ipairs({ request, near, far }) do
    logistics.add(depot)
  end
  assert(logistics.set_request(request, "a", 100))
  if trucks > 0 then
    assert(logistics.put_freighters(request, stack("jatz-quinityn-freighter", trucks)) == trucks)
  end
  return request, near, far
end

local function trips_from(request)
  local list = {}
  for id in pairs(storage.depots[request.unit_number].trips) do
    list[#list + 1] = storage.trips[id]
  end
  table.sort(list, function(a, b)
    return a.drone.unit_number < b.drone.unit_number
  end)
  return list
end

do -- Several freighters, one after another, across providers.
  local logistics = reset()
  local request, near, far = supplied(logistics, 5)
  logistics.on_tick()
  check("one dispatch asks about one freighter's route", #requests == 1)
  answer(logistics, 1, "route")
  local trips = trips_from(request)
  check("the first freighter goes to the nearest provider", #trips == 1 and trips[1].provider == near.unit_number)
  check("promising all it has", trips[1].planned == 30)
  logistics.on_script_path_request_finished({ id = 999 }) -- nothing pending: no second freighter yet
  check("freighters don't leave all at once", #trips_from(request) == 1)
  game.tick = 60
  logistics.on_tick()
  answer(logistics, #requests, "route")
  trips = trips_from(request)
  check("the next dispatch sends a second freighter", #trips == 2)
  check("to the other provider, since the first one's stock is promised", trips[2].provider == far.unit_number)
  check("for the rest of the request", trips[2].planned == 70)
  check("with three freighters left in the slot", logistics.freighter_counts(request) == 3)
  game.tick = 120
  local before = #requests
  logistics.on_tick()
  check("nothing more is sent while those two cover the request", #requests == before)
end

do -- No freighters: nothing is sent, and the panel says why.
  local logistics = reset()
  local request = supplied(logistics, 0)
  logistics.on_tick()
  check("a depot without freighters sends none", #requests == 0)
  check("and says so", logistics.get_status(request) == "no-trucks")
end

do -- A freighter goes back into the slot after its trip; one destroyed on the way is lost.
  local logistics = reset()
  local request = supplied(logistics, 2)
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(request)[1]
  local success = defines.behavior_result.success
  logistics.on_ai_command_completed({ unit_number = trip.drone.unit_number, result = success }) -- at provider
  logistics.on_ai_command_completed({ unit_number = trip.drone.unit_number, result = success }) -- home
  check("a freighter back from its trip is in the slot again", logistics.freighter_counts(request) == 2)
  game.tick = 60
  logistics.on_tick()
  answer(logistics, #requests, "route")
  trip = trips_from(request)[1]
  logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = trip.drone.unit_number })
  local in_slot, out = logistics.freighter_counts(request)
  check("a freighter destroyed on the way is lost", in_slot == 1 and out == 0)
end

do -- The slot holds one stack, counting freighters out.
  local logistics = reset()
  local request = supplied(logistics, 8)
  logistics.on_tick()
  answer(logistics, 1, "route")
  local hand = stack("jatz-quinityn-freighter", 10)
  check(
    "a full slot (7 here, 1 out) takes only 2 more",
    logistics.put_freighters(request, hand) == 2 and hand.count == 8
  )
  check("other items are refused", logistics.put_freighters(request, stack("a", 5)) == 0)
  local taken = stack()
  check("taking half", logistics.take_freighters(request, taken, 5) == 5 and taken.count == 5)
end

do -- Mined: every freighter, in the slot and out, goes to whoever mined it.
  local logistics = reset()
  local request = supplied(logistics, 5)
  logistics.on_tick()
  answer(logistics, 1, "route")
  local buffer = script_inventory(4)
  logistics.on_depot_mined({ entity = request, buffer = buffer })
  request.valid = false
  logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = request.unit_number })
  check("mining a request depot hands over all its freighters", buffer.get_item_count() == 5)
  check("and drops none", #surface.spilled == 0)
  check("its freighter out leaves", next(storage.trips) == nil)
end

do -- Destroyed: its freighters are left on the ground where it stood.
  local logistics = reset()
  local request = supplied(logistics, 5)
  logistics.on_tick()
  answer(logistics, 1, "route")
  request.valid = false
  logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = request.unit_number })
  local dropped = 0
  for _, spilled in ipairs(surface.spilled) do
    dropped = dropped + (spilled.name == "jatz-quinityn-freighter" and spilled.count or 0)
  end
  check("a destroyed request depot leaves all its freighters on the ground", dropped == 5)
end

print("all logistics checks passed")
