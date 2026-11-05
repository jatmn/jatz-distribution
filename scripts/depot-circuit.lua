-- SPDX-License-Identifier: LGPL-3.0-only
-- A depot's enable/disable circuit condition, as a logistic chest has one in Factorio 2.1
-- (LuaLogisticContainerControlBehavior.circuit_condition_enabled and circuit_condition): while it
-- is set, the depot takes part in deliveries only while the condition holds. It reads one of two
-- things (its mode):
-- - "network", the default: the red and green wires, without the depot's own contents. A depot
--   sends its contents on its wires (a container's read_contents, a storage tank's send_contents,
--   both on by default), and a road network monitor on its road counts it too; a logistic chest's,
--   inserter's or assembling machine's condition would read those back, so "wood > 3000" would
--   hold with 2800 wood at another depot and 300 here. They are taken back out (`external`).
--   Without a wire the condition has no effect, as with the game's own entities.
-- - "contents": what the depot itself holds, items by quality and fluids in whole units, as it
--   would send them. No wire is needed.
--
-- A condition is { first_signal, comparator, second_signal, constant }, the game's CircuitCondition:
-- the first signal compared with the second signal, or with the constant (0 if unset). No first
-- signal never holds. "Everything" as the first signal holds when every signal on the wires does
-- (so also with none at all), "Anything" when at least one does; "Each" can't be used, as in the
-- game's own conditions, and the second signal must be an ordinary one. Red and green are added
-- together.
local depot_circuit = {}

local EVERYTHING, ANYTHING, EACH = "signal-everything", "signal-anything", "signal-each"
-- The two modes, in the order the panel lists them; nil is stored for the default, "network".
local NETWORK, CONTENTS = "network", "contents"
depot_circuit.modes = { NETWORK, CONTENTS }
depot_circuit.network, depot_circuit.contents = NETWORK, CONTENTS
local WIRES = { red = defines.wire_connector_id.circuit_red, green = defines.wire_connector_id.circuit_green }
-- The comparators in the order the game's condition editor lists them; "≥", "≤" and "≠" are how
-- the game writes them back (it also accepts ">=", "<=" and "!=").
depot_circuit.comparators = { "<", ">", "=", "≥", "≤", "≠" }
local ALIASES = { [">="] = "≥", ["<="] = "≤", ["!="] = "≠" }
local COMPARE = {
  ["<"] = function(a, b)
    return a < b
  end,
  [">"] = function(a, b)
    return a > b
  end,
  ["="] = function(a, b)
    return a == b
  end,
  ["≥"] = function(a, b)
    return a >= b
  end,
  ["≤"] = function(a, b)
    return a <= b
  end,
  ["≠"] = function(a, b)
    return a ~= b
  end,
}
local INT_MIN, INT_MAX = -2147483648, 2147483647
-- Each signal type, and where `prototypes` lists that type's prototypes.
local SIGNAL_TYPES = {
  item = "item",
  fluid = "fluid",
  virtual = "virtual_signal",
  entity = "entity",
  recipe = "recipe",
  ["space-location"] = "space_location",
  ["asteroid-chunk"] = "asteroid_chunk",
  quality = "quality",
}

-- A copy of a SignalID that names a signal the game has, or nil. The game reads item signals back
-- without a type; they are stored with one.
local function signal_id(signal)
  if type(signal) ~= "table" or type(signal.name) ~= "string" then
    return nil
  end
  local kind = signal.type or "item"
  local group = SIGNAL_TYPES[kind]
  if not (group and prototypes[group] and prototypes[group][signal.name]) then
    return nil
  end
  if signal.quality ~= nil and not (type(signal.quality) == "string" and prototypes.quality[signal.quality]) then
    return nil
  end
  return { type = kind, name = signal.name, quality = signal.quality }
end

local function special(signal)
  return signal and signal.type == "virtual" and signal.name or nil
end
depot_circuit.special = special

