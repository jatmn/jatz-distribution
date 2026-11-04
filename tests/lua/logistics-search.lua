-- SPDX-License-Identifier: LGPL-3.0-only
-- Provider searches in scripts/logistics.lua, against a small fake of the Factorio runtime, so
-- races that depend on the order of engine callbacks within a tick can be played out exactly.
-- Run from the repository root with Lua 5.2 (tools/test_mod_setup.py does): lua5.2 tests/lua/logistics-search.lua
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
  item = { a = { stack_size = 50 }, b = { stack_size = 50 } },
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
  function surface.create_entity(parameters)
    local drone = entity(parameters.name, parameters.position.x, parameters.position.y)
    drone.commands = {}
    drone.commandable = {
      set_command = function(command)
        drone.commands[#drone.commands + 1] = command
      end,
    }
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
    create_inventory = function()
      return {
        valid = true,
        is_empty = function()
          return true
        end,
        destroy = function() end,
      }
    end,
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

local function trip_of(depot)
  return storage.trips[storage.depots[depot.unit_number].trip]
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
  check("a stale search sends no freighter and asks nothing more", depot.trip == nil and #requests == 1)
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
  check("and sends a freighter", depot.trip ~= nil)
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
  check("a save without a search table dispatches", storage.depots[request.unit_number].trip ~= nil)
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
  check("the freighter is kept", trip.drone.valid and storage.depots[request.unit_number].trip ~= nil)
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
  check("the request depot keeps its freighter", storage.depots[request.unit_number].trip ~= nil)
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

print("all logistics search checks passed")
