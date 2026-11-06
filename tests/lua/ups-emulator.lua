-- SPDX-License-Identifier: LGPL-3.0-only
-- An engine-free stand-in for the UPS benchmark (tools/benchmark_ups.py): the real control.lua
-- and scripts/ run against a fake Factorio runtime on the same map (the benchmark mod's layout.lua
-- and presets.lua), with the same stock and demand, and the Lua instructions the mod executes are
-- counted. Instruction counts don't depend on the machine, so CI can compare a pull request with
-- its base exactly (tools/emulate_ups.py). The fake answers path requests a tick later with the
-- shortest road route, drives freighters along it at their prototype speed, and completes stop
-- commands after their wait; it doesn't model the engine's own cost (pathfinding, movement), which
-- only the real benchmark measures. Freighters move along their route at the speed the mod sets
-- (`LuaEntity::speed`), so fuel burns and impact checks see them move. Fuel depots are kept stocked
-- with solid fuel; there are no enemies.
--
-- Only the mod's own Lua is counted, exactly, one instruction at a time. Every function and
-- computed property of the fake runtime is wrapped by `native`, the one boundary between the mod
-- and the fake: counting stops when the mod calls into it and starts again when it returns, so how
-- the fake does its work (inventory loops, path answers, movement) never shows. The few instructions
-- of the boundary itself are measured once at start-up and taken off. Calls into the runtime's
-- functions (methods such as get_item_count, request_path or create_entity, not property reads)
-- are counted separately, as `api_calls`: a machine-independent stand-in for the API's own cost.
-- Only measured ticks are counted; the harness's stocking runs outside the mod's handlers.
--
-- lua5.2 tests/lua/ups-emulator.lua [mod root] [preset] [ticks]   (prints one JSON object)
-- It reads the freighter prototype (io) and times the handlers (os.clock), outside the game.
-- luacheck: read globals io os
-- luacheck: globals settings
local MOD_ROOT, PRESET, TICKS = arg[1] or ".", arg[2] or "quick", tonumber(arg[3])
local HERE = (arg[0]:match("^(.*)/[^/]*$") or ".")
package.path = MOD_ROOT .. "/?.lua;" .. HERE .. "/../factorio/ups-benchmark_0.1.0/?.lua;" .. package.path
local layout = require("layout")
local preset = require("presets")[PRESET] or error("no preset " .. PRESET)

-- Instruction counting: a count hook on every instruction, armed only while the mod's own Lua runs
-- in a measured tick. `native` wraps everything the fake runtime offers the mod: while armed, a call
-- through it disarms the hook, runs the fake's code, and arms it again on the way back.
local instructions, armed = 0, false
-- Crossings of the boundary: calls of runtime functions, and computed property reads and writes.
local crossings = { call = 0, property = 0 }
local sethook = debug.sethook
local function tally()
  instructions = instructions + 1
end
local function arm()
  armed = true
  sethook(tally, "", 1)
end
local function disarm()
  armed = false
  sethook()
end
local function resume(...)
  arm()
  return ...
end
-- `kind`: "call" for a runtime function (the default), "property" for a metamethod.
local function native(fn, kind)
  kind = kind or "call"
  return function(...)
    if not armed then
      return fn(...)
    end
    disarm()
    crossings[kind] = crossings[kind] + 1
    return resume(fn(...))
  end
end
-- Every function in a fake object, wrapped in place.
local function natives(object)
  for key, value in pairs(object) do
    if type(value) == "function" then
      object[key] = native(value)
    end
  end
  return object
end
-- A metatable whose __index and __newindex functions are computed properties.
local function properties(meta)
  for _, key in ipairs({ "__index", "__newindex" }) do
    if type(meta[key]) == "function" then
      meta[key] = native(meta[key], "property")
    end
  end
  return meta
end
-- The instructions one crossing costs on the mod's side of the boundary (the wrapper's own, before
-- it disarms and after it arms again), so they can be taken off: a call through a wrapped empty
-- function less a bare arm and disarm, less the caller's own two (load the function, call it).
local BOUNDARY
do
  local probe = native(function() end)
  arm()
  disarm()
  local bare = instructions
  instructions = 0
  arm()
  probe()
  disarm()
  BOUNDARY = instructions - bare - 2
  instructions, crossings.call = 0, 0
  assert(BOUNDARY >= 0 and BOUNDARY < 32, "emulator: unexpected boundary cost " .. BOUNDARY)
