-- SPDX-License-Identifier: LGPL-3.0-only
-- A depot's enable/disable circuit condition, as a logistic chest has one in Factorio 2.1
-- (LuaLogisticContainerControlBehavior.circuit_condition_enabled and circuit_condition): while it
-- is set, and the depot has a red or green wire, the depot takes part in deliveries only while the
-- condition holds. Without a wire the condition has no effect, as with the game's own entities.
--
-- A condition is { first_signal, comparator, second_signal, constant }, the game's CircuitCondition:
-- the first signal compared with the second signal, or with the constant (0 if unset). No first
-- signal never holds. "Everything" as the first signal holds when every signal on the wires does
-- (so also with none at all), "Anything" when at least one does; "Each" can't be used, as in the
-- game's own conditions, and the second signal must be an ordinary one. Red and green are added
-- together.
local depot_circuit = {}

local EVERYTHING, ANYTHING, EACH = "signal-everything", "signal-anything", "signal-each"
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

-- The red and green circuit networks wired to an entity (none, one or two).
local function networks(entity)
  local found = {}
  for _, wire in ipairs({ defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green }) do
    local network = entity.get_circuit_network(wire)
    if network then
      found[#found + 1] = network
    end
  end
  return found
end

-- Whether any red or green wire reaches the entity.
function depot_circuit.connected(entity)
  return #networks(entity) > 0
end

local function value(found, signal)
  local total = 0
  for _, network in ipairs(found) do
    total = total + network.get_signal(signal)
  end
  return total
end

-- Every signal on the wires, red and green added together, without the zeros.
local function all_signals(found)
  local totals, order = {}, {}
  for _, network in ipairs(found) do
    for _, signal in ipairs(network.signals or {}) do
      local id = signal.signal
      local key = (id.type or "item") .. "/" .. id.name .. "/" .. (id.quality or "normal")
      if not totals[key] then
        order[#order + 1] = key
        totals[key] = 0
      end
      totals[key] = totals[key] + signal.count
    end
  end
  local values = {}
  for _, key in ipairs(order) do
    if totals[key] ~= 0 then
      values[#values + 1] = totals[key]
    end
  end
  return values
end

-- Whether a condition holds on these networks.
local function fulfilled(found, condition)
  local first = condition.first_signal
  if not first then
    return false
  end
  local compare = COMPARE[condition.comparator] or COMPARE["<"]
  local right = condition.second_signal and value(found, condition.second_signal) or (condition.constant or 0)
  local kind = special(first)
  if kind == EVERYTHING or kind == ANYTHING then
    local any = false
    for _, left in ipairs(all_signals(found)) do
      if compare(left, right) then
        any = true
      elseif kind == EVERYTHING then
        return false
      end
    end
    return kind == EVERYTHING or any
  end
  return compare(value(found, first), right)
end

-- Whether a depot with this setting may take part in deliveries now: always unless `enabled` is
-- set and the entity has a wire; then only while `condition` holds.
function depot_circuit.allows(entity, enabled, condition)
  if not enabled then
    return true
  end
  local found = networks(entity)
  if #found == 0 then
    return true
  end
  return fulfilled(found, condition or {})
end

return depot_circuit
