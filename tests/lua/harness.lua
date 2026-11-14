-- SPDX-License-Identifier: LGPL-3.0-only
-- The fake Factorio runtime the delivery checks run against (tests/lua/logistics.lua, and the
-- quality checks, tests/lua/quality.lua), with their shared helpers: Factorio's globals as far as
-- scripts/logistics.lua and its modules use them, quality-aware inventories and item stacks (a name
-- alone is normal quality, as in the game), entities and a surface that records path requests,
-- `reset` for fresh modules and storage, and `check`, which also verifies what freighters bring is
-- filed as the trips say. Split out of tests/lua/logistics.lua, which reached the 256 KiB a text
-- file may have in CI (AGENTS.md, "Downloads stay small").

defines = {
  direction = { north = 0, east = 4, south = 8, west = 12 },
  inventory = { chest = 1 },
  command = { go_to_location = 1, stop = 2 },
  distraction = { none = 0 },
  behavior_result = { in_progress = 0, fail = 1, success = 2, deleted = 3 },
  target_type = { entity = 1 },
  entity_status_diode = { green = 1, red = 2, yellow = 3 },
  wire_connector_id = { circuit_red = 1, circuit_green = 2 },
  -- Factorio 2.1's values (probed on 2.1.24): containers 1, storage tanks 7, send_contents 1.
  control_behavior = {
    type = { container = 1, single_fluid_box = 7 },
    single_fluid_box = { exclusive_mode = { none = 0, send_contents = 1, send_segment_contents = 2 } },
  },
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
  -- Startup settings the scripts read; new depots start with "Full loads only" off.
  startup = { ["jatz-default-full-loads"] = { value = false } },
}
-- Every item and fluid prototype has a fuel_value (0 if it doesn't burn), as in game.
prototypes = {
  entity = { ["jatz-freighter-drone"] = { collision_box = {}, collision_mask = {}, speed = 0.2 } },
  -- No research unless a check adds it (the research checks below).
  technology = {},
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
  virtual_signal = {
    ["signal-A"] = {},
    ["signal-B"] = {},
    ["signal-everything"] = {},
    ["signal-anything"] = {},
    ["signal-each"] = {},
  },
  -- As the game lists them (with the Quality mod: levels, and the default bonus each gives), and its
  -- hidden quality items never have.
  quality = {
    normal = { name = "normal", level = 0, default_multiplier = 1, order = "a" },
    uncommon = { name = "uncommon", level = 1, default_multiplier = 1.3, order = "b" },
    rare = { name = "rare", level = 2, default_multiplier = 1.6, order = "c" },
    epic = { name = "epic", level = 3, default_multiplier = 1.9, order = "d" },
    legendary = { name = "legendary", level = 5, default_multiplier = 2.5, order = "e" },
    ["quality-unknown"] = { name = "quality-unknown", level = 0, default_multiplier = 1, hidden = true, order = "z" },
  },
}
-- An item id's name and quality, as the game reads an ItemWithQualityID: a name alone is normal.
local function id_of(id)
  if type(id) == "table" then
    local grade = id.quality
    return id.name, type(grade) == "table" and grade.name or grade or "normal"
  end
  return id, "normal"
end
-- A stack's quality name (stacks made here without one are normal).
local function grade_of(stack)
  local grade = stack.quality
  return type(grade) == "table" and grade.name or grade or "normal"
end
-- Whether an item of quality `grade` passes an ItemFilter's quality (none: any; comparators by level,
-- as the game compares them, probed on 2.1.24).
local COMPARE = {
  ["="] = function(a, b)
    return a == b
  end,
  ["!="] = function(a, b)
    return a ~= b
  end,
  [">"] = function(a, b)
    return a > b
  end,
  ["<"] = function(a, b)
    return a < b
  end,
  [">="] = function(a, b)
    return a >= b
  end,
  ["<="] = function(a, b)
    return a <= b
  end,
}
COMPARE["≠"], COMPARE["≥"], COMPARE["≤"] = COMPARE["!="], COMPARE[">="], COMPARE["<="]
local function passes(filter, grade)
  if filter.quality == nil then
    return true
  end
  local compare = COMPARE[filter.comparator or "="]
  assert(compare, "no comparator " .. tostring(filter.comparator))
  return compare(prototypes.quality[grade].level, prototypes.quality[filter.quality].level)