end

local DRONE, FREIGHTER, ROAD = "jatz-freighter-drone", "jatz-quinityn-freighter", "jatz-road"
local FUEL_TANK = "jatz-fuel-depot-tank"
local STACK_SIZE = {
  ["iron-plate"] = 100,
  ["copper-plate"] = 100,
  ["steel-plate"] = 100,
  ["iron-gear-wheel"] = 100,
  ["electronic-circuit"] = 200,
  ["copper-cable"] = 200,
  coal = 50,
  stone = 50,
  ["plastic-bar"] = 100,
  ["stone-brick"] = 100,
  ["solid-fuel"] = 50,
  [FREIGHTER] = 10,
}
-- Fuel values in joules (base game); other items don't burn.
local FUEL_VALUE = { coal = 4000000, ["solid-fuel"] = 12000000 }
-- The freighter's speed in tiles per tick, from its prototype.
local SPEED = 0.2
do
  local handle = io.open(MOD_ROOT .. "/prototypes/freighter-drone.lua")
  if handle then
    SPEED = tonumber(handle:read("*a"):match("movement_speed%s*=%s*([%d.]+)")) or SPEED
    handle:close()
  end
end
local PERIOD, CHEST_SLOTS = 60, 48

-- Runtime globals the mod reads.
local handlers, nth, interfaces = {}, {}, {}
defines = setmetatable(
  {
    direction = { north = 0, east = 4, south = 8, west = 12 },
    inventory = { chest = 1 },
    entity_status_diode = { green = 1, red = 2, yellow = 3 },
    target_type = { entity = 1 },
    behavior_result = { in_progress = 0, fail = 1, success = 2, deleted = 3 },
    command = { go_to_location = 1, stop = 2 },
    distraction = { none = 0 },
    events = setmetatable(
      {},
      properties({
        __index = function(_, name)
          return name
        end,
      })
    ),
  },
  properties({
    __index = function(_, name)
      return setmetatable(
        {},
        properties({
          __index = function(_, key)
            return name .. "." .. key
          end,
        })
      )
    end,
  })
)
local registrations = {}
script = {
  on_event = function(event, handler)
    handlers[event] = handler
  end,
  on_nth_tick = function(ticks, handler)
    nth[ticks] = handler
  end,
  on_init = function(handler)
    handlers.on_init = handler
  end,
  on_load = function() end,
  on_configuration_changed = function() end,
  register_on_object_destroyed = function(entity)
    registrations[entity] = true
    return entity.unit_number
  end,
  active_mods = { ["jatz-distribution"] = "emulated" },
}
natives(script)
remote = natives({
  add_interface = function(name, functions)
    interfaces[name] = functions
  end,
})
commands = natives({ add_command = function() end })
prototypes = {
  item = {},
  entity = {
    [DRONE] = {
      collision_box = { left_top = { x = -0.2, y = -0.2 }, right_bottom = { x = 0.2, y = 0.2 } },
      collision_mask = {},
      speed = SPEED,
    },
  },
  fluid = {},
  decorative = {},
  quality = { normal = { name = "normal" } },
  -- Nothing researched: a technology's `level` is its own, and none is done.
  technology = {},
  -- No cargo colours: every load takes the unknown paint, a swap all the same.
  mod_data = {},
}
-- The base game's units, for the "type" filter the mod asks for the units freighters run over.
local UNITS = {}
for _, size in ipairs({ "small", "medium", "big", "behemoth" }) do
  UNITS[size .. "-biter"], UNITS[size .. "-spitter"] = "unit", "unit"
