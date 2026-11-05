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
  entity_status_diode = { green = 1, red = 2, yellow = 3 },
}
-- luacheck: globals settings
-- Runtime settings, as Factorio gives them: an unknown name fails, as `settings.global[name].value`
-- would on nil in game.
local SETTINGS = { ["jatz-freighter-fuel-capacity"] = 20, ["jatz-freighter-fuel-per-tile"] = 10 }
settings = {
  global = setmetatable({}, {
    __index = function(_, name)
      local value = SETTINGS[name]
      if value == nil then
        error("FAILED: no runtime-global setting " .. tostring(name), 2)
      end
      return { value = value }
    end,
  }),
}
-- Every item and fluid prototype has a fuel_value (0 if it doesn't burn), as in game.
prototypes = {
  entity = { ["jatz-freighter-drone"] = { collision_box = {}, collision_mask = {}, speed = 0.2 } },
  item = {
    a = { stack_size = 50, fuel_value = 0 },
    b = { stack_size = 50, fuel_value = 0 },
    ["jatz-quinityn-freighter"] = { stack_size = 10, fuel_value = 0 },
    coal = { name = "coal", stack_size = 50, fuel_value = 4000000 },
    ["used-cell"] = { name = "used-cell", stack_size = 50, fuel_value = 0 },
    -- Worth far more than a tank, as some mods' fuel items are (a 10 GJ item).
    megacell = { name = "megacell", stack_size = 10, fuel_value = 10000000000 },
  },
  fluid = { water = { fuel_value = 0 }, steam = { fuel_value = 0 }, diesel = { fuel_value = 1000000 } },
  -- prototypes/freighter-colors.lua's output: item b and steam have no color of their own.
  mod_data = {
    ["jatz-freighter-colors"] = {
      data = { items = { a = "jatz-freighter-drone-500" }, fluids = { water = "jatz-freighter-drone-013" } },
    },
  },
}
prototypes.item.cell =
  { name = "cell", stack_size = 50, fuel_value = 30000000, burnt_result = prototypes.item["used-cell"] }
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

-- Factorio 2.1's LuaRendering.draw_sprite parameters, and its entity info icon render layers.
local DRAW_SPRITE = {}
for _, key in ipairs({
  "blink_interval",
  "forces",
  "light_mode",
  "only_in_alt_mode",
  "orientation",
  "orientation_target",
  "oriented_offset",
  "players",
  "render_layer",
  "render_mode",
  "sprite",
  "surface",
  "tall",
  "target",
  "time_to_live",
  "tint",
  "use_target_orientation",
  "visible",
  "x_scale",
  "y_scale",
}) do
  DRAW_SPRITE[key] = true
end
local ENTITY_INFO_LAYERS =
  { ["entity-info-icon"] = true, ["entity-info-icon-above"] = true, ["air-entity-info-icon"] = true }

-- The alt-mode sprites drawn on a freighter, in drawing order.
local function sprites_on(drone)
  local sprites = {}
  for _, drawn in ipairs(surface.sprites) do
    if drawn.target == drone then
      assert(drawn.only_in_alt_mode, "a freighter's cargo icon shows outside alt mode")
      sprites[#sprites + 1] = drawn.sprite
    end
  end
  return table.concat(sprites, " ")
end

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

-- A liquid depot: a storage tank of 25,000 holding one fluid, as far as deliveries use it.
local function tank(name, x, y, fluid, amount, temperature)
  local self = entity(name, x, y)
  local held = { name = fluid, amount = amount or 0, temperature = temperature or 15 }
  self.held = held
  local function contents()
    return held.amount > 0 and held.name or nil
  end
  function self.get_fluid_count(name_)
    return contents() == name_ and held.amount or 0
  end
  function self.get_fluid_contents()
    return contents() and { [held.name] = held.amount } or {}
  end
  function self.get_fluid_capacity()
    return 25000
  end
  function self.clear_fluid_inside()
    held.amount = 0
  end
  function self.get_fluid(index)
    if index == 1 and contents() then
      return { name = held.name, amount = held.amount, temperature = held.temperature }
    end
  end
  function self.remove_fluid(index, wanted)
    if index ~= 1 or not contents() then
      return nil
    end
    local taken = math.min(wanted, held.amount)
    held.amount = held.amount - taken
    return { name = held.name, amount = taken, temperature = held.temperature }
  end
  function self.set_fluid(index, set)
    assert(index == 1, "a storage tank has one fluid storage")
    held.name, held.amount, held.temperature = set.name, math.min(set.amount, 25000), set.temperature or 15
    return held.amount
  end
  function self.insert_fluid(spec)
    if contents() and contents() ~= spec.name then
      return 0
    end
    local put = math.min(spec.amount, 25000 - held.amount)
    if put > 0 then
      held.temperature = (held.temperature * held.amount + spec.temperature * put) / (held.amount + put)
      held.name, held.amount = spec.name, held.amount + put
    end
    return put
  end
  return self
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
  surface.polluted = 0
  function surface.pollute(_, amount)
    surface.polluted = surface.polluted + amount
  end
  surface.created = {}
  function surface.create_entity(parameters)
    -- A Fuel depot's hidden tank is a storage tank; anything else is a freighter here.
    local make = parameters.name == "jatz-fuel-depot-tank" and tank or entity
    local drone = make(parameters.name, parameters.position.x, parameters.position.y)
    drone.target = parameters.target
    drone.parameters = parameters
    surface.created[#surface.created + 1] = drone
    drone.commands = {}
    drone.commandable = {
      set_command = function(command)
        drone.commands[#drone.commands + 1] = command
      end,
    }
    drone.force = parameters.force or "player"
    drone.health = 500
    function drone.destroy()
      drone.valid = false
    end
    return drone
  end
  -- Sprites drawn on entities (alt-mode cargo icons), strict to Factorio 2.1's draw_sprite: only
  -- its parameters, its entity info render layers, and sprites that exist.
  surface.sprites = {}
  rendering = {
    draw_sprite = function(parameters)
      for key in pairs(parameters) do
        assert(DRAW_SPRITE[key], "rendering.draw_sprite has no parameter " .. key)
      end
      local kind, name = parameters.sprite:match("^(%a+)/(.+)$")
      assert(
        parameters.sprite == "utility/entity_info_dark_background"
          or (kind == "item" or kind == "fluid") and prototypes[kind][name],
        "no sprite " .. parameters.sprite
      )
      assert(ENTITY_INFO_LAYERS[parameters.render_layer], "not an entity info layer: " .. parameters.render_layer)
      assert(parameters.target.valid and parameters.surface == parameters.target.surface, "drawn off its target")
      surface.sprites[#surface.sprites + 1] = parameters
    end,
  }
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

-- A freighter reaches where it was driving (`result`: success unless given). After a successful
-- arrival it stands at the loading zone for a moment: that ends too, and it loads or unloads.
local function arrive(logistics, trip, result)
  logistics.on_ai_command_completed({
    unit_number = trip.drone.unit_number,
    result = result or defines.behavior_result.success,
  })
  if trip.loading then
    logistics.on_ai_command_completed({ unit_number = trip.drone.unit_number, result = defines.behavior_result.success })
  end
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

do -- Even if dispatch runs early, a depot sends at most one freighter a second.
  local logistics = reset()
  local request = supplied(logistics, 5)
  logistics.on_tick()
  answer(logistics, 1, "route")
  game.tick = 30
  logistics.on_tick()
  check("no second freighter half a second after the first", #requests == 1 and #trips_from(request) == 1)
  game.tick = 60
  logistics.on_tick()
  check("one a second after", #requests == 2)
end

do -- A changed request lets go of what its outbound freighters promised.
  local logistics = reset()
  local first, near = supplied(logistics, 5)
  logistics.on_tick()
  answer(logistics, 1, "route")
  check("the first depot's freighter promises all 30 at the near provider", trips_from(first)[1].planned == 30)
  local second = entity("jatz-request-depot", 0.5, 10.5)
  logistics.add(second)
  assert(logistics.set_request(second, "a", 30))
  assert(logistics.put_freighters(second, stack("jatz-quinityn-freighter", 1)) == 1)
  assert(logistics.set_request(first, "b", 10))
  check("changing the request drops the old promise", trips_from(first)[1].planned == 0)
  game.tick = 60
  logistics.on_tick()
  answer(logistics, #requests, "route")
  local trip = trips_from(second)[1]
  check("so another depot can have that stock", trip and trip.provider == near.unit_number and trip.planned == 30)
end

do -- A rerouted freighter promises only what its new provider has unpromised.
  local logistics = reset()
  local request, near, far = supplied(logistics, 5)
  logistics.on_tick()
  answer(logistics, 1, "route")
  game.tick = 60
  logistics.on_tick()
  answer(logistics, 2, "route")
  local trips = trips_from(request)
  check("setup: 30 promised at the near provider, 70 at the far one", trips[1].planned == 30 and trips[2].planned == 70)
  near.valid = false
  logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = near.unit_number })
  answer(logistics, #requests, "route")
  check("rerouted to the far provider", trips[1].provider == far.unit_number)
  check("promising only the 10 not already promised there", trips[1].planned == 10)
end

do -- "On its way" means a freighter is bringing the item: not one driving home empty, nor one
  -- taking its cargo back to the provider.
  local logistics = reset()
  local request = supplied(logistics, 5)
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(request)[1]
  local fail = defines.behavior_result.fail
  arrive(logistics, trip) -- nothing to load
  check("an empty freighter shows no cargo icon", sprites_on(trip.drone) == "")
  game.tick = 60
  logistics.on_tick()
  check("a freighter driving home empty isn't 'on its way'", logistics.get_status(request) ~= "delivering")
  -- A loaded freighter whose way to the depot is cut takes its cargo back to the provider.
  local other = trips_from(request)[2] or trips_from(request)[1]
  other.state = "to-request"
  other.cargo[1].name, other.cargo[1].count, other.cargo[1].valid_for_read = "a", 10, true
  logistics.on_ai_command_completed({ unit_number = other.drone.unit_number, result = fail })
  check("setup: the loaded freighter heads back to the provider", other.state == "returning")
  game.tick = 120
  logistics.on_tick()
  check("nor is one taking its cargo back", logistics.get_status(request) ~= "delivering")
end

do -- No freighters: nothing is sent, and the panel says why.
  local logistics = reset()
  local request = supplied(logistics, 0)
  logistics.on_tick()
  check("a depot without freighters sends none", #requests == 0)
  check("and says so", logistics.get_status(request) == "no-trucks")
end

do -- A freighter goes back into the slot after its trip; one destroyed on the way is lost, and
  -- its depot asks robots for a replacement.
  local logistics = reset()
  local request = supplied(logistics, 2)
  -- A chest with stacks, for the replacement's request to go into.
  local chest = script_inventory(4)
  chest.get_insertable_count = request.chest.get_insertable_count
  request.get_inventory = function()
    return chest
  end
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(request)[1]
  arrive(logistics, trip) -- at provider
  arrive(logistics, trip) -- home
  check("a freighter back from its trip is in the slot again", logistics.freighter_counts(request) == 2)
  game.tick = 60
  logistics.on_tick()
  answer(logistics, #requests, "route")
  trip = trips_from(request)[1]
  check("no pollution while no freighter is out at a check", surface.polluted == 0)
  game.tick = 120
  logistics.on_tick()
  check("a freighter out pollutes a little", surface.polluted == 0.005)
  logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = trip.drone.unit_number })
  local in_slot, out = logistics.freighter_counts(request)
  check("a freighter destroyed on the way is lost", in_slot == 1 and out == 0)
  local proxy = surface.created[#surface.created]
  check(
    "and its depot asks robots for one freighter to replace it",
    proxy.name == "item-request-proxy"
      and proxy.parameters.target == request
      and proxy.parameters.modules[1].items.in_inventory[1].count == 1
      and storage.depots[request.unit_number].freighter_target == 2
  )
end

do -- A freighter lost while every stack of its depot's chest is taken: robots can't be asked yet,
  -- but the depot remembers it is short, and asks once a stack is free.
  local logistics = reset()
  local request = supplied(logistics, 2)
  local chest = script_inventory(2)
  chest.get_insertable_count = request.chest.get_insertable_count
  request.get_inventory = function()
    return chest
  end
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(request)[1]
  for index = 1, 2 do
    chest[index].name, chest[index].count, chest[index].valid_for_read = "b", 50, true
  end
  local created = #surface.created
  logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = trip.drone.unit_number })
  check("with a full chest, no replacement can be requested yet", #surface.created == created)
  check("but the depot remembers it had 2", storage.depots[request.unit_number].freighter_target == 2)
  chest[2].name, chest[2].count, chest[2].valid_for_read = nil, 0, false
  game.tick = 60
  logistics.on_tick()
  local proxy = surface.created[#surface.created]
  check(
    "once a stack is free, the next dispatch asks robots for the replacement",
    #surface.created == created + 1
      and proxy.name == "item-request-proxy"
      and proxy.parameters.modules[1].items.in_inventory[1].stack == 1
      and proxy.parameters.modules[1].items.in_inventory[1].count == 1
  )
end

do -- Freighters asked for while the chest has no free stack wait for one; asking for more adds
  -- to them, and once a stack is free they are all requested, once.
  local logistics = reset()
  local request = supplied(logistics, 0)
  local chest = script_inventory(2)
  chest.get_insertable_count = request.chest.get_insertable_count
  request.get_inventory = function()
    return chest
  end
  for index = 1, 2 do
    chest[index].name, chest[index].count, chest[index].valid_for_read = "b", 50, true
  end
  local depot = storage.depots[request.unit_number]
  local created = #surface.created
  check("with a full chest, nothing is requested yet", logistics.request_freighters(request, 5) == 0)
  check("but the 5 are remembered", depot.freighter_target == 5 and #surface.created == created)
  logistics.request_freighters(request, 1)
  check("one more adds to them", depot.freighter_target == 6)
  check("a match to what it is already waiting for adds nothing", logistics.match_freighters(request, 6) == 0)
  check("and keeps them", depot.freighter_target == 6)
  chest[2].name, chest[2].count, chest[2].valid_for_read = nil, 0, false
  game.tick = 60
  logistics.on_tick()
  local proxy = surface.created[#surface.created]
  check(
    "once a stack is free, all 6 are requested",
    #surface.created == created + 1
      and proxy.name == "item-request-proxy"
      and proxy.parameters.modules[1].items.in_inventory[1].count == 6
  )
  check("and the target isn't counted twice", depot.freighter_target == 6)
end

do -- Running enemies over: damage can set off other mods' handlers, which may remove an enemy
  -- further down the same search, or the freighter itself. Neither is read once gone.
  local logistics = reset()
  local request = supplied(logistics, 2)
  logistics.on_tick()
  answer(logistics, 1, "route")
  local drone = trips_from(request)[1].drone
  local box = prototypes.entity["jatz-freighter-drone"].collision_box
  box.left_top, box.right_bottom = { x = -0.4, y = -0.4 }, { x = 0.4, y = 0.4 }
  local player, enemy_force = { name = "player" }, { name = "enemy" }
  function player.is_enemy(other)
    return other == enemy_force
  end
  game.forces = { player = player, enemy = enemy_force }
  drone.force = player
  -- A LuaEntity: reading anything but `valid` from one that is gone is an error, as in the game.
  local function enemy(x)
    local fields = { valid = true, name = "small-biter", unit_number = 1000 + x, position = { x = x, y = 0.5 } }
    fields.hits = 0
    function fields.damage(amount, force, damage_type, source, cause)
      assert(amount == 200 and force == player and damage_type == "impact" and source == drone and cause == drone)
      fields.hits = fields.hits + 1
      if fields.on_damage then
        fields.on_damage()
      end
    end
    local self = setmetatable({}, {
      __index = function(_, key)
        if key ~= "valid" and not fields.valid then
          error("LuaEntity API call when LuaEntity was invalid")
        end
        return fields[key]
      end,
      __newindex = fields,
    })
    return self, fields
  end
  local first, first_fields = enemy(2)
  local second, second_fields = enemy(3)
  local third, third_fields = enemy(4)
  local fourth, fourth_fields = enemy(5)
  -- The first one's death removes its neighbor.
  first_fields.on_damage = function()
    second_fields.valid = false
  end
  local found, listed = {}, { first, second, third }
  function surface.find_entities_filtered(filter)
    if filter.type then
      found[#found + 1] = filter
      return listed
    end
    return {}
  end
  local start = drone.position
  logistics.on_impact_tick()
  check("a freighter that hasn't moved since the last look hits nothing", #found == 0)
  drone.position = { x = 5, y = start.y }
  local ok, err = pcall(logistics.on_impact_tick)
  check("an enemy removed by another's damage is skipped, not read", ok or print(err))
  check(
    "the others are hit, in the ground the freighter crossed, among its enemies",
    first_fields.hits == 1
      and second_fields.hits == 0
      and third_fields.hits == 1
      and found[1].force[1] == enemy_force
      and found[1].area[1][1] == math.min(start.x, 5) - 0.4
      and found[1].area[2][1] == math.max(start.x, 5) + 0.4
  )
  -- Within the second: the two hit aren't hit again. A fresh one's death removes the freighter,
  -- and nothing after it is hit.
  second_fields.valid = true
  second_fields.on_damage = function()
    drone.valid = false
  end
  listed = { first, second, third, fourth }
  drone.position = { x = 6, y = start.y }
  game.tick = 30
  ok, err = pcall(logistics.on_impact_tick)
  check("nothing is hit by a freighter that is gone", (ok or print(err)) and fourth_fields.hits == 0)
  check("hits within a second aren't repeated", first_fields.hits == 1 and third_fields.hits == 1)
end

do -- A freighter killed by enemies fails its command as it dies, at 0 health, before it is gone:
  -- it is lost, not taken back into the slot, and its provider isn't put on cooldown.
  local logistics = reset()
  local request = supplied(logistics, 2)
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(request)[1]
  trip.drone.health = 0
  logistics.on_ai_command_completed({ unit_number = trip.drone.unit_number, result = defines.behavior_result.fail })
  check("a dying freighter's failed command doesn't end its trip", logistics.freighter_counts(request) == 1)
  check("nor puts its provider on cooldown", next(storage.depots[request.unit_number].cooldowns) == nil)
  trip.drone.valid = false
  logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = trip.drone.unit_number })
  local in_slot, out = logistics.freighter_counts(request)
  check("once gone, it is lost", in_slot == 1 and out == 0)
end

do -- The slot holds 100 freighters, counting freighters out.
  local logistics = reset()
  local request = supplied(logistics, 98)
  logistics.on_tick()
  answer(logistics, 1, "route")
  local hand = stack("jatz-quinityn-freighter", 10)
  check(
    "a nearly full slot (97 here, 1 out) takes only 2 more",
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

-- Buffer depots: a request depot set to request from them takes from them first, however near a
-- provider is; one not set to takes from providers first and falls back to buffers only for what
-- no provider can supply; a buffer depot fetches only from providers.
local function buffered(logistics, from_buffers)
  local request = entity("jatz-request-depot", 0.5, 0.5)
  local provider = entity("jatz-provider-depot", 10.5, 0.5, { a = 30 })
  local buffer = entity("jatz-buffer-depot", 40.5, 0.5, { a = 30 })
  for _, depot in ipairs({ request, provider, buffer }) do
    logistics.add(depot)
  end
  assert(logistics.set_request(request, "a", 10))
  assert(logistics.set_from_buffers(request, from_buffers))
  assert(logistics.put_freighters(request, stack("jatz-quinityn-freighter", 2)) == 2)
  return request, provider, buffer
end

do -- Buffers first, nearer provider or not.
  local logistics = reset()
  local request, _, buffer = buffered(logistics, true)
  logistics.on_tick()
  check("the buffer depot is asked about first", requests[1].goal.x == 40.5)
  answer(logistics, 1, "route")
  check("with a road to it, the nearer provider isn't asked", #requests == 1)
  check("and the freighter goes to the buffer", trips_from(request)[1].provider == buffer.unit_number)
end

do -- A buffer with no road route: the provider instead.
  local logistics = reset()
  local request, provider = buffered(logistics, true)
  logistics.on_tick()
  answer(logistics, 1, "none")
  check("then the provider is asked", #requests == 2 and requests[2].goal.x == 10.5)
  answer(logistics, 2, "route")
  check("and the freighter goes there", trips_from(request)[1].provider == provider.unit_number)
end

do -- Not set to request from buffers: providers first, the buffer isn't asked while one has a road.
  local logistics = reset()
  local request, provider = buffered(logistics, false)
  logistics.on_tick()
  answer(logistics, 1, "route")
  check(
    "a request depot not set to use buffers fetches from the provider",
    trips_from(request)[1].provider == provider.unit_number
  )
  check("without asking about the buffer", #requests == 1)
end

do -- Not set to request from buffers, and no provider holds the item: the buffer after all.
  local logistics = reset()
  local request, provider, buffer = buffered(logistics, false)
  provider.chest.contents.a = nil
  logistics.on_tick()
  check("an empty provider isn't asked; the buffer is", #requests == 1 and requests[1].goal.x == 40.5)
  answer(logistics, 1, "route")
  check("and the freighter goes to the buffer", trips_from(request)[1].provider == buffer.unit_number)
end

do -- Not set to request from buffers, and the provider has no road route: the buffer instead.
  local logistics = reset()
  local request, _, buffer = buffered(logistics, false)
  logistics.on_tick()
  check("the provider is asked about first", requests[1].goal.x == 10.5)
  answer(logistics, 1, "none")
  check("then the buffer", #requests == 2 and requests[2].goal.x == 40.5)
  answer(logistics, 2, "route")
  check("and the freighter goes there", trips_from(request)[1].provider == buffer.unit_number)
end

do -- A buffer depot fetches only from providers, never from another buffer.
  local logistics = reset()
  local filling = entity("jatz-buffer-depot", 0.5, 0.5)
  local provider = entity("jatz-provider-depot", 40.5, 0.5, { a = 30 })
  local other = entity("jatz-buffer-depot", 10.5, 0.5, { a = 30 })
  for _, depot in ipairs({ filling, provider, other }) do
    logistics.add(depot)
  end
  assert(logistics.set_request(filling, "a", 10))
  check("buffer depots have no request-from-buffers setting", logistics.set_from_buffers(filling, true) == false)
  assert(logistics.put_freighters(filling, stack("jatz-quinityn-freighter", 2)) == 2)
  logistics.on_tick()
  check("a buffer depot asks only about providers", #requests == 1 and requests[1].goal.x == 40.5)
end

do -- Changing "request from buffer depots" restarts searches under way, freighters' included, and
  -- applies at once, without waiting out a retry delay.
  local logistics = reset()
  local request, _, trip = rerouting(logistics)
  local depot = storage.depots[request.unit_number]
  depot.retry_at = game.tick + 600
  assert(logistics.set_from_buffers(request, true))
  check("a retry delay doesn't hold the change back", depot.retry_at == 0)
  answer(logistics, 2, "route")
  check("the freighter's old reroute search is dropped", trip.searching ~= nil and trip.provider ~= nil)
  logistics.on_tick()
  check("and started afresh at the next check", #requests == 3)
end

-- Priority: within each kind of depot, the highest priority it can reach by road first, however
-- near a lower one is; buffer depots all still come before providers for a request depot that
-- requests from them, and after them for one that doesn't.
local function prioritised(logistics, from_buffers)
  local request = entity("jatz-request-depot", 0.5, 0.5)
  local near = entity("jatz-provider-depot", 10.5, 0.5, { a = 30 })
  local far = entity("jatz-provider-depot", 40.5, 0.5, { a = 30 })
  for _, depot in ipairs({ request, near, far }) do
    logistics.add(depot)
  end
  assert(logistics.set_request(request, "a", 10))
  assert(logistics.set_from_buffers(request, from_buffers or false))
  assert(logistics.put_freighters(request, stack("jatz-quinityn-freighter", 2)) == 2)
  return request, near, far
end

do -- Settings: provider and buffer depots only, 1 to 10, 5 until set.
  local logistics = reset()
  local request, near = prioritised(logistics)
  local buffer = entity("jatz-buffer-depot", 20.5, 0.5)
  logistics.add(buffer)
  check("a new provider depot has priority 5", logistics.get_priority(near) == 5)
  check("and so does a new buffer depot", logistics.get_priority(buffer) == 5)
  check("request depots have none", logistics.get_priority(request) == nil)
  check("and can't be given one", logistics.set_priority(request, 3) == false)
  check("a priority must be a number", logistics.set_priority(near, "high") == false)
  check("not text that reads as one", logistics.set_priority(near, "8") == false and logistics.get_priority(near) == 5)
  check("not NaN either", logistics.set_priority(near, 0 / 0) == false and logistics.get_priority(near) == 5)
  logistics.set_priority(near, 0)
  check("below 1 is 1", logistics.get_priority(near) == 1)
  logistics.set_priority(near, 42)
  check("above 10 is 10", logistics.get_priority(near) == 10)
  logistics.set_priority(buffer, 6.6)
  check("a fraction is rounded", logistics.get_priority(buffer) == 7)
end

do -- A farther provider with a higher priority wins over a nearer one.
  local logistics = reset()
  local request, _, far = prioritised(logistics)
  assert(logistics.set_priority(far, 8))
  logistics.on_tick()
  check("the higher priority provider is asked about first", requests[1].goal.x == 40.5)
  answer(logistics, 1, "route")
  check("with a road to it, the nearer one isn't asked", #requests == 1)
  check("and the freighter goes to it", trips_from(request)[1].provider == far.unit_number)
end

do -- The higher priority provider can't be reached by road: the lower one instead.
  local logistics = reset()
  local request, near, far = prioritised(logistics)
  assert(logistics.set_priority(far, 8))
  logistics.on_tick()
  answer(logistics, 1, "none")
  check("then the lower priority provider is asked", #requests == 2 and requests[2].goal.x == 10.5)
  answer(logistics, 2, "route")
  check("and the freighter goes there", trips_from(request)[1].provider == near.unit_number)
  check("the unreachable one is on cooldown", storage.depots[request.unit_number].cooldowns[far.unit_number])
end

do -- Equal priorities: nearest first, as before.
  local logistics = reset()
  local request, near, far = prioritised(logistics)
  assert(logistics.set_priority(near, 8) and logistics.set_priority(far, 8))
  logistics.on_tick()
  answer(logistics, 1, "route")
  check("equal priorities go to the nearest", trips_from(request)[1].provider == near.unit_number)
end

do -- Buffers: the higher priority first too; and any buffer before any provider.
  local logistics = reset()
  local request = prioritised(logistics, true)
  local near_buffer = entity("jatz-buffer-depot", 20.5, 0.5, { a = 30 })
  local far_buffer = entity("jatz-buffer-depot", 60.5, 0.5, { a = 30 })
  logistics.add(near_buffer)
  logistics.add(far_buffer)
  for _, provider in pairs(storage.depots) do
    if provider.role == "provider" then
      assert(logistics.set_priority(provider.entity, 10))
    end
  end
  assert(logistics.set_priority(near_buffer, 1) and logistics.set_priority(far_buffer, 2))
  logistics.on_tick()
  check("a priority 2 buffer comes before a nearer priority 1 one", requests[1].goal.x == 60.5)
  answer(logistics, 1, "none")
  check("then the priority 1 buffer, before priority 10 providers", requests[2].goal.x == 20.5)
  answer(logistics, 2, "route")
  check("and the freighter goes to it", trips_from(request)[1].provider == near_buffer.unit_number)
end

do -- A priority changed while a search waits: the search starts again with the new order.
  local logistics = reset()
  local request, _, far = prioritised(logistics)
  logistics.on_tick()
  check("first the nearer provider is asked about", requests[1].goal.x == 10.5)
  assert(logistics.set_priority(far, 9))
  answer(logistics, 1, "route")
  check("the old search's answer sends nobody", not has_trip(request))
  game.tick = game.tick + 60
  logistics.on_tick()
  check("the new search asks about the higher priority one", requests[2].goal.x == 40.5)
  answer(logistics, 2, "route")
  check("and the freighter goes there", trips_from(request)[1].provider == far.unit_number)
end

do -- Setting the priority it already has restarts nothing.
  local logistics = reset()
  local request, near = prioritised(logistics)
  logistics.on_tick()
  assert(logistics.set_priority(near, 5))
  answer(logistics, 1, "route")
  check("an unchanged priority leaves the search be", has_trip(request))
end

do -- Copy and paste, and clones, carry the priority between provider and buffer depots.
  local logistics = reset()
  local _, near, far = prioritised(logistics)
  local buffer = entity("jatz-buffer-depot", 20.5, 0.5)
  logistics.add(buffer)
  assert(logistics.set_priority(near, 9))
  logistics.on_entity_settings_pasted({ source = near, destination = far })
  check("pasting copies a provider's priority", logistics.get_priority(far) == 9)
  logistics.on_entity_settings_pasted({ source = near, destination = buffer })
  check("onto a buffer depot too", logistics.get_priority(buffer) == 9)
  local clone = entity("jatz-provider-depot", 80.5, 0.5)
  logistics.on_cloned(near, clone)
  check("a clone keeps it", logistics.get_priority(clone) == 9)
end

-- Liquid depots: the same deliveries, for fluids, 500 at a time, between liquid depots only.
local function liquids(logistics, wanted, trucks)
  local request = tank("jatz-liquid-request-depot", 0.5, 0.5)
  local provider = tank("jatz-liquid-provider-depot", 10.5, 0.5, "water", 1000, 60)
  logistics.add(request)
  logistics.add(provider)
  assert(logistics.set_request(request, "water", wanted or 800))
  assert(logistics.put_freighters(request, stack("jatz-quinityn-freighter", trucks or 3)) == (trucks or 3))
  return request, provider
end

do -- Requests: fluids for liquid depots, items for item depots.
  local logistics = reset()
  local request = tank("jatz-liquid-request-depot", 0.5, 0.5)
  local item_depot = entity("jatz-request-depot", 20.5, 0.5)
  logistics.add(request)
  logistics.add(item_depot)
  check("a liquid request depot takes a fluid", logistics.set_request(request, "water", 1000))
  check("not an item", logistics.set_request(request, "a", 10) == false)
  check("an item request depot takes no fluid", logistics.set_request(item_depot, "water", 10) == false)
  local chest = surface.created[1]
  check("a liquid request depot gets a truck chest", chest and chest.name == "jatz-truck-chest")
  check("under its centre", chest.position.x == 0.5 and chest.position.y == 0.5)
  local provider = tank("jatz-liquid-provider-depot", 10.5, 0.5)
  logistics.add(provider)
  check("a liquid provider needs none", #surface.created == 1)
  check(
    "liquid providers have a priority too",
    logistics.set_priority(provider, 7) and logistics.get_priority(provider) == 7
  )
end

do -- A fluid delivery: 500 per freighter, at the provider's temperature.
  local logistics = reset()
  local request, provider = liquids(logistics)
  logistics.on_tick()
  check("the liquid provider is asked about", #requests == 1 and requests[1].goal.x == 10.5)
  answer(logistics, 1, "route")
  local trip = trips_from(request)[1]
  check("a freighter promises 500, all it carries", trip and trip.planned == 500)
  check("with fluid cargo, not an item inventory", trip.fluid and not trip.cargo)
  arrive(logistics, trip)
  check("it pumps 500 out of the provider", provider.held.amount == 500 and trip.fluid.amount == 500)
  check("at the provider's temperature", trip.fluid.temperature == 60)
  check(
    "showing the fluid's icon in alt mode",
    sprites_on(trip.drone) == "utility/entity_info_dark_background fluid/water"
  )
  arrive(logistics, trip)
  check("and into the request depot's tank", request.held.name == "water" and request.held.amount == 500)
  check("hot", request.held.temperature == 60)
  check("then parks in the slot again", logistics.freighter_counts(request) == 3)
  game.tick = 60
  logistics.on_tick()
  answer(logistics, #requests, "route")
  check("the next freighter fetches the remaining 300", trips_from(request)[1].planned == 300)
end

do -- A freighter stands at each loading zone for a moment before it loads or unloads.
  local logistics = reset()
  local request, provider = liquids(logistics)
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(request)[1]
  local function reached()
    logistics.on_ai_command_completed({ unit_number = trip.drone.unit_number, result = defines.behavior_result.success })
  end
  local function last_command()
    return trip.drone.commands[#trip.drone.commands]
  end
  reached()
  local stop = last_command()
  check("at the provider it stops for one second", stop.type == defines.command.stop and stop.ticks_to_wait == 60)
  check("before pumping anything", provider.held.amount == 1000 and trip.fluid.amount == 0)
  logistics.on_roads_changed(1, false, true)
  check("a road change doesn't cut its stop short", last_command() == stop)
  reached()
  check("then it loads", provider.held.amount == 500 and trip.fluid.amount == 500)
  check("and drives home", last_command().type == defines.command.go_to_location)
  reached()
  stop = last_command()
  check("at home it stops again", stop.type == defines.command.stop and stop.ticks_to_wait == 60)
  check("before unloading", request.held.amount == 0 and trip.fluid.amount == 500)
  reached()
  check("then it unloads", request.held.amount == 500)
  check("and parks", logistics.freighter_counts(request) == 3 and not storage.trips[trip.drone.unit_number])
end

do -- One coming home empty parks at once; one unloading at a removed depot takes its cargo back.
  local logistics = reset()
  local request, provider = liquids(logistics)
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(request)[1]
  provider.held.amount = 0
  arrive(logistics, trip)
  check("setup: nothing to load", trip.fluid.amount == 0)
  logistics.on_ai_command_completed({ unit_number = trip.drone.unit_number, result = defines.behavior_result.success })
  check("an empty freighter parks without stopping", not storage.trips[trip.drone.unit_number])
  provider.held.amount = 1000
  game.tick = 60
  logistics.on_tick()
  answer(logistics, #requests, "route")
  trip = trips_from(request)[1]
  arrive(logistics, trip)
  logistics.on_ai_command_completed({ unit_number = trip.drone.unit_number, result = defines.behavior_result.success })
  check("setup: stopped at home to unload", trip.loading and trip.fluid.amount == 500)
  request.valid = false
  logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = request.unit_number })
  local drive = trip.drone.commands[#trip.drone.commands]
  check("a removed request depot sends it back at once", trip.state == "returning" and not trip.loading)
  check("driving", drive.type == defines.command.go_to_location and drive.destination.x == 10.5)
  arrive(logistics, trip)
  check("and the fluid goes back into the provider", provider.held.amount == 1000)
end

do -- A large request: several freighters, one a second, each promising what it can carry.
  local logistics = reset()
  local request = liquids(logistics, 900)
  logistics.on_tick()
  answer(logistics, 1, "route")
  game.tick = 60
  logistics.on_tick()
  answer(logistics, 2, "route")
  local trips = trips_from(request)
  check("two freighters for 900", #trips == 2 and trips[1].planned == 500 and trips[2].planned == 400)
end

do -- Items and fluids never meet.
  local logistics = reset()
  local request = tank("jatz-liquid-request-depot", 0.5, 0.5)
  local item_provider = entity("jatz-provider-depot", 10.5, 0.5, { water = 100 })
  logistics.add(request)
  logistics.add(item_provider)
  assert(logistics.set_request(request, "water", 100))
  assert(logistics.put_freighters(request, stack("jatz-quinityn-freighter", 1)) == 1)
  logistics.on_tick()
  check("a liquid request depot never asks an item provider", #requests == 0)
  check("and says no provider has it", logistics.get_status(request) == "no-provider")
  assert(logistics.set_request(request, nil)) -- only the item request depot asks from here on
  local item_request = entity("jatz-request-depot", 0.5, 20.5)
  local liquid_provider = tank("jatz-liquid-provider-depot", 10.5, 20.5, "water", 1000)
  liquid_provider.get_fluid_count = function()
    return 1000 -- even one that claims to hold anything
  end
  local real = entity("jatz-provider-depot", 40.5, 20.5, { a = 20 })
  for _, depot in ipairs({ item_request, liquid_provider, real }) do
    logistics.add(depot)
  end
  assert(logistics.set_request(item_request, "a", 10))
  assert(logistics.put_freighters(item_request, stack("jatz-quinityn-freighter", 1)) == 1)
  local before = #requests
  logistics.on_tick()
  check(
    "an item request depot asks only item providers",
    #requests == before + 1 and requests[#requests].goal.x == 40.5
  )
  local copy = tank("jatz-liquid-request-depot", 60.5, 0.5)
  logistics.add(copy)
  logistics.on_entity_settings_pasted({ source = item_request, destination = copy })
  check("pasting from an item depot onto a liquid depot copies nothing", logistics.get_request(copy) == nil)
end

do -- Liquid buffer depots, and liquid request depots set to request from them.
  local logistics = reset()
  local request = tank("jatz-liquid-request-depot", 0.5, 0.5)
  local provider = tank("jatz-liquid-provider-depot", 10.5, 0.5, "water", 1000)
  local buffer = tank("jatz-liquid-buffer-depot", 40.5, 0.5, "water", 1000)
  local item_buffer = entity("jatz-buffer-depot", 20.5, 0.5, { water = 100 })
  for _, depot in ipairs({ request, provider, buffer, item_buffer }) do
    logistics.add(depot)
  end
  assert(logistics.set_request(request, "water", 300))
  check("liquid request depots can request from buffers", logistics.set_from_buffers(request, true))
  check("liquid buffer depots can't", logistics.set_from_buffers(buffer, true) == false)
  assert(logistics.put_freighters(request, stack("jatz-quinityn-freighter", 1)) == 1)
  logistics.on_tick()
  check("the liquid buffer comes first, nearer provider or not", requests[1].goal.x == 40.5)
  answer(logistics, 1, "route")
  check("and the freighter goes there", trips_from(request)[1].provider == buffer.unit_number)
  assert(logistics.set_request(buffer, "water", 2000))
  assert(logistics.put_freighters(buffer, stack("jatz-quinityn-freighter", 1)) == 1)
  game.tick = 60
  local before = #requests
  logistics.on_tick()
  check(
    "a liquid buffer fetches from the liquid provider only",
    #requests == before + 1 and requests[#requests].goal.x == 10.5
  )
end

do -- A liquid request depot not set to request from buffers, with every liquid provider empty:
  -- the liquid buffer holding the fluid.
  local logistics = reset()
  local request = tank("jatz-liquid-request-depot", 0.5, 0.5)
  local provider = tank("jatz-liquid-provider-depot", 10.5, 0.5, "water", 0)
  local buffer = tank("jatz-liquid-buffer-depot", 40.5, 0.5, "water", 1000)
  for _, depot in ipairs({ request, provider, buffer }) do
    logistics.add(depot)
  end
  assert(logistics.set_request(request, "water", 300))
  assert(logistics.put_freighters(request, stack("jatz-quinityn-freighter", 1)) == 1)
  logistics.on_tick()
  check("the liquid buffer is asked about", #requests == 1 and requests[1].goal.x == 40.5)
  answer(logistics, 1, "route")
  check("and the freighter goes to it", trips_from(request)[1].provider == buffer.unit_number)
end

do -- The tank holds another fluid: nothing is fetched until it is emptied.
  local logistics = reset()
  local request = liquids(logistics)
  request.held.name, request.held.amount = "steam", 100
  logistics.on_tick()
  check("no freighter goes out", #requests == 0)
  check("and the panel says why", logistics.get_status(request) == "other-fluid")
end

do -- Fluid that no longer fits goes back to the provider; a lost way back brings it back too.
  local logistics = reset()
  local request, provider = liquids(logistics)
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(request)[1]
  arrive(logistics, trip)
  request.held.name, request.held.amount = "steam", 100 -- another fluid got in meanwhile
  arrive(logistics, trip)
  check("what doesn't fit heads back to the provider", trip.state == "returning" and trip.fluid.amount == 500)
  arrive(logistics, trip)
  check("and goes back into its tank", provider.held.amount == 1000 and not storage.trips[trip.drone.unit_number])
  check("the freighter parks again", logistics.freighter_counts(request) == 3)
  request.held.amount = 0
  game.tick = 600
  logistics.on_tick()
  answer(logistics, #requests, "route")
  trip = trips_from(request)[1]
  arrive(logistics, trip)
  arrive(logistics, trip, defines.behavior_result.fail)
  check("a loaded freighter whose way is lost brings the fluid back", trip.state == "returning")
  arrive(logistics, trip)
  check("into the provider", provider.held.amount == 1000)
end

do -- A liquid request depot mined: its freighters go to the miner, its truck chest goes.
  local logistics = reset()
  local request = liquids(logistics)
  local chest = surface.created[1]
  local buffer = script_inventory(4)
  logistics.on_depot_mined({ entity = request, buffer = buffer })
  check("mining a liquid request depot hands over its freighters", buffer.get_item_count() == 3)
  request.valid = false
  logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = request.unit_number })
  check("and its truck chest is removed", chest.valid == false)
end

-- Give a depot a chest of real stacks (the fake chests only count), holding `count` of `name`.
local function stocked(depot, name, count)
  local chest = script_inventory(4)
  if count then
    chest[1] = stack(name, count)
    chest[1].quality = { name = "normal" }
  end
  function chest.get_item_count(id)
    local wanted = type(id) == "table" and id.name or id
    local total = 0
    for index = 1, 4 do
      if chest[index].valid_for_read and chest[index].name == wanted then
        total = total + chest[index].count
      end
    end
    return total
  end
  function chest.get_insertable_count()
    return 1000
  end
  depot.get_inventory = function()
    return chest
  end
  return chest
end

do -- The cargo paint: grey out, the load's color from the provider home, the same trip throughout.
  local logistics = reset()
  local request, provider = setup(logistics)
  local stock, home = stocked(provider, "a", 20), stocked(request)
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trip_of(request)
  local empty = trip.drone
  check("a freighter sets off in the empty paint", empty.name == "jatz-freighter-drone")
  -- Crawling, as a dry freighter does.
  empty.orientation, empty.health, empty.speed = 0.25, 321, 0.02
  arrive(logistics, trip)
  local painted = trip.drone
  check(
    "loading paints it for its item",
    painted.name == "jatz-freighter-drone-500" and stock.get_item_count("a") == 10
  )
  check("as a new freighter in place of the old one", painted ~= empty and not empty.valid and painted.valid)
  check("showing its cargo's icon in alt mode", sprites_on(painted) == "utility/entity_info_dark_background item/a")
  check(
    "where it stood, facing the same way, as damaged, as fast",
    painted.position.x == empty.position.x
      and painted.position.y == empty.position.y
      and painted.orientation == 0.25
      and painted.health == 321
      and painted.speed == 0.02
  )
  check(
    "the trip moves to the new freighter",
    storage.trips[painted.unit_number] == trip
      and not storage.trips[empty.unit_number]
      and trip_of(request) == trip
      and not storage.depots[request.unit_number].trips[empty.unit_number]
  )
  local drive = painted.commands[#painted.commands]
  check("and drives home", drive and drive.type == defines.command.go_to_location and drive.destination.x == 0.5)
  logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = empty.unit_number })
  check("the old freighter's removal ends nothing", storage.trips[painted.unit_number] == trip)
  check("one freighter is still out", logistics.freighter_counts(request) == 4)
  arrive(logistics, trip)
  check("it unloads and parks as usual", home.get_item_count("a") == 10 and logistics.freighter_counts(request) == 5)
  check("leaving no freighter behind", not painted.valid and next(storage.trips) == nil)
end

do -- Something stuck to it (fire, acid) stays stuck: it keeps its paint until that wears off.
  local logistics = reset()
  local request, provider = setup(logistics)
  stocked(provider, "a", 20)
  local home = stocked(request)
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trip_of(request)
  local drone = trip.drone
  local fire = { valid = true, name = "fire-sticker" }
  drone.stickers = { fire }
  arrive(logistics, trip)
  local drive = drone.commands[#drone.commands]
  check("a freighter with a sticker loads", trip.cargo.get_item_count("a") == 10)
  check(
    "but is not swapped for a painted one",
    trip.drone == drone and drone.valid and drone.name == "jatz-freighter-drone"
  )
  check("and drives home", drive.type == defines.command.go_to_location and drive.destination.x == 0.5)
  check("showing its cargo's icon meanwhile", sprites_on(drone) == "utility/entity_info_dark_background item/a")
  game.tick = 60
  logistics.on_tick()
  check("still not while the sticker lasts", trip.drone == drone and drone.valid and drone.stickers[1] == fire)
  drone.stickers = {}
  game.tick = 120
  logistics.on_tick()
  local painted = trip.drone
  check("once it wears off, the next check paints it", painted ~= drone and painted.name == "jatz-freighter-drone-500")
  check("in place of the old one", not drone.valid and storage.trips[painted.unit_number] == trip)
  check("which shows the icon now", sprites_on(painted) == "utility/entity_info_dark_background item/a")
  drive = painted.commands[#painted.commands]
  check("which drives on home", drive and drive.type == defines.command.go_to_location and drive.destination.x == 0.5)
  game.tick = 180
  logistics.on_tick()
  check("and is left alone after", trip.drone == painted and #painted.commands == 1)
  arrive(logistics, trip)
  check("it unloads and parks", home.get_item_count("a") == 10 and next(storage.trips) == nil)
end

do -- A freighter standing to load or unload is never painted from on_tick.
  local logistics = reset()
  local request, provider = setup(logistics)
  stocked(provider, "a", 20)
  stocked(request)
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trip_of(request)
  local drone = trip.drone
  drone.stickers = { { valid = true, name = "fire-sticker" } }
  arrive(logistics, trip)
  drone.stickers = nil
  logistics.on_ai_command_completed({ unit_number = drone.unit_number, result = defines.behavior_result.success })
  check("setup: it stands at home to unload", trip.loading and trip.drone == drone)
  game.tick = 60
  logistics.on_tick()
  check("on_tick leaves it standing", trip.drone == drone and drone.valid and trip.loading)
end

do -- Nothing to load keeps the empty paint; an item with no color of its own gets the artwork's.
  local logistics = reset()
  local request, provider = setup(logistics)
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trip_of(request)
  local empty = trip.drone
  stocked(request)
  local stock = stocked(provider)
  arrive(logistics, trip)
  check("a freighter with nothing to load stays as it is", trip.drone == empty and empty.valid)
  arrive(logistics, trip)
  stock[1] = stack("b", 20)
  stock[1].quality = { name = "normal" }
  assert(logistics.set_request(request, "b", 10))
  game.tick = 60
  logistics.on_tick()
  answer(logistics, #requests, "route")
  trip = trip_of(request)
  arrive(logistics, trip)
  check("an item with no color gets the artwork's paint", trip.drone.name == "jatz-freighter-drone-loaded")
end

do -- Fluids get their color, and keep it while what didn't fit goes back.
  local logistics = reset()
  local request, provider = liquids(logistics)
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(request)[1]
  check("a liquid freighter sets off empty too", trip.drone.name == "jatz-freighter-drone")
  arrive(logistics, trip)
  check("loading water paints it the water's color", trip.drone.name == "jatz-freighter-drone-013")
  request.held.name, request.held.amount = "steam", 100
  arrive(logistics, trip)
  check("cargo going back keeps its paint", trip.state == "returning" and trip.drone.name == "jatz-freighter-drone-013")
  arrive(logistics, trip)
  check("and it parks once the fluid is back", provider.held.amount == 1000 and next(storage.trips) == nil)
end

do -- Without a Mining Drones mod there is no mining depot: an entity of that name is no depot.
  local logistics = reset()
  logistics.add(entity("mining-depot", 20.5, 0))
  check("no mining depot without Mining Drones", next(storage.depots) == nil)
end

do -- With Mining Drones, a mining depot is an item provider of what collects in its output.
  prototypes.entity["mining-depot"] = {}
  package.loaded["scripts.loading-zone"] = nil
  local logistics = reset()
  local loading_zone = require("scripts.loading-zone")
  local request = entity("jatz-request-depot", 0.5, 0.5)
  local mine = entity("mining-depot", 20.5, 0)
  -- An assembling machine: no chest, its ore in the output inventory.
  local output = stocked(mine, "a", 30)
  mine.get_inventory = function()
    return nil
  end
  function mine.get_output_inventory()
    return output
  end
  local home = stocked(request)
  logistics.add(request)
  logistics.add(mine)
  assert(logistics.set_request(request, "a", 10))
  assert(logistics.put_freighters(request, stack("jatz-quinityn-freighter", 5)) == 5)
  check("a mining depot is a provider depot, priority 5", logistics.get_priority(mine) == 5)
  local zones = {}
  for _, direction in ipairs({ "north", "east", "south", "west" }) do
    mine.direction = defines.direction[direction]
    local x, y = loading_zone.tile_centre(mine)
    zones[#zones + 1] = (x - 20.5) .. "," .. y
  end
  mine.direction = defines.direction.north
  check(
    "its loading zone is the tile behind it, turning with it",
    table.concat(zones, " ") == "0,4.5 -4.5,0 0,-4.5 4.5,0"
  )
  logistics.on_tick()
  check("the search asks for a road to it", #requests == 1 and requests[1].goal.x == 20.5 and requests[1].goal.y == 4.5)
  answer(logistics, 1, "route")
  local trip = trip_of(request)
  check("a freighter drives to its loading zone", trip and trip.destination.x == 20.5 and trip.destination.y == 4.5)
  arrive(logistics, trip)
  check("and loads from its output", output.get_item_count("a") == 20 and trip.state == "to-request")
  arrive(logistics, trip)
  check("which it delivers", home.get_item_count("a") == 10 and next(storage.trips) == nil)
  prototypes.entity["mining-depot"] = nil
  package.loaded["scripts.loading-zone"] = nil
end

-- Fuel. A Fuel depot: a chest of item stacks (with quality, as fuel is taken from them) and the
-- hidden tank logistics.add makes under it.
local function fuel_depot(logistics, x, y, items, fluid, amount)
  local self = entity("jatz-fuel-depot", x, y)
  local chest = script_inventory(4)
  for index, item in ipairs(items or {}) do
    chest[index] = stack(item[1], item[2])
  end
  for index = 1, #chest do
    local slot = chest[index]
    slot.quality = { name = "normal" }
    local clear = slot.clear
    function slot.clear()
      clear()
      slot.quality = { name = "normal" }
    end
  end
  function chest.get_contents()
    local list = {}
    for index = 1, #chest do
      if chest[index].valid_for_read then
        list[#list + 1] = { name = chest[index].name, quality = "normal", count = chest[index].count }
      end
    end
    return list
  end
  function chest.count(name)
    local total = 0
    for index = 1, #chest do
      if chest[index].valid_for_read and chest[index].name == name then
        total = total + chest[index].count
      end
    end
    return total
  end
  -- Room for burnt results: as much as asked unless a check sets `room`.
  function chest.get_insertable_count()
    return chest.room or 1000
  end
  local insert = chest.insert
  function chest.insert(spec)
    return insert({ name = spec.name, count = spec.count })
  end
  self.get_inventory = function()
    return chest
  end
  self.chest = chest
  logistics.add(self)
  local tank_ = storage.depots[self.unit_number].tank
  if fluid then
    tank_.held.name, tank_.held.amount = fluid, amount
  end
  return self, tank_
end

local MJ = 1000000

-- The request depot and provider of `setup`, ten tiles apart, its freighters at `energy` joules,
-- and the fuel depot made by `make`. The dispatch's search finds the provider by road.
local function fuelled(logistics, energy, make)
  local request, provider = setup(logistics)
  local fuel, tank_ = make and make() or nil, nil
  if type(fuel) == "table" and fuel[1] then
    fuel, tank_ = fuel[1], fuel[2]
  end
  check("setting parked fuel covers the slot", logistics.set_freighter_fuel(request, energy) == 5)
  logistics.on_tick()
  answer(logistics, 1, "route")
  return request, provider, fuel, tank_
end

do -- Fuel burns by the tile driven; a freighter with enough for the leg sets straight off.
  local logistics = reset()
  local request, provider = fuelled(logistics, 20 * MJ)
  local trip = trips_from(request)[1]
  check("a freighter with fuel for the leg drives to the provider", trip.destination.x == provider.position.x)
  trip.drone.position = { x = trip.drone.position.x + 100, y = trip.drone.position.y }
  game.tick = 60
  logistics.on_tick()
  check("driving 100 tiles burns 1 MJ at 10 kJ a tile", math.abs(trip.energy - 19 * MJ) < 1)
  arrive(logistics, trip)
  arrive(logistics, trip)
  check("it parks with what it has left", logistics.freighter_fuel(request).home[5] == trip.energy)
  local fuel = logistics.freighter_fuel(request)
  check("new freighters have a full tank", fuel.home[1] == fuel.capacity and fuel.capacity == 20 * MJ)
end

do -- Short of fuel for the leg: to the Fuel depot nearest by road first, fill up, then on.
  local logistics = reset()
  local near, far
  local request, provider = fuelled(logistics, 0.5 * MJ, function()
    far = fuel_depot(logistics, -40.5, 0.5, { { "coal", 20 } })
    near = fuel_depot(logistics, -10.5, 0.5, { { "coal", 20 } })
    return near
  end)
  local trip = trips_from(request)[1]
  check("a freighter short of fuel stands while it looks for a Fuel depot", trip.searching and trip.fuel_search)
  check("asking the pathfinder for the nearest first", requests[2].goal.x == near.position.x)
  answer(logistics, 2, "route")
  check("the farther one isn't asked once a nearer has a road", #requests == 2)
  check("it heads for the nearest", trip.refuel == near.unit_number and trip.destination.x == near.position.x)
  arrive(logistics, trip)
  check("fills up there, a whole coal at a time", near.chest.count("coal") == 15 and trip.energy == 20.5 * MJ)
  check("the other Fuel depot is untouched", far.chest.count("coal") == 20)
  check("then goes on to the provider", not trip.refuel and trip.destination.x == provider.position.x)
  check("having promised its load all along", trip.planned == 10)
  arrive(logistics, trip)
  check("it loads there", trip.state == "to-request" and trip.destination.x == request.position.x)
end

do -- Liquid fuel first, then items; an item that burns into another leaves that in the depot.
  local logistics = reset()
  local fuel, tank_
  local request = fuelled(logistics, 0, function()
    fuel, tank_ = fuel_depot(logistics, -10.5, 0.5, { { "cell", 3 } }, "diesel", 5)
    return { fuel, tank_ }
  end)
  local trip = trips_from(request)[1]
  check("a dry freighter crawls", trip.dry and trip.drone.speed == 0.2 * 0.1)
  answer(logistics, 2, "route")
  arrive(logistics, trip)
  check("all the burnable fluid goes first", tank_.held.amount == 0)
  check("then one fuel cell tops it up past full", fuel.chest.count("cell") == 2 and trip.energy == 35 * MJ)
  check("leaving its used cell in the depot", fuel.chest.count("used-cell") == 1)
  check("filled up, it drives at full speed again", not trip.dry and trip.drone.speed == 0.2)
end

do -- Nothing to fill up with: a fluid that doesn't burn, a chest of things that don't.
  local logistics = reset()
  local fuel = fuel_depot(logistics, -10.5, 0.5, { { "a", 20 } }, "water", 500)
  local request = fuelled(logistics, 0)
  check("a freighter at home asks for a road to the empty Fuel depot too", requests[2].goal.x == -10.5)
  answer(logistics, 2, "route")
  check("but is never sent to wait there: it stays home", not has_trip(request))
  check("its depot says the Fuel depots have no fuel", logistics.get_status(request) == "no-fuel")
  check("the freighter is back in the slot", logistics.freighter_counts(request) == 5)
  game.tick = 60
  logistics.on_tick()
  check("and the depot waits for fuel", #requests == 2 and logistics.get_status(request) == "no-fuel")
  check("a flushed tank is empty", logistics.flush_fuel(fuel) and logistics.fuel_contents(fuel).amount == 0)
  local contents = logistics.fuel_contents(fuel)
  check("the panel reads the tank", contents.capacity == 25000 and contents.burnable == false)
  fuel.chest.insert({ name = "coal", count = 5 })
  game.tick = 120
  logistics.on_tick()
  check("once the Fuel depot has fuel, it looks again at once, not after the wait", #requests == 3)
  answer(logistics, 3, "route")
  local trip = trips_from(request)[1]
  check("and the freighter sets off to fill up there", trip and trip.fuel_search and requests[4].goal.x == -10.5)
end

do -- A Fuel depot with fuel on another road counts for nothing: an empty one on this road is yellow.
  local logistics = reset()
  local far
  local request = fuelled(logistics, 0, function()
    far = fuel_depot(logistics, -40.5, 0.5, { { "coal", 20 } })
    fuel_depot(logistics, -10.5, 0.5)
    return far
  end)
  check("those with fuel are asked first, however far", requests[2].goal.x == far.position.x)
  answer(logistics, 2, "none")
  check("then, none with fuel having a road, the empty one", requests[3].goal.x == -10.5)
  answer(logistics, 3, "route")
  check("the freighter stays home", not has_trip(request))
  check("waiting for fuel, not red", logistics.get_status(request) == "no-fuel")
end

do -- No Fuel depot at all: red, until one is built; then a freighter sets off to fill up there.
  local logistics = reset()
  local request = fuelled(logistics, 0)
  check("a freighter that can't make it stays home", not has_trip(request) and logistics.freighter_counts(request) == 5)
  check("and its depot says no Fuel depot is connected by road", logistics.get_status(request) == "no-fuel-depot")
  game.tick = 60
  logistics.on_tick()
  check("it waits", #requests == 1 and logistics.get_status(request) == "no-fuel-depot")
  local fuel = fuel_depot(logistics, -10.5, 0.5, { { "coal", 20 } })
  logistics.on_depot_changed(fuel)
  game.tick = 120
  logistics.on_tick()
  check("a Fuel depot built: it looks again at once", #requests == 2)
  answer(logistics, 2, "route")
  local trip = trips_from(request)[1]
  check("and sets off to fill up there", trip and trip.fuel_search and requests[3].goal.x == fuel.position.x)
end

do -- A Fuel depot with fuel but no road route to it: red too, and no new search while it cools down.
  local logistics = reset()
  local request = fuelled(logistics, 0, function()
    return fuel_depot(logistics, -10.5, 0.5, { { "coal", 20 } })
  end)
  answer(logistics, 2, "none")
  check("no route: the freighter stays home", not has_trip(request) and logistics.freighter_counts(request) == 5)
  check("and its depot says no Fuel depot is connected by road", logistics.get_status(request) == "no-fuel-depot")
  game.tick = 60
  logistics.on_tick()
  check("nothing is asked again meanwhile", #requests == 2 and logistics.get_status(request) == "no-fuel-depot")
end

do -- Short, but enough to reach the provider, and nowhere to fill up: it goes anyway.
  local logistics = reset()
  local request, provider = fuelled(logistics, 0.15 * MJ)
  local trip = trips_from(request)[1]
  check("it sets off on what it has", trip and trip.destination.x == provider.position.x and trip.refueled)
end

do -- No road route to the Fuel depot: that one waits out a cooldown, and the freighter goes on.
  local logistics = reset()
  local fuel = nil
  local request = fuelled(logistics, 0.5 * MJ, function()
    fuel = fuel_depot(logistics, -10.5, 0.5, { { "coal", 20 } })
    return fuel
  end)
  answer(logistics, 2, "none")
  local trip = trips_from(request)[1]
  check("no route: the Fuel depot goes on cooldown", storage.depots[request.unit_number].cooldowns[fuel.unit_number])
  check("and it sets off with what it has", trip.destination and not trip.fuel_search and not trip.refuel)
end

do -- Running dry on the road: it crawls to a Fuel depot; one removed on the way sends it to another.
  local logistics = reset()
  local first, second
  local request = fuelled(logistics, 3 * MJ, function()
    first = fuel_depot(logistics, 20.5, 0.5, { { "coal", 20 } })
    second = fuel_depot(logistics, 40.5, 0.5, { { "coal", 20 } })
    return first
  end)
  local trip = trips_from(request)[1]
  check("with fuel for the leg it doesn't look for any", not trip.fuel_search and #requests == 1)
  -- 21 tiles on, beside the first Fuel depot, with fuel for 10 tiles left.
  trip.energy = 0.1 * MJ
  trip.drone.position = { x = trip.drone.position.x + 21, y = trip.drone.position.y }
  game.tick = 60
  logistics.on_tick()
  check("run dry, it crawls and looks for a Fuel depot", trip.dry and trip.drone.speed < 0.2 and trip.fuel_search)
  answer(logistics, #requests, "route")
  check("and heads for it", trip.refuel == first.unit_number)
  first.valid = false
  logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = first.unit_number })
  check("that one removed, it looks again", trip.fuel_search and requests[#requests].goal.x == second.position.x)
  check("and the removed depot's tank goes with it", storage.depots[first.unit_number] == nil)
  answer(logistics, #requests, "route")
  arrive(logistics, trip)
  check("it fills up at the other", second.chest.count("coal") < 20 and not trip.dry)
end

do -- A Fuel depot of fuel cells with no room left for used ones gives nothing: it isn't a candidate.
  local logistics = reset()
  local request = fuelled(logistics, 0, function()
    local fuel = fuel_depot(logistics, -10.5, 0.5, { { "cell", 3 } })
    fuel.chest.room = 0
    return fuel
  end)
  check("a Fuel depot with no room for burnt results is asked only as an empty one", #requests == 2)
  answer(logistics, 2, "route")
  check("so a freighter that can't make it stays home", not has_trip(request))
  check("waiting for fuel", logistics.get_status(request) == "no-fuel")
end

do -- Cloning a Fuel depot keeps its liquid fuel: the tank cloned with it, or the original's fluid.
  local logistics = reset()
  local original, source = fuel_depot(logistics, -10.5, 0.5, { { "coal", 10 } }, "water", 1234)
  source.held.temperature = 60
  local function destroyable(thing)
    function thing.destroy()
      thing.valid = false
    end
    return thing
  end
  -- What stands where: the cloned entities, as LuaSurface::find_entities_filtered finds them.
  local placed = {}
  function surface.find_entities_filtered(filter)
    local found = {}
    for _, thing in ipairs(placed) do
      local dx, dy = thing.position.x - filter.position.x, thing.position.y - filter.position.y
      if thing.valid and thing.name == filter.name and dx * dx + dy * dy <= filter.radius ^ 2 then
        found[#found + 1] = thing
      end
    end
    return found
  end

  local alone = entity("jatz-fuel-depot", 40.5, 0.5)
  logistics.on_cloned(original, alone)
  local made = storage.depots[alone.unit_number].tank
  check(
    "a Fuel depot cloned alone gets a tank with the original's liquid fuel",
    made and made.held.name == "water" and made.held.amount == 1234 and made.held.temperature == 60
  )
  check(
    "the original keeps its own",
    source.held.amount == 1234 and storage.depots[original.unit_number].tank == source
  )

  -- Cloned with its tank, the depot's event first: it adopts that tank, fluid and all.
  local copy = destroyable(entity("jatz-fuel-depot", 80.5, 0.5))
  local copy_tank = destroyable(tank("jatz-fuel-depot-tank", 80.5, 0.5, "water", 1234, 60))
  placed = { copy, copy_tank }
  local created = #surface.created
  logistics.on_cloned(original, copy)
  check("cloned with its tank, the depot adopts it", storage.depots[copy.unit_number].tank == copy_tank)
  check("making none of its own", #surface.created == created and copy_tank.held.amount == 1234)
  logistics.on_cloned(source, copy_tank)
  check("and the tank's own clone event leaves it", copy_tank.valid)

  -- The tank's event first: it stays for the depot cloned on it, which then adopts it.
  local later = destroyable(entity("jatz-fuel-depot", 120.5, 0.5))
  local later_tank = destroyable(tank("jatz-fuel-depot-tank", 120.5, 0.5, "water", 1234, 60))
  placed = { later, later_tank }
  logistics.on_cloned(source, later_tank)
  check("a tank cloned before its depot's event stays", later_tank.valid)
  logistics.on_cloned(original, later)
  check("and the depot adopts it", storage.depots[later.unit_number].tank == later_tank and #surface.created == created)

  -- One tank only: a second cloned onto a depot that has one goes, as does one cloned alone.
  local extra = destroyable(tank("jatz-fuel-depot-tank", 120.5, 0.5, "water", 5))
  placed = { later, later_tank, extra }
  logistics.on_cloned(source, extra)
  check("a second tank cloned onto a Fuel depot with one goes", not extra.valid and later_tank.valid)
  local lone = destroyable(tank("jatz-fuel-depot-tank", 160.5, 0.5, "water", 5))
  placed = { lone }
  logistics.on_cloned(source, lone)
  check("a tank cloned without its depot goes", not lone.valid)
end

do -- A freighter shows its fuel on hover: green, yellow when low, red when dry; nothing if off.
  local logistics = reset()
  local request, provider = fuelled(logistics, 20 * MJ)
  stocked(provider, "a", 20)
  stocked(request)
  local trip = trips_from(request)[1]
  local status = trip.drone.custom_status
  check(
    "a full freighter's status is green, its fuel against a full tank",
    status
      and status.diode == defines.entity_status_diode.green
      and status.label[1] == "jatz-gui.freighter-fuel"
      and status.label[2][1] == "jatz-gui.energy-mj"
      and status.label[2][2] == "20.0"
      and status.label[3][2] == "20.0"
  )
  trip.energy = 3 * MJ
  game.tick = 60
  logistics.on_tick()
  check("low, yellow, and says how much", trip.drone.custom_status.diode == defines.entity_status_diode.yellow)
  check("as it burns", trip.drone.custom_status.label[2][2] == "3.0")
  trip.energy = 0
  game.tick = 120
  logistics.on_tick()
  check("dry, red", trip.drone.custom_status.diode == defines.entity_status_diode.red)
  trip.energy = 10 * MJ
  arrive(logistics, trip)
  check("painted for its load, the new freighter shows it too", trip.drone.custom_status.label[2][2] == "10.0")
  check("(it was swapped)", trip.drone.name == "jatz-freighter-drone-500")
  SETTINGS["jatz-freighter-fuel-per-tile"] = 0
  game.tick = 180
  logistics.on_tick()
  check("with fuel turned off, no status", trip.drone.custom_status == nil)
  check("and the panel's fuel is marked unused", logistics.freighter_fuel(request).used == false)
  SETTINGS["jatz-freighter-fuel-per-tile"] = 10
end

do -- A fuel item worth more than a tank (10 GJ) goes in whole, and stays with the freighter parked.
  local logistics = reset()
  local fuel
  local request = fuelled(logistics, 0.5 * MJ, function()
    fuel = fuel_depot(logistics, -10.5, 0.5, { { "megacell", 3 } })
    return fuel
  end)
  local trip = trips_from(request)[1]
  answer(logistics, 2, "route")
  arrive(logistics, trip)
  check("one item is taken", fuel.chest.count("megacell") == 2)
  check("all 10 GJ of it", trip.energy == 10000.5 * MJ)
  check("shown in GJ", trip.drone.custom_status.label[2][1] == "jatz-gui.energy-gj")
  check("green", trip.drone.custom_status.diode == defines.entity_status_diode.green)
  arrive(logistics, trip)
  arrive(logistics, trip)
  local energy = trip.energy
  check("it parks with all it has left", logistics.freighter_fuel(request).home[1] == energy and energy > 9 * 1e9)
  check("the others are full", logistics.freighter_fuel(request).home[5] == 0.5 * MJ)
  game.tick = 600
  logistics.on_tick()
  answer(logistics, #requests, "route")
  local again = trips_from(request)[1]
  check("the fullest goes next: the one with the big fill", again and again.energy == energy)
  check("and needs no fuel stop", again and not again.fuel_search and not again.refuel)
end

do -- Freighters taken out take their fuel with them; new ones put in come with a full tank.
  local logistics = reset()
  local request = setup(logistics)
  logistics.set_freighter_fuel(request, 0)
  local hand = script_inventory(1)
  logistics.take_freighters(request, nil, nil, hand)
  logistics.put_freighters(request, stack("jatz-quinityn-freighter", 5))
  local fuel = logistics.freighter_fuel(request)
  check("new freighters put in after the old ones left are full", #fuel.home == 5 and fuel.home[5] == fuel.capacity)
end

do -- The provider goes (its entity invalid before on_object_destroyed) while a freighter at home
  -- looks for fuel that turns out unreachable: it still drives somewhere, the provider's old zone.
  local logistics = reset()
  local request, provider = fuelled(logistics, 0.15 * MJ, function()
    return fuel_depot(logistics, -10.5, 0.5, { { "coal", 20 } })
  end)
  local trip = trips_from(request)[1]
  provider.valid = false
  answer(logistics, 2, "none")
  local command = trip.drone.commands[#trip.drone.commands]
  check("it never drives without a destination", command.destination and command.destination.x == provider.position.x)
end

do -- Fuel turned off (0 per tile): nothing burns and nobody looks for fuel.
  local logistics = reset()
  SETTINGS["jatz-freighter-fuel-per-tile"] = 0
  local request = fuelled(logistics, 0.01 * MJ, function()
    return fuel_depot(logistics, -10.5, 0.5, { { "coal", 20 } })
  end)
  local trip = trips_from(request)[1]
  trip.drone.position = { x = trip.drone.position.x + 400, y = trip.drone.position.y }
  game.tick = 60
  logistics.on_tick()
  check("with fuel off, a freighter goes straight on and burns nothing", #requests == 1 and trip.energy == 0.01 * MJ)
  logistics = reset()
  local empty = fuelled(logistics, 0)
  trip = trips_from(empty)[1]
  check("and one sent with an empty tank sets off at full speed", trip and not trip.dry and trip.drone.speed == nil)
  SETTINGS["jatz-freighter-fuel-per-tile"] = 10
end

print("all logistics checks passed")