-- A well-formed copy of a condition (from the panel, a blueprint tag or another mod), or nil if
-- it isn't a table. Anything unusable in it is dropped: an unknown signal, "Each", a special
-- second signal, a comparator the game doesn't have, a constant that isn't a whole int32.
function depot_circuit.condition(condition)
  if type(condition) ~= "table" then
    return nil
  end
  local first = signal_id(condition.first_signal)
  if special(first) == EACH then
    first = nil
  end
  local second = signal_id(condition.second_signal)
  if special(second) == EVERYTHING or special(second) == ANYTHING or special(second) == EACH then
    second = nil
  end
  local comparator = ALIASES[condition.comparator] or condition.comparator
  local constant = condition.constant
  if type(constant) ~= "number" or constant ~= constant then
    constant = nil
  else
    constant = math.max(INT_MIN, math.min(INT_MAX, math.floor(constant)))
  end
  return {
    first_signal = first,
    comparator = COMPARE[comparator] and comparator or "<",
    second_signal = second,
    constant = constant,
  }
end

-- A mode as stored: nil for "network", "contents" for the other; false for anything else.
function depot_circuit.mode(mode)
  if mode == nil or mode == NETWORK then
    return nil
  end
  return mode == CONTENTS and CONTENTS or false
end

-- The key a signal is counted under: type, name and quality, as the game fills them in (an item
-- signal read back has no type, and a signal with no quality is normal).
local function key(signal)
  return (signal.type or "item") .. "/" .. signal.name .. "/" .. (signal.quality or "normal")
end
depot_circuit.key = key