end
prototypes.get_entity_filtered = native(function(filters)
  assert(#filters == 1 and filters[1].filter == "type", "emulator: only the type filter is faked")
  local types = type(filters[1].type) == "table" and filters[1].type or { filters[1].type }
  local found = {}
  for name, kind in pairs(UNITS) do
    for _, wanted in ipairs(types) do
      if kind == wanted then
        found[name] = { name = name, type = kind }
      end
    end
  end
  return found
end)
-- None of the emulated items spoil.
local function never_spoils()
  return 0
end
for name, size in pairs(STACK_SIZE) do
  prototypes.item[name] =
    { name = name, stack_size = size, fuel_value = FUEL_VALUE[name] or 0, get_spoil_ticks = never_spoils }
end
local NORMAL = prototypes.quality.normal
local technologies = {}
for _, name in ipairs({ "jatz-freighter-speed", "jatz-freighter-item-capacity", "jatz-freighter-fluid-capacity" }) do
  for level = 1, 5 do
    prototypes.technology[name .. "-" .. level] = { name = name .. "-" .. level }
    technologies[name .. "-" .. level] = { researched = false, level = level }
  end
end
for _, name in ipairs({ "jatz-freight-system", "jatz-liquid-freight", "jatz-road-network-monitor" }) do
  prototypes.technology[name] = { name = name }
  technologies[name] = { researched = false, level = 1 }
end
-- The runtime settings at their defaults (settings.lua); any other name fails.
local function strict(values, kind)
  return setmetatable(
    {},
    properties({
      __index = function(_, name)
        return { value = assert(values[name], "emulator: unknown " .. kind .. " setting " .. tostring(name)) }
      end,
    })
  )
end
settings = {
  global = strict({ ["jatz-freighter-fuel-capacity"] = 20, ["jatz-freighter-fuel-per-tile"] = 10 }, "global"),
  startup = strict({}, "startup"),
}
-- Alt-mode cargo icons: drawn, never read back.
rendering = natives({
  draw_sprite = function()
    return natives({ valid = true, destroy = function() end })
  end,
})

-- Item stacks: name, count (0 clears), quality, transfer_stack, clear.
local function new_stack()
  local data = { count = 0 }
  local stack = {}
  local methods = {}
  function methods.clear()
    data.name, data.count, data.quality = nil, 0, nil
  end
  function methods.set_stack(spec)
    if not spec or (spec.count or 0) <= 0 then
      methods.clear()
      return true
    end
    data.name, data.count, data.quality = spec.name, spec.count, NORMAL
    return true
  end
  function methods.transfer_stack(from, amount)
    if not from.valid_for_read then
      return false
    end
    if data.count > 0 and data.name ~= from.name then
      return false
    end
    local room = STACK_SIZE[from.name] - data.count
    local moved = math.min(amount or from.count, from.count, room)
    if moved <= 0 then
      return false
    end
    data.name, data.quality, data.count = from.name, NORMAL, data.count + moved
    from.count = from.count - moved
    return true
  end
  natives(methods)
  return setmetatable(
    stack,
    properties({
      __index = function(_, field)
        if field == "valid_for_read" then
          return data.count > 0
        elseif field == "valid" then
          return true
        elseif field == "count" or field == "name" or field == "quality" then
          return data[field]
        end
        return methods[field]
      end,
      __newindex = function(_, field, value)
        assert(field == "count", "stack field " .. field)
        data.count = value
        if value <= 0 then
          methods.clear()
        end
      end,
    })
  )
end

local function item_name(id)
  return type(id) == "table" and id.name or id
end

-- Inventories: stacks at [1..n], and the methods the mod uses.
local function new_inventory(size)
  local inv = { valid = true }
  for index = 1, size do
    inv[index] = new_stack()
  end
  function inv.get_item_count(id)
    local name, total = item_name(id), 0
    for index = 1, #inv do
      local stack = inv[index]
      if stack.valid_for_read and (not name or stack.name == name) then
        total = total + stack.count
      end
    end
    return total
  end
  function inv.get_contents()
    local found = {}
    for index = 1, #inv do
      local stack = inv[index]
      if stack.valid_for_read then
        found[#found + 1] = { name = stack.name, count = stack.count, quality = "normal" }
      end
    end
    return found
  end
  function inv.is_empty()
    return inv.get_item_count() == 0
  end
  -- An ItemFilter of any quality (every item here is normal quality).
  function inv.get_item_count_filtered(filter)
    assert(type(filter) == "table" and filter.name and not filter.quality, "emulator: an item filter of any quality")
    return inv.get_item_count(filter.name)
  end
  function inv.get_insertable_count(id)
    local name, room = item_name(id), 0
    for index = 1, #inv do
      local stack = inv[index]
      if not stack.valid_for_read then
        room = room + STACK_SIZE[name]
      elseif stack.name == name then
        room = room + STACK_SIZE[name] - stack.count
      end
    end
    return room
  end
  function inv.insert(spec)
    local name, left = spec.name, spec.count
    for pass = 1, 2 do
      for index = 1, #inv do
        local stack = inv[index]
        if left <= 0 then
          break
        end
        if (pass == 1 and stack.valid_for_read and stack.name == name) or (pass == 2 and not stack.valid_for_read) then
          local put = math.min(left, STACK_SIZE[name] - (stack.count or 0))
          if put > 0 then
            stack.set_stack({ name = name, count = (stack.count or 0) + put })
            left = left - put
          end
        end
      end
    end
    return spec.count - left
  end
  function inv.remove(spec)
    local name, left = item_name(spec), spec.count or math.huge
    local removed = 0
    for index = #inv, 1, -1 do
      local stack = inv[index]
      if left <= 0 then
        break
      end
      if stack.valid_for_read and stack.name == name then
        local take = math.min(left, stack.count)
        stack.count = stack.count - take
        left, removed = left - take, removed + take
      end
    end
    return removed
  end
  function inv.find_item_stack(id)
    local name = item_name(id)
    for index = 1, #inv do
      if inv[index].valid_for_read and inv[index].name == name then
        return inv[index], index
      end
    end
  end
  function inv.resize(size_)
    for index = #inv + 1, size_ do
      inv[index] = new_stack()
    end
  end
  function inv.destroy()
    inv.valid = false
  end
  return natives(inv)
end

-- The world: surfaces with road tiles, entities, scheduled engine events.
local tick = 0
local next_unit = 0
local queue = {}
local function schedule(at, event)
  queue[at] = queue[at] or {}
  table.insert(queue[at], event)
end
local stats = { path_requests = 0, commands = 0, drones = 0, spilled = 0 }
-- The player's force, at war with the enemy force as in a new game (no enemies are on the map).
local force = { name = "player", index = 1, technologies = technologies }
-- How each freighter finishes its route, when the arrival comes (by freighter).
local arrive = setmetatable({}, { __mode = "k" })
local forces = {
  player = force,
  enemy = { name = "enemy", index = 2, technologies = {} },
  neutral = { name = "neutral", index = 3, technologies = {} },
}
function force.is_enemy(other)
  return other.name == "enemy"
end
for _, other in pairs(forces) do
  -- LuaForce::get_entity_count: nobody has any units here (no enemies on the map).
  function other.get_entity_count(name)
    assert(UNITS[name], "emulator: not a unit prototype " .. tostring(name))
    return 0
  end
  if other ~= force then
    function other.is_enemy(them)
      return them.name == "player"
    end
  end
  natives(other)
end
local destroyed = {}

local function tile_key(x, y)
  return x * 65536 + y
end

local function new_surface(index, plan)
  local surface = { index = index, name = plan.name, valid = true, road = {}, entities = {} }
  for _, rect in ipairs(plan.roads) do
    for x = rect[1], rect[3] do
      for y = rect[2], rect[4] do
        surface.road[tile_key(x, y)] = true
      end
    end
  end
  -- Road distance maps, by goal tile, filled on first use (breadth-first over road tiles).
  local maps = {}
  function surface.distances(gx, gy)
    local goal = tile_key(gx, gy)
    if maps[goal] ~= nil then
      return maps[goal]
    end
    if not surface.road[goal] then
      maps[goal] = false
      return false
    end
    local distance = { [goal] = 0 }
    local frontier, head = { { gx, gy } }, 1
    while frontier[head] do
      local x, y = frontier[head][1], frontier[head][2]
      head = head + 1
      local here = distance[tile_key(x, y)]
      for _, step in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local nx, ny = x + step[1], y + step[2]
        local name = tile_key(nx, ny)
        if surface.road[name] and not distance[name] then
          distance[name] = here + 1
          frontier[#frontier + 1] = { nx, ny }
        end
      end
    end
    maps[goal] = distance
    return distance
  end
  -- The shortest road route from one position to another as corner waypoints, or nil.
  function surface.route(from, to)
    local sx, sy, gx, gy = math.floor(from.x), math.floor(from.y), math.floor(to.x), math.floor(to.y)
    local distance = surface.distances(gx, gy)
    if not distance or not distance[tile_key(sx, sy)] then
      return nil
    end
    local path, x, y, dx, dy = {}, sx, sy, nil, nil
    while x ~= gx or y ~= gy do
      local here = distance[tile_key(x, y)]
      for _, step in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        if distance[tile_key(x + step[1], y + step[2])] == here - 1 then
          if dx and (dx ~= step[1] or dy ~= step[2]) then
            path[#path + 1] = { position = { x = x + 0.5, y = y + 0.5 } }
          end
          dx, dy, x, y = step[1], step[2], x + step[1], y + step[2]
          break
        end
      end
    end
    path[#path + 1] = { position = { x = gx + 0.5, y = gy + 0.5 } }
    return path, distance[tile_key(sx, sy)]
  end
  function surface.get_tile(x, y)
    local road = surface.road[tile_key(math.floor(x), math.floor(y))]
    return natives({
      valid = true,
      name = road and ROAD or "lab-dark-1",
      collides_with = function()
        return false
      end,
    })
  end
  function surface.get_hidden_tile()
    return nil
  end
  function surface.get_double_hidden_tile()
    return nil
  end
  function surface.set_tiles() end
  function surface.set_hidden_tile() end
  function surface.set_double_hidden_tile() end
  function surface.find_entities_filtered()
    return {}
  end
  -- No enemy units anywhere on the map.
  function surface.count_entities_filtered()
    return 0
  end
  function surface.find_decoratives_filtered()
    return {}
  end
  function surface.destroy_decoratives() end
  function surface.spill_item_stack(parameters)
    stats.spilled = stats.spilled + parameters.stack.count
    return {}
  end
  function surface.request_path(parameters)
    stats.path_requests = stats.path_requests + 1
    next_unit = next_unit + 1
    local id = next_unit
    local path = surface.route(parameters.start, parameters.goal)
    schedule(tick + 1, { name = "on_script_path_request_finished", event = { id = id, path = path } })
    return id
  end
  function surface.pollute() end
  -- A Fuel depot's hidden tank: no liquid fuel is piped in.
  local function new_tank(parameters)
    next_unit = next_unit + 1
    local position = parameters.position
    local tank = {
      valid = true,
      name = FUEL_TANK,
      unit_number = next_unit,
      position = { x = position.x or position[1], y = position.y or position[2] },
      direction = parameters.direction,
      surface = surface,
      surface_index = surface.index,
      force = parameters.force,
      force_index = parameters.force.index,
    }
    function tank.get_fluid()
      return nil
    end
    function tank.get_fluid_capacity()
      return 1000
    end
    function tank.remove_fluid()
      return nil
    end
    function tank.destroy()
      tank.valid = false
    end
    return natives(tank)
  end
  function surface.create_entity(parameters)
    if parameters.name == FUEL_TANK then
      return new_tank(parameters)
    end
    assert(
      parameters.name:sub(1, #DRONE) == DRONE,
      "emulator only creates freighters and tanks, not " .. parameters.name
    )
    stats.drones = stats.drones + 1
    next_unit = next_unit + 1
    local position = parameters.position
    -- Where it stands, or the route it drives: from `from` at tick `since`, through `points`.
    local at = { x = position.x or position[1], y = position.y or position[2] }
    local fields = { speed = SPEED, orientation = 0, health = 100 }
    local moving
    local function where(now)
      if not moving then
        return at.x, at.y
      end
      local left = (now - moving.since) * fields.speed
      local x, y = moving.from.x, moving.from.y
      for _, point in ipairs(moving.points) do
        local dx, dy = point.x - x, point.y - y
        local length = math.abs(dx) + math.abs(dy)
        if left <= length then
          local share = length > 0 and left / length or 0
          return x + dx * share, y + dy * share
        end
        left, x, y = left - length, point.x, point.y
      end
      return x, y
    end
    -- Stop where it is now (a new command, or a change of speed restarts the route from here).
    local function halt()
      at.x, at.y = where(tick)
      moving = nil
    end
    local drone = {
      valid = true,
      name = parameters.name,
      unit_number = next_unit,
      surface = surface,
      surface_index = surface.index,
      force = parameters.force or force,
      force_index = (parameters.force or force).index,
      version = 0,
    }
    -- Drive the rest of `points` from here at the current speed; arrival is scheduled for when
    -- it gets there.
    local function drive(points, event)
      moving = { from = { x = at.x, y = at.y }, since = tick, points = points, event = event }
      local length, x, y = 0, at.x, at.y
      for _, point in ipairs(points) do
        length, x, y = length + math.abs(point.x - x) + math.abs(point.y - y), point.x, point.y
      end
      drone.version = drone.version + 1
      local arrival = tick + math.max(1, math.ceil(length / math.max(fields.speed, 1e-6)))
      moving.until_tick = arrival
      schedule(arrival, { name = "on_ai_command_completed", event = event, drone = drone, version = drone.version })
    end
    -- What's left of the route from where it stands now.
    local function remaining()
      local left = (tick - moving.since) * fields.speed
      local x, y, rest = moving.from.x, moving.from.y, {}
      for _, point in ipairs(moving.points) do
        local length = math.abs(point.x - x) + math.abs(point.y - y)
        if left < length then
          rest[#rest + 1] = point
        end
        left, x, y = math.max(0, left - length), point.x, point.y
      end
      return rest
    end
    function drone.destroy()
      drone.valid = false
      surface.entities[drone] = nil
      if registrations[drone] then
        destroyed[#destroyed + 1] = drone
      end
      return true
    end
    drone.commandable = {
      set_command = native(function(command)
        stats.commands = stats.commands + 1
        halt()
        drone.version = drone.version + 1
        local event = { unit_number = drone.unit_number, result = defines.behavior_result.success }
        if command.type == defines.command.go_to_location then
          local path = surface.route(at, command.destination)
          if path then
            local points = {}
            for _, waypoint in ipairs(path) do
              points[#points + 1] = waypoint.position
            end
            points[#points] = { x = command.destination.x, y = command.destination.y }
            drive(points, event)
          else
            event.result = defines.behavior_result.fail
            schedule(
              tick + 60,
              { name = "on_ai_command_completed", event = event, drone = drone, version = drone.version }
            )
          end
        else
          schedule(
            tick + (command.ticks_to_wait or 1),
            { name = "on_ai_command_completed", event = event, drone = drone, version = drone.version }
          )
        end
      end),
    }
    arrive[drone] = function()
      if moving then
        local last = moving.points[#moving.points]
        if last then
          at.x, at.y = last.x, last.y
        end
        moving = nil
      end
    end
    surface.entities[drone] = true
    drone.destroy = native(drone.destroy)
    return setmetatable(
      drone,
      properties({
        __index = function(_, field)
          if field == "position" then
            local x, y = where(tick)
            return { x = x, y = y }
          end
          return fields[field]
        end,
        __newindex = function(_, field, value)
          if field == "speed" and moving and value ~= fields.speed then
            -- The rest of the route at the new speed, arriving later or sooner.
            local rest, event = remaining(), moving.event
            halt()
            fields.speed = value
            drive(rest, event)
            return
          end
          fields[field] = value
        end,
      })
    )
  end
  -- Everything a surface offers the mod (distances and route are the fake's own, but wrapping them
  -- changes nothing: the fake calls them with counting already off).
  return natives(surface)
end

game = {
  tick = 0,
  surfaces = {},
  forces = forces,
  players = {},
  connected_players = {},
  create_inventory = new_inventory,
  get_player = function()
    return nil
  end,
  get_surface = function(index)
    return game.surfaces[index]
  end,
}
natives(game)
storage = {}

local function new_depot(surface, name, x, y, direction)
  next_unit = next_unit + 1
  local chest = new_inventory(CHEST_SLOTS)
  local entity = {
    valid = true,
    name = name,
    unit_number = next_unit,
    position = { x = x, y = y },
    direction = direction,
    surface = surface,
    surface_index = surface.index,
    force = force,
    force_index = force.index,
  }
  function entity.get_inventory()
    return chest
  end
  function entity.insert(spec)
    return chest.insert(spec)
  end
  return natives(entity), chest
end

-- Run a mod handler, counting its instructions in measured ticks.
local cpu, measuring = 0, false
local function call(handler, event)
  local started = os.clock()
  if measuring then
    arm()
    handler(event)
    disarm()
  else
    handler(event)
  end
  cpu = cpu + os.clock() - started
end

-- Load the mod and build the map.
require("control")
call(handlers.on_init)
local jatz = interfaces["jatz-distribution"]
local map = layout.generate(preset)
local summary = layout.summary(map)
local DIRECTION = {
  south = defines.direction.north,
  north = defines.direction.south,
  west = defines.direction.east,
  east = defines.direction.west,
}
local SHIFT = { north = { 0, -2 }, south = { 0, 2 }, east = { 2, 0 }, west = { -2, 0 } }
local serviced = {}
for index, plan in ipairs(map.surfaces) do
  local surface = new_surface(index, plan)
  game.surfaces[index] = surface
  for _, depot in ipairs(plan.depots) do
    local shift = SHIFT[depot.side]
    local entity, chest = new_depot(
      surface,
      "jatz-" .. depot.role .. "-depot",
      depot.x + 0.5 - shift[1],
      depot.y + 0.5 - shift[2],
      DIRECTION[depot.side]
    )
    call(handlers[defines.events.script_raised_built], { entity = entity, tick = 0 })
    if depot.role == "request" then
      assert(jatz.set_request(entity, depot.item, STACK_SIZE[depot.item] * CHEST_SLOTS), "request refused")
      jatz.add_freighters(entity, depot.freighters)
      jatz.set_freighter_fuel(entity, depot.fuel * settings.global["jatz-freighter-fuel-capacity"].value * 1000000)
    elseif depot.role == "fuel" then
      chest.insert({ name = depot.item, count = STACK_SIZE[depot.item] * CHEST_SLOTS })
    end
    serviced[#serviced + 1] = { role = depot.role, item = depot.item, chest = chest }
  end
end

-- Run: engine events, the mod's tick handlers, then stocking and emptying the depots.
local warmup, measured = preset.warmup, TICKS or preset.ticks
local per_tick, delivered, vehicles, samples = {}, 0, 0, 0
for current = 1, warmup + measured do
  tick, game.tick = current, current
  measuring = current > warmup
  local before, crossed = instructions, crossings.call + crossings.property
  for _, drone in ipairs(destroyed) do
    call(handlers[defines.events.on_object_destroyed], {
      registration_number = drone.unit_number,
      useful_id = drone.unit_number,
      type = defines.target_type.entity,
      tick = current,
    })
  end
  destroyed = {}
  for _, item in ipairs(queue[current] or {}) do
    if item.name == "on_ai_command_completed" then
      local drone = item.drone
      if drone.valid and drone.version == item.version then
        arrive[drone]()
        item.event.tick = current
        call(handlers[defines.events.on_ai_command_completed], item.event)
      end
    else
      item.event.tick = current
      call(handlers[defines.events[item.name]], item.event)
    end
  end
  queue[current] = nil
  -- The game raises on_tick before on_nth_tick.
  if handlers[defines.events.on_tick] then
    call(handlers[defines.events.on_tick], { tick = current })
  end
  local ticks = {}
  for interval in pairs(nth) do
    ticks[#ticks + 1] = interval
  end
  table.sort(ticks)
  for _, interval in ipairs(ticks) do
    if current % interval == 0 then
      call(nth[interval], { tick = current, nth_tick = interval })
    end
  end
  for index = current % PERIOD + 1, #serviced, PERIOD do
    local depot = serviced[index]
    if depot.role == "provider" or depot.role == "fuel" then
      depot.chest.insert({ name = depot.item, count = STACK_SIZE[depot.item] * CHEST_SLOTS })
    else
      local count = depot.chest.get_item_count(depot.item)
      if current > warmup then
        delivered = delivered + count
      end
      depot.chest.remove({ name = depot.item, count = count })
    end
  end
  if current > warmup then
    -- The mod's own: less the boundary's few instructions for each crossing this tick.
    local crossed_now = crossings.call + crossings.property - crossed
    per_tick[#per_tick + 1] = instructions - before - BOUNDARY * crossed_now
    if current % 600 == 0 then
      local out = 0
      for _, surface in ipairs(game.surfaces) do
        for _ in pairs(surface.entities) do
          out = out + 1
        end
      end
      vehicles, samples = vehicles + out, samples + 1
    end
  end
end
disarm()

local total, peak = 0, 0
for _, count in ipairs(per_tick) do
  total = total + count
  peak = math.max(peak, count)
end
local sorted = { table.unpack(per_tick) }
table.sort(sorted)
local result = {
  preset = PRESET,
  warmup = warmup,
  ticks = measured,
  surfaces = summary.surfaces,
  providers = summary.providers,
  requests = summary.requests,
  freighters = summary.freighters,
  fuel_depots = summary.fuel,
  instructions_per_tick = total / measured,
  instructions_p99 = sorted[math.max(1, math.floor(#sorted * 0.99))],
  instructions_max = peak,
  api_calls_per_tick = crossings.call / measured,
  path_requests = stats.path_requests,
  commands = stats.commands,
  freighters_sent = stats.drones,
  vehicles_out = samples > 0 and vehicles / samples or 0,
  delivered = delivered,
  spilled = stats.spilled,
  cpu_seconds = cpu,
}
local fields = {}
for name, value in pairs(result) do
  fields[#fields + 1] = string.format("%q:%s", name, type(value) == "string" and string.format("%q", value) or value)
end
table.sort(fields)
print("{" .. table.concat(fields, ",") .. "}")
