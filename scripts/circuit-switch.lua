-- SPDX-License-Identifier: LGPL-3.0-only
-- Depots switched on and off by their circuit condition: what a depot sends and holds as signals,
-- sampling them each tick, whether its condition holds (with or without the promises made there),
-- showing it switched off, and its circuit settings. The conditions themselves are
-- scripts/depot-circuit.lua's. Split out of scripts/logistics.lua so its main chunk stays well below
-- Lua's limit of 200 locals (issue #69). logistics.lua keeps the entry points
-- (`logistics.enabled`, `logistics.set_circuit` and the others) and hands this module the helpers
-- it shares with it once they are defined (switching.install).
local depot_circuit = require("scripts.depot-circuit")
local quality = require("scripts.quality")

local switching = {}

-- scripts/logistics.lua, and its helpers, from switching.install.
local logistics, inventory, file_promises

function switching.install(owner, shared)
  logistics = owner
  inventory, file_promises = shared.inventory, shared.file_promises
end

-- What a depot holds, as circuit signal counts by key (depot_circuit.key): its items by quality,
-- or its fluids in whole units, as a container or storage tank sends them.
local function own_signals(depot)
  local counts = {}
  local entity = depot.entity
  if depot.fluid then
    for name, amount in pairs(entity.get_fluid_contents()) do
      local key = depot_circuit.key({ type = "fluid", name = name })
      counts[key] = (counts[key] or 0) + math.floor(amount)
    end
    return counts
  end
  local contents = inventory(entity)
  for _, item in ipairs(contents and contents.get_contents() or {}) do
    local key = depot_circuit.key({ type = "item", name = item.name, quality = item.quality })
    counts[key] = (counts[key] or 0) + item.count
  end
  return counts
end

-- A storage tank's whole pipe segment's fluid, in whole units, as it sends it in that mode.
local function segment_signals(depot)
  local fluid = depot.fluid and depot.entity.get_fluid_segment_fluid(1)
  return fluid and { [depot_circuit.key({ type = "fluid", name = fluid.name })] = math.floor(fluid.amount) } or {}
end

-- A depot whose condition reads the circuit network takes its own contents back out of what the
-- wires carry. Their signals are what each entity sent at the previous tick's circuit update, and
-- its contents can change before it is read this tick (inserters, robots, freighters, scripts:
-- 700 wood taken out of 1000 still left 1000 on the wire, probed on 2.1.24). So its contents are
-- sampled at the start of every tick, before anything moves (control.lua's on_tick, which the game
-- raises before on_nth_tick and the entity updates), and that sample is what it takes out all tick
-- (`circuit_sample`). Only depots reading the network are sampled (`storage.circuit_watch`, kept
-- by set_circuit and on load). Changes the game applies before any mod's on_tick (a player's own
-- transfers) and those of mods running earlier in the tick can't be told apart: for that one tick
-- the sample already holds them.
local function watch(depot)
  storage.circuit_watch = storage.circuit_watch or {}
  storage.circuit_watch[depot.entity.unit_number] = (depot.circuit_enabled and not depot.circuit_mode) or nil
  if not storage.circuit_watch[depot.entity.unit_number] then
    depot.circuit_sample = nil
  end
end

function switching.sample_circuits()
  local watched = storage.circuit_watch
  if not watched then
    return
  end
  for unit_number in pairs(watched) do
    local depot = storage.depots[unit_number]
    if depot and depot.entity.valid and depot.circuit_enabled and not depot.circuit_mode then
      depot.circuit_sample = { tick = game.tick, sent = own_signals(depot), segment = segment_signals(depot) }
    else
      watched[unit_number] = nil
    end
  end
end

-- Whether a depot takes part in deliveries now: its circuit condition holds, or isn't in effect.
-- With `claims`, a depot reading its own contents must also still hold it once freighters on their
-- way there have loaded what they promised: `true` for every promise filed there (whether to send
-- it another freighter, so once those already sent would take it below its condition no more go),
-- or a table of amounts by key (logistics.claims_ahead: the promises made before a freighter's,
-- for whether that one still gets its load). Both, not the second instead of the first: a
-- condition that taking items switches on (only while below some amount) can hold with promises
-- taken and not now, and a switched-off depot gives nothing. Without it, what it holds now: its
-- status, its panel, road network monitors. `held`: its own_signals, if the caller has read them
-- already this tick (check_depot reads them once for its status and its promises).
local function enabled(depot, claims, held)
  if not depot.circuit_enabled then
    -- No condition in effect (most depots): nothing to read.
    return true
  end
  local counted = logistics.monitor_counts
  -- What it put on its wires: this tick's sample, or (not sampled this tick: its condition was set
  -- since) what it holds now.
  local sample = depot.circuit_sample
  sample = sample and sample.tick == game.tick and sample or nil
  local live = held
  if
    not depot_circuit.allows(depot.entity, depot.circuit_enabled, depot.circuit_condition, depot.circuit_mode, {
      held = function()
        live = live or own_signals(depot)
        return live
      end,
      sent = function()
        return sample and sample.sent or own_signals(depot)
      end,
      segment = function()
        return sample and sample.segment or segment_signals(depot)
      end,
    }, counted and function(network)
      return counted(depot.entity.unit_number, network)
    end)
  then
    return false
  end
  if not claims or depot.circuit_mode ~= depot_circuit.contents then
    -- Read from the network, the condition leaves the depot's own contents out: promises don't
    -- change it.
    return true
  end
  if claims == true then
    claims = logistics.claims_ahead(depot.entity.unit_number)
  end
  return logistics.holds_less(depot, claims, live or own_signals(depot))