end
-- An inventory's stock by quality: `contents` is keyed by name for normal, "name/quality" otherwise.
local function key_of(name, grade)
  return grade == "normal" and name or name .. "/" .. grade
end
-- Entity prototypes by type, as far as prototypes.get_entity_filtered's "type" filter is asked.
local ENTITY_TYPES =
  { ["small-biter"] = "unit", ["jatz-freighter-drone"] = "unit", ["jatz-request-depot"] = "container" }
function prototypes.get_entity_filtered(filters)
  assert(#filters == 1 and filters[1].filter == "type", "only the type filter is faked")
  local types = type(filters[1].type) == "table" and filters[1].type or { filters[1].type }
  local found = {}
  for name, kind in pairs(ENTITY_TYPES) do
    for _, wanted in ipairs(types) do
      if kind == wanted then
        found[name] = { name = name, type = kind }
      end
    end
  end
  return found
end
prototypes.item.cell =
  { name = "cell", stack_size = 50, fuel_value = 30000000, burnt_result = prototypes.item["used-cell"] }
-- None of these spoil unless a check says so (LuaItemPrototype.get_spoil_ticks is 0 then).
local function never_spoils()
  return 0
end
for _, item in pairs(prototypes.item) do
  item.get_spoil_ticks = never_spoils
end
script = { register_on_object_destroyed = function() end }

-- A depot's chest as far as deliveries read it: `contents` by key (key_of: normal items by name).
local function inventory(contents)
  local self = { contents = contents or {} }
  -- Each key's item and quality.
  local function each(visit)
    for key, count in pairs(self.contents) do
      local name, grade = key:match("^(.-)/(.+)$")
      visit(name or key, grade or "normal", count)
    end
  end
  -- An ItemWithQualityID: a name alone is normal quality, as in the game.
  function self.get_item_count(id)
    if id == nil then
      local total = 0
      each(function(_, _, count)
        total = total + count
      end)
      return total
    end
    local name, grade = id_of(id)
    return self.contents[key_of(name, grade)] or 0
  end
  -- Room for 1000 of any item, unless a check sets `room` (by key, or `room.empty` for a quality it
  -- holds none of: its empty stacks).
  function self.get_insertable_count(id)
    local name, grade = id_of(id)
    if self.room then
      return self.room[key_of(name, grade)] or self.room.empty or 0
    end
    return 1000
  end
  -- An ItemFilter table: without a quality, items of any quality match.
  function self.get_item_count_filtered(filter)
    assert(type(filter) == "table" and filter.name, "an ItemFilter table")
    local total = 0
    each(function(name, grade, count)
      if name == filter.name and passes(filter, grade) then
        total = total + count
      end
    end)
    return total
  end
  function self.get_item_quality_counts(item)
    local counts = {}
    each(function(name, grade, count)
      if (item == nil or name == item) and count > 0 then
        counts[grade] = (counts[grade] or 0) + count
      end
    end)
    return counts
  end
  function self.get_contents()
    local list = {}
    each(function(name, grade, count)
      list[#list + 1] = { name = name, quality = grade, count = count }
    end)
    return list
  end
  -- A depot's 48 slots, so #inventory (LuaInventory's length operator) counts them. Their stacks
  -- read empty: what it holds is `contents`.
  for index = 1, 48 do
    self[index] = { valid_for_read = false }
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

-- An item stack and a script inventory, as far as the dispatcher uses them. As in the game, a
-- stack holds at most its item's stack size, and stacks merge only when their item data match
-- (`health` stands for it here: health, tags, durability...). A stack of an item that spoils
-- has the tick it spoils (`spoil_tick`, 0 if it doesn't); merged stacks spoil in between.
local function stack(name, count)
  local self = { name = name, count = count or 0, valid_for_read = (count or 0) > 0, spoil_tick = 0 }
  function self.clear()
    self.name, self.count, self.valid_for_read, self.health, self.spoil_tick = nil, 0, false, nil, 0
  end
  function self.transfer_stack(from, amount)
    amount = math.min(amount or from.count, from.count)
    if
      self.valid_for_read
      and (self.name ~= from.name or self.health ~= from.health or grade_of(self) ~= grade_of(from))
    then
      return false
    end
    local item = prototypes.item[from.name]
    local moved = math.min(amount, (item and item.stack_size or math.huge) - self.count)
    if moved <= 0 then
      return false
    end
    if not self.valid_for_read then
      self.health, self.quality, self.spoil_tick = from.health, from.quality, from.spoil_tick
    elseif self.spoil_tick > 0 then
      self.spoil_tick = math.floor((self.spoil_tick * self.count + from.spoil_tick * moved) / (self.count + moved))
    end
    self.name, self.count, self.valid_for_read = from.name, self.count + moved, true
    from.count = from.count - moved
    if from.count == 0 then
      from.clear()
    end
    return moved == amount
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
  -- Of one item at one quality (an ItemWithQualityID: a name alone is normal, as in the game), or of
  -- all.
  function self.get_item_count(item)
    local total = 0
    if item == nil then
      for index = 1, size do
        total = total + self[index].count
      end
      return total
    end
    local name, grade = id_of(item)
    for index = 1, size do
      if self[index].name == name and grade_of(self[index]) == grade then
        total = total + self[index].count
      end
    end
    return total
  end
  function self.get_item_count_filtered(filter)
    assert(type(filter) == "table" and filter.name, "an ItemFilter table")
    local total = 0
    for index = 1, size do
      if self[index].name == filter.name and passes(filter, grade_of(self[index])) then
        total = total + self[index].count
      end
    end
    return total
  end
  function self.get_item_quality_counts(item)
    local counts = {}
    for index = 1, size do
      local held = self[index]
      if held.valid_for_read and (item == nil or held.name == item) then
        counts[grade_of(held)] = (counts[grade_of(held)] or 0) + held.count
      end
    end
    return counts
  end
  function self.find_item_stack(item)
    local name, grade = id_of(item)
    for index = 1, size do
      local held = self[index]
      if held.valid_for_read and held.name == name and grade_of(held) == grade then
        return held, index
      end
    end
  end
  -- A stack, or a table with a name, count and quality (normal if none).
  function self.insert(from)
    local grade = grade_of(from)
    for index = 1, size do
      local slot = self[index]
      if not slot.valid_for_read or (slot.name == from.name and grade_of(slot) == grade) then
        slot.name, slot.count, slot.valid_for_read = from.name, slot.count + from.count, true
        slot.quality = { name = grade }
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

-- The player force, as entities' `force` (a LuaForce, with its index; research is kept by it).
local PLAYER = { name = "player", index = 1 }

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
    force = PLAYER,
    force_index = 1,
    -- Its LuaQualityPrototype (normal unless made at another quality).
    quality = prototypes.quality.normal,
    get_inventory = function()
      return chest
    end,
    chest = chest,
    -- No wires (wire() below adds them), so no control behavior either.
    get_circuit_network = function()
      return nil
    end,
    get_control_behavior = function()
      return nil
    end,
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
    -- Made at a quality (a name, or a LuaQualityPrototype), normal by default, as in the game.
    local grade = parameters.quality
    drone.quality = prototypes.quality[type(grade) == "table" and grade.name or grade or "normal"]
    assert(drone.quality, "no quality " .. tostring(grade))
    surface.created[#surface.created + 1] = drone
    drone.commands = {}
    drone.commandable = {
      set_command = function(command)
        drone.commands[#drone.commands + 1] = command
      end,
    }
    drone.force = parameters.force or PLAYER
    drone.health = 500
    -- LuaControl::teleport, to a position on its own surface.
    function drone.teleport(position)
      assert(type(position) == "table" and position.x and position.y, "teleport to a MapPosition")
      drone.position = { x = position.x, y = position.y }
      return true
    end
    -- Destroyed, it answers the mod only `valid`, as in the game: reading anything else from an
    -- invalid LuaEntity is an error (start_trip read a freighter its own set_off had sent home).
    -- These checks may still look at what it was.
    function drone.destroy()
      local was = {}
      for key, value in pairs(drone) do
        was[key] = value
      end
      for key in pairs(was) do
        drone[key] = nil
      end
      drone.valid = false
      setmetatable(drone, {
        __index = function(_, key)
          if debug.getinfo(2, "S").source:find("scripts/", 1, true) then
            error("LuaEntity API call when LuaEntity was invalid: " .. tostring(key), 2)
          end
          return was[key]
        end,
      })
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
  -- Fresh modules, with no cache from an earlier check (scripts/impact.lua keeps the names of what
  -- freighters run over, scripts/research.lua the freighter's speed, read from its prototype once,
  -- scripts/fuel.lua what burns, scripts/routes.lua the freighter's shape, scripts/cargo.lua
  -- items' stack sizes, scripts/promises.lua which items spoil, and scripts/quality.lua the
  -- qualities and their item ids).
  package.loaded["scripts.research"] = nil
  package.loaded["scripts.fuel"] = nil
  package.loaded["scripts.routes"] = nil
  package.loaded["scripts.cargo"] = nil
  package.loaded["scripts.promises"] = nil
  package.loaded["scripts.quality"] = nil
  package.loaded["scripts.logistics"] = nil
  package.loaded["scripts.impact"] = nil
  local logistics = require("scripts.logistics")
  logistics.init()
  return logistics
end

-- The road between two points, for the roads a way through tunnels asks the pathfinder about
-- (scripts/tunnels.lua, plan): `leg_road(start, goal)` gives its waypoints, or nil for none. Straight
-- unless a check sets it: a check file that does hands `roads` a function returning its current one.
local leg_road_of
local function straight(_, goal)
  return { { position = goal } }
end

-- Answer every road a way through tunnels is waiting for (and those its answers ask in turn).
local function settle(logistics)
  local leg_road = leg_road_of and leg_road_of()
  for _ = 1, 50 do
    local ids = {}
    for id in pairs(storage.tunnel_leg_asks or {}) do
      ids[#ids + 1] = id
    end
    if #ids == 0 then
      return
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
      local asked = requests[id]
      logistics.on_script_path_request_finished({ id = id, path = (leg_road or straight)(asked.start, asked.goal) })
    end
  end
  error("tunnel roads still asked after 50 rounds")
end

-- tunnels.plan as a search or freighter gets it in the end, its roads measured (leg_road).
local function plan_of(logistics, from, to, road)
  local tunnels = require("scripts.tunnels")
  for _ = 1, 50 do
    local hops, length = tunnels.plan(1, from, to, road, "player", { id = "check", order = 0 })
    if hops ~= false then
      return hops, length
    end
    settle(logistics)
  end
  error("tunnel plan never decided")
end

-- Answer path request `id`: "route" (straight to the goal), "none" or "busy". A question never asked
-- (the depot remembered that road's length, and has had its answer) has nothing to answer.
local function answer(logistics, id, result)
  if not requests[id] then
    return
  end
  logistics.on_script_path_request_finished({
    id = id,
    try_again_later = result == "busy",
    path = result == "route" and { { position = requests[id].goal } } or nil,
  })
  settle(logistics)
end

-- A freighter reaches where it was driving (`result`: success unless given). After a successful
-- arrival it stands at the loading zone for a moment: that ends too, and it loads or unloads. A
-- failed command is acted on the tick after (failed_commands, from control.lua's on_tick).
local function arrive(logistics, trip, result)
  logistics.on_ai_command_completed({
    unit_number = trip.drone.unit_number,
    result = result or defines.behavior_result.success,
  })
  if result == defines.behavior_result.fail then
    logistics.failed_commands()
  end
  settle(logistics)
  if trip.service then
    logistics.on_ai_command_completed({ unit_number = trip.drone.unit_number, result = defines.behavior_result.success })
    settle(logistics)
  end
end

-- The (first) trip of a request depot, and whether it has any.
local function trip_of(depot)
  return storage.trips[next(storage.depots[depot.unit_number].trips) or 0]
end

local function has_trip(depot)
  return next(storage.depots[depot.unit_number].trips) ~= nil
end

-- The depot asks the pathfinder again rather than use the road length it remembers: for checks
-- that answer each question by hand (`answer`) and aren't about remembered roads.
local function forget_roads()
  storage.road_lengths = nil
end

-- What each trip is bringing its request depot, as filed for `need` (storage.coming), must match
-- the trips themselves: what it promised on its way out, its cargo on its way back, nothing
-- otherwise. Checked with every check below, so a change to a trip that isn't filed shows up.
-- Cargo that spoils changes by itself: its earliest spoil tick must be filed (storage.spoiling),
-- and only once that tick has come may what was filed for the depot's item differ from it.
local function coming_filed()
  if not (storage and storage.coming and storage.trips) then
    return true
  end
  local spoiling = storage.spoiling or {}
  local function due(request, item)
    local tick = spoiling[request] and spoiling[request][item]
    return tick and tick <= game.tick
  end
  local expected = {}
  for _, trip in pairs(storage.trips) do
    -- By key (scripts/quality.lua): the item's name for normal quality, "item/quality" otherwise.
    local amounts = {}
    if trip.state == "to-provider" then
      if trip.mix then
        for grade, part in pairs(trip.mix) do
          amounts[key_of(trip.item, grade)] = part
        end
      else
        amounts[trip.item] = trip.planned or 0
      end
    elseif trip.state == "to-request" then
      if trip.fluid then
        amounts[trip.item] = trip.fluid.amount
      elseif type(trip.cargo) == "table" and trip.cargo.valid then
        for grade, count in pairs(trip.cargo.get_item_quality_counts(trip.item)) do
          amounts[key_of(trip.item, grade)] = count
        end
        for index = 1, #trip.cargo do
          local cargo = trip.cargo[index]
          local filed = spoiling[trip.request] and spoiling[trip.request][trip.item]
          if cargo.name == trip.item and cargo.spoil_tick > 0 and not (filed and filed <= cargo.spoil_tick) then
            return false,
              trip.request .. " " .. trip.item .. " spoils at " .. cargo.spoil_tick .. ", filed " .. tostring(filed)
          end
        end
      end
    end
    for stock, amount in pairs(amounts) do
      if amount ~= 0 then
        local key = trip.request .. " " .. stock .. " " .. trip.key
        expected[key] = { amount = amount, request = trip.request, item = trip.item }
      end
    end
  end
  for request, items in pairs(storage.coming) do
    for stock, trips in pairs(items) do
      local item = stock:match("^(.-)/") or stock
      for key, amount in pairs(trips) do
        local id = request .. " " .. stock .. " " .. key
        local has = expected[id] and expected[id].amount
        if has ~= amount and not due(request, item) then
          return false, id .. " filed " .. amount .. ", trip has " .. tostring(has)
        end
        expected[id] = nil
      end
    end
  end
  for id, trip in pairs(expected) do
    if not due(trip.request, trip.item) then
      return false, id .. " not filed"
    end
  end
  -- The promises' kept totals (storage.promise_totals) must be their sum, each rounded up to a
  -- whole unit, with no total left where nothing is promised.
  if storage.promised and storage.promise_totals then
    local sums = {}
    for provider, items in pairs(storage.promised) do
      for item, trips in pairs(items) do
        local sum = 0
        for _, amount in pairs(trips) do
          sum = sum + math.ceil(amount)
        end
        sums[provider .. " " .. item] = sum
      end
    end
    for provider, items in pairs(storage.promise_totals) do
      for item, total in pairs(items) do
        local id = provider .. " " .. item
        if sums[id] ~= total then
          return false, "promises at " .. id .. " total " .. tostring(sums[id]) .. ", kept " .. total
        end
        sums[id] = nil
      end
    end
    for id, sum in pairs(sums) do
      if sum ~= 0 then
        return false, "promises at " .. id .. " total " .. sum .. ", none kept"
      end
    end
  end
  return true
end

-- State invariants run at every existing behavioral checkpoint, alongside the ledger invariant.
local function lifecycle_consistent()
  local movements = {
    departing = true,
    road = true,
    ["approaching-tunnel"] = true,
    ["waiting-at-tunnel"] = true,
    underground = true,
    ["exiting-tunnel"] = true,
  }
  local keys = {}
  for id, trip in pairs(storage.trips or {}) do
    if trip.lifecycle_version == 1 then
      assert(movements[trip.movement], "live trip has invalid movement")
      assert(trip.drone.unit_number == id and trip.id == id, "trip identity not rebound")
      assert(not keys[trip.key], "logical trip identity duplicated")
      keys[trip.key] = true
      local home = storage.depots[trip.request]
      assert(not home or home.trips[id], "home lost its trip")
      assert(not (trip.search and trip.service), "search overlaps depot service")
      assert(trip.fuel_check == "unchecked" or trip.fuel_check == "checked", "invalid fuel check")
      if trip.search then
        assert(trip.search.kind == "provider" or trip.search.kind == "fuel", "invalid search kind")
        assert(type(trip.search.since) == "number", "search has no timeout origin")
        assert(
          (trip.search.phase == "pending" and type(trip.search.token) == "number")
            or (trip.search.phase == "retry" and trip.search.token == nil),
          "invalid search ownership"
        )
      end
      if trip.service then
        assert(
          trip.service.kind == "loading" or trip.service.kind == "unloading" or trip.service.kind == "refueling",
          "invalid service"
        )
        assert(trip.movement == "road", "servicing away from a depot")
      end
      local in_tunnel = trip.movement == "underground"
        or trip.movement == "approaching-tunnel"
        or trip.movement == "waiting-at-tunnel"
      assert((trip.tunnel ~= nil) == in_tunnel, "tunnel payload disagrees with movement")
      assert(
        trip.searching == nil
          and trip.search_token == nil
          and trip.loading == nil
          and trip.departing == nil
          and trip.coming_out == nil
          and trip.refueled == nil
          and trip.fuel_search == nil,
        "legacy trip flags survived migration"
      )
    end
  end
end

local function check(name, condition)
  lifecycle_consistent()
  local filed, problem = coming_filed()
  if not filed then
    error("FAILED: " .. name .. ": what freighters bring is filed wrong: " .. problem, 2)
  end
  if not condition then
    error("FAILED: " .. name, 2)
  end
  print("ok   " .. name)
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

-- What a check file uses. `state` gives the surface and the path requests of the latest reset.
return {
  SETTINGS = SETTINGS,
  ENTITY_TYPES = ENTITY_TYPES,
  never_spoils = never_spoils,
  stack = stack,
  script_inventory = script_inventory,
  entity = entity,
  tank = tank,
  sprites_on = sprites_on,
  straight = straight,
  settle = settle,
  plan_of = plan_of,
  roads = function(of)
    leg_road_of = of
  end,
  answer = answer,
  arrive = arrive,
  trip_of = trip_of,
  has_trip = has_trip,
  forget_roads = forget_roads,
  check = check,
  supplied = supplied,
  trips_from = trips_from,
  reset = reset,
  state = function()
    return surface, requests
  end,
}