-- The red and green circuit networks wired to an entity (none, one or two), with their colour.
local function networks(entity)
  local found = {}
  for _, colour in ipairs({ "red", "green" }) do
    local network = entity.get_circuit_network(WIRES[colour])
    if network then
      found[#found + 1] = { network = network, colour = colour }
    end
  end
  return found
end

-- Whether any red or green wire reaches the entity.
function depot_circuit.connected(entity)
  return #networks(entity) > 0
end

-- What the entity itself put on its `colour` wire as its contents, as signal counts by key, from
-- `own` (see allows): own.sent() while a container reads its contents or a storage tank sends
-- them, own.segment() (its whole pipe segment's fluid) while a tank sends that, nothing when it
-- sends none or not on that colour. Entities of other kinds (a Mining Drones mining depot) aren't
-- worked out: nothing.
local function sent(entity, colour, own)
  local behavior = entity.get_control_behavior()
  if not behavior then
    return nil
  end
  local selection = behavior.output_networks
  if selection and selection[colour] == false then
    return nil
  end
  local kind = defines.control_behavior.type
  if behavior.type == kind.container then
    return behavior.read_contents and own.sent() or nil
  elseif behavior.type == kind.single_fluid_box then
    local modes = defines.control_behavior.single_fluid_box.exclusive_mode
    local mode = behavior.circuit_exclusive_mode_of_operation
    if mode == modes.send_contents then
      return own.sent()
    elseif mode == modes.send_segment_contents then
      return own.segment()
    end
  end
  return nil
end

-- A reading: the signals a condition is compared on, as the game's own conditions see them.
-- value(signal) gives one signal's value, and all() every signal that isn't zero, as
-- { key = depot_circuit.key, value = value }, so a wildcard can leave out its right-hand signal.
-- Values are signed 32-bit, as on the wires: red and green (and what is taken out of them) add up
-- with the game's wrap-around (`wrap`), before zeros are dropped and before anything is compared.

-- A sum as a signed 32-bit signal value: wrapped around, as the game adds signals.
local function wrap(value)
  value = value % 4294967296
  return value >= 2147483648 and value - 4294967296 or value
end
depot_circuit.wrap = wrap

-- The non-zero signals of `totals` (values by key) in `order`, wrapped.
local function nonzero(totals, order)
  local signals = {}
  for _, signal_key in ipairs(order) do
    local value = wrap(totals[signal_key])
    if value ~= 0 then
      signals[#signals + 1] = { key = signal_key, value = value }
    end
  end
  return signals
end

-- The depot's own contents (`own`, counts by key).
local function contents_reading(own)
  return {
    value = function(signal)
      return wrap(own[key(signal)] or 0)
    end,
    all = function()
      local order = {}
      for signal_key in pairs(own) do
        order[#order + 1] = signal_key
      end
      table.sort(order)
      return nonzero(own, order)
    end,
  }
end

-- The wires in `found`, red and green added together, each less what the depot put on it: its own
-- contents (`sent`, from `own`), and what `counted(network)` says road network monitors on that
-- network counted for it (a list of counts by key).
local function external(entity, found, own, counted)
  local minus = {}
  for index, wire in ipairs(found) do
    local list = {}
    local mine = sent(entity, wire.colour, own)
    if mine then
      list[#list + 1] = mine
    end
    for _, counts in ipairs(counted and counted(wire.network) or {}) do
      list[#list + 1] = counts
    end
    minus[index] = list
  end
  local function less(index, signal_key)
    local total = 0
    for _, counts in ipairs(minus[index]) do
      total = total + (counts[signal_key] or 0)
    end
    return total
  end
  return {
    value = function(signal)
      local total = 0
      for index, wire in ipairs(found) do
        total = total + wire.network.get_signal(signal) - less(index, key(signal))
      end
      return wrap(total)
    end,
    all = function()
      local totals, order = {}, {}
      local function add(signal_key, count)
        if not totals[signal_key] then
          order[#order + 1] = signal_key
          totals[signal_key] = 0
        end
        totals[signal_key] = totals[signal_key] + count
      end
      for index, wire in ipairs(found) do
        for _, signal in ipairs(wire.network.signals or {}) do
          add(key(signal.signal), signal.count)
        end
        for _, counts in ipairs(minus[index]) do
          for signal_key, count in pairs(counts) do
            add(signal_key, -count)
          end
        end
      end
      return nonzero(totals, order)
    end,
  }
end

-- Whether a condition holds on a reading.
local function fulfilled(reading, condition)
  local first = condition.first_signal
  if not first then
    return false
  end
  local compare = COMPARE[condition.comparator] or COMPARE["<"]
  local second = condition.second_signal
  local right = second and reading.value(second) or (condition.constant or 0)
  local kind = special(first)
  if kind == EVERYTHING or kind == ANYTHING then
    -- As in the game, a wildcard compared with a signal leaves that signal out of its inputs: with
    -- only B on the wires, "Anything >= B" doesn't hold and "Everything > B" does.
    local excluded = second and key(second)
    local any = false
    for _, signal in ipairs(reading.all()) do
      if signal.key ~= excluded then
        if compare(signal.value, right) then
          any = true
        elseif kind == EVERYTHING then
          return false
        end
      end
    end
    return kind == EVERYTHING or any
  end
  return compare(reading.value(first), right)
end

-- Whether a depot with this setting may take part in deliveries now: always unless the condition
-- is in effect; then only while `condition` holds. `own` gives the depot's contents as counts by
-- key: own.held() what it holds now, for the "contents" reading; own.sent() and own.segment() what
-- it put on its wires (its contents, its pipe segment's fluid), for "network" to take back out.
-- Those must be what the wires carry: their signals are what every entity sent at the last circuit
-- update, so a transfer since (earlier this tick) is not on them yet. `counted(network)` gives
-- what road network monitors on that network counted for it.
function depot_circuit.allows(entity, enabled, condition, mode, own, counted)
  if not enabled then
    return true
  end
  if mode == CONTENTS then
    return fulfilled(contents_reading(own.held()), condition or {})
  end
  local found = networks(entity)
  if #found == 0 then
    return true
  end
  local cache = {}
  local once = {}
  for _, name in ipairs({ "sent", "segment" }) do
    once[name] = function()
      cache[name] = cache[name] or own[name]()
      return cache[name]
    end
  end
  return fulfilled(external(entity, found, once, counted), condition or {})
end

return depot_circuit