end
switching.enabled = enabled

-- Whether a depot's condition, reading its own contents, holds with `claims` (amounts by key, an
-- item at one quality or a fluid: scripts/quality.lua) taken out of `live` (own_signals, read once
-- by the caller; not changed): freighters load the qualities promised, each its own signal.
-- Promises of fluid can be fractions: taken from the exact amount, then floored once, as the tank
-- would send what is left (own_signals has floored it already). (A field, not a local: this file
-- has as many locals as Lua allows.)
function switching.holds_less(depot, claims, live)
  if next(claims) == nil then
    return true
  end
  local counts = {}
  for signal, count in pairs(live) do
    counts[signal] = count
  end
  for item, claimed in pairs(claims) do
    local signal = quality.signal(item, depot.fluid)
    if depot.fluid then
      counts[signal] = math.floor(depot.entity.get_fluid_count(item) - claimed)
    else
      counts[signal] = (counts[signal] or 0) - claimed
    end
  end
  return depot_circuit.allows(depot.entity, true, depot.circuit_condition, depot.circuit_mode, {
    held = function()
      return counts
    end,
  })
end

-- The promises filed at a provider (unit number) made before `trip`'s (logistics.ahead), or all of
-- them without one: amounts by key (an item at one quality, or a fluid). All of an item depot's are their kept totals
-- (storage.promise_totals, exact for items; not to be changed): `enabled(depot, true)` asks for
-- them whenever a search looks at a provider or ends there, and adding them up afresh each time
-- made many searches ending at one busy provider cost the square of its promises (Copilot's review
-- of be24d17). Fluid's are added up afresh, as fractions.
function switching.claims_ahead(unit_number, trip)
  local provider = not trip and storage.depots[unit_number]
  if provider and not provider.fluid then
    if not (storage.promised and storage.promise_totals) then
      file_promises()
    end
    return storage.promise_totals[unit_number] or {}
  end
  local claims = {}
  for item, trips in pairs(storage.promised and storage.promised[unit_number] or {}) do
    local claimed = 0
    for key, amount in pairs(trips) do
      if not trip or logistics.ahead(key, trip) then
        claimed = claimed + amount
      end
    end
    claims[item] = claimed
  end
  return claims
end

-- The entity info panel (hover) shows a depot's own status, "Normal" for a chest. While its
-- circuit condition switches it off, it shows that instead (LuaEntity.custom_status, a red light),
-- as the game shows an entity its circuit condition disabled; switched on, its own status again.
-- Written only when it changes (`depot.shown_off`): once a second, and when the setting changes.
local SWITCHED_OFF = { diode = defines.entity_status_diode.red, label = { "jatz-circuit-status.entity-off" } }
local function show_switched(depot, held)
  local off = (depot.circuit_enabled and not enabled(depot, nil, held)) or nil
  if depot.shown_off ~= off and depot.entity.valid then
    depot.entity.custom_status = off and SWITCHED_OFF or nil
    depot.shown_off = off
  end
end

-- A provider, request or buffer depot (item or liquid) by its entity, or nil: the depots that have
-- a circuit condition. Fuel depots are registered too, but freighters refuel there whatever its
-- wires say, so they have none.
local function delivery_depot(entity)
  local depot = entity and entity.valid and entity.unit_number and storage.depots and storage.depots[entity.unit_number]
  return depot and depot.role ~= "fuel" and depot or nil
end

-- A delivery depot's circuit settings: { enabled, condition, mode, connected, fulfilled }, where
-- `enabled` says the condition is ticked, `mode` what it reads ("network" or "contents"),
-- `connected` that a red or green wire reaches the depot, and `fulfilled` that it takes part in
-- deliveries now. Nil for anything else.
function switching.get_circuit(entity)
  local depot = delivery_depot(entity)
  if not depot then
    return nil
  end
  return {
    enabled = depot.circuit_enabled == true,
    condition = depot_circuit.condition(depot.circuit_condition or {}),
    mode = depot.circuit_mode or depot_circuit.network,
    connected = depot_circuit.connected(entity),
    fulfilled = enabled(depot),
  }
end

-- Set whether a delivery depot's circuit condition is in effect, and (unless nil) the condition
-- and what it reads ("network" or "contents"). Returns false, changing nothing, for anything else,
-- a condition that isn't a table or another mode.
function switching.set_circuit(entity, enable, condition, mode)
  local depot = delivery_depot(entity)
  local stored = depot_circuit.mode(mode)
  if not depot or (condition ~= nil and type(condition) ~= "table") or stored == false then
    return false
  end
  depot.circuit_enabled = enable == true
  if condition ~= nil then
    depot.circuit_condition = depot_circuit.condition(condition)
  end
  if mode ~= nil then
    depot.circuit_mode = stored
  end
  watch(depot)
  show_switched(depot)
  return true
end

switching.own_signals = own_signals
switching.watch = watch
switching.show_switched = show_switched
switching.delivery_depot = delivery_depot

return switching
