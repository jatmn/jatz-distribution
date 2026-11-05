-- SPDX-License-Identifier: LGPL-3.0-only
-- An engine-free stand-in for the UPS benchmark (tools/benchmark_ups.py): the real control.lua
-- and scripts/ run against a fake Factorio runtime on the same map (the benchmark mod's layout.lua
-- and presets.lua), with the same stock and demand, and the Lua instructions the mod executes are
-- counted. Instruction counts don't depend on the machine, so CI can compare a pull request with
-- its base exactly (tools/emulate_ups.py). The fake answers path requests a tick later with the
-- shortest road route, drives freighters along it at their prototype speed, and completes stop
-- commands after their wait; it doesn't model the engine's own cost (pathfinding, movement), which
-- only the real benchmark measures. Harness work (routes, movement, stocking) isn't counted.
--
-- lua5.2 tests/lua/ups-emulator.lua [mod root] [preset] [ticks]   (prints one JSON object)
-- It reads the freighter prototype (io) and times the handlers (os.clock), outside the game.
-- luacheck: read globals io os
local MOD_ROOT, PRESET, TICKS = arg[1] or ".", arg[2] or "quick", tonumber(arg[3])
local HERE = (arg[0]:match("^(.*)/[^/]*$") or ".")
package.path = MOD_ROOT .. "/?.lua;" .. HERE .. "/../factorio/ups-benchmark_0.1.0/?.lua;" .. package.path
local layout = require("layout")
local preset = require("presets")[PRESET] or error("no preset " .. PRESET)

-- Instruction counting, only while the mod's handlers run.
local counting, instructions = false, 0
local STEP = 100
debug.sethook(function()
  if counting then
    instructions = instructions + STEP
  end
end, "", STEP)

local DRONE, FREIGHTER, ROAD = "jatz-freighter-drone", "jatz-quinityn-freighter", "jatz-road"
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
  [FREIGHTER] = 10,
}
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
defines = setmetatable({
  direction = { north = 0, east = 4, south = 8, west = 12 },
  inventory = { chest = 1 },
  target_type = { entity = 1 },
  behavior_result = { in_progress = 0, fail = 1, success = 2, deleted = 3 },
  command = { go_to_location = 1, stop = 2 },
  distraction = { none = 0 },
  events = setmetatable({}, {
    __index = function(_, name)
      return name
    end,
  }),
}, {
  __index = function(_, name)
    return setmetatable({}, {
      __index = function(_, key)
        return name .. "." .. key
      end,
    })
  end,
})
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
remote = {
  add_interface = function(name, functions)
    interfaces[name] = functions
  end,
}
commands = { add_command = function() end }
prototypes = {
  item = {},
  entity = { [DRONE] = { collision_box = { { -0.4, -0.4 }, { 0.4, 0.4 } }, collision_mask = {} } },
  fluid = {},
  decorative = {},
  quality = { normal = { name = "normal" } },
}
for name, size in pairs(STACK_SIZE) do
  prototypes.item[name] = { name = name, stack_size = size }
end
local NORMAL = prototypes.quality.normal

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
  return setmetatable(stack, {
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
  return inv
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
local force = { name = "player", index = 1 }
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
    return {
      valid = true,
      name = road and ROAD or "lab-dark-1",
      collides_with = function()
        return false
      end,
    }
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
  function surface.create_entity(parameters)
    assert(parameters.name == DRONE, "emulator only creates freighters, not " .. parameters.name)
    stats.drones = stats.drones + 1
    next_unit = next_unit + 1
    local position = parameters.position
    local drone = {
      valid = true,
      name = DRONE,
      unit_number = next_unit,
      position = { x = position.x or position[1], y = position.y or position[2] },
      surface = surface,
      surface_index = surface.index,
      force = force,
      version = 0,
    }
    function drone.destroy()
      drone.valid = false
      surface.entities[drone] = nil
      if registrations[drone] then
        destroyed[#destroyed + 1] = drone
      end
      return true
    end
    drone.commandable = {
      set_command = function(command)
        stats.commands = stats.commands + 1
        drone.version = drone.version + 1
        local version = drone.version
        local event = { unit_number = drone.unit_number, result = defines.behavior_result.success }
        local at
        if command.type == defines.command.go_to_location then
          local _, length = surface.route(drone.position, command.destination)
          if length then
            at = tick + math.max(1, math.ceil(length / SPEED))
            event.arrive = command.destination
          else
            at, event.result = tick + 60, defines.behavior_result.fail
          end
        else
          at = tick + (command.ticks_to_wait or 1)
        end
        schedule(at, { name = "on_ai_command_completed", event = event, drone = drone, version = version })
      end,
    }
    surface.entities[drone] = true
    return drone
  end
  return surface
end

game = {
  tick = 0,
  surfaces = {},
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
  }
  function entity.get_inventory()
    return chest
  end
  function entity.insert(spec)
    return chest.insert(spec)
  end
  return entity, chest
end

-- Run a mod handler with instruction counting on.
local cpu = 0
local function call(handler, event)
  local started = os.clock()
  counting = true
  handler(event)
  counting = false
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
    end
    serviced[#serviced + 1] = { role = depot.role, item = depot.item, chest = chest }
  end
end

-- Run: engine events, the mod's tick handlers, then stocking and emptying the depots.
local warmup, measured = preset.warmup, TICKS or preset.ticks
local per_tick, delivered, vehicles, samples = {}, 0, 0, 0
for current = 1, warmup + measured do
  tick, game.tick = current, current
  local before = instructions
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
        if item.event.arrive then
          drone.position = { x = item.event.arrive.x, y = item.event.arrive.y }
        end
        item.event.tick = current
        call(handlers[defines.events.on_ai_command_completed], item.event)
      end
    else
      item.event.tick = current
      call(handlers[defines.events[item.name]], item.event)
    end
  end
  queue[current] = nil
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
    if depot.role == "provider" then
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
    per_tick[#per_tick + 1] = instructions - before
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
debug.sethook()

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
  instructions_per_tick = total / measured,
  instructions_p99 = sorted[math.max(1, math.floor(#sorted * 0.99))],
  instructions_max = peak,
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
