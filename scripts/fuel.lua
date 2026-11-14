-- SPDX-License-Identifier: LGPL-3.0-only
-- Freighter fuel: how much a tank holds and a tile burns, what burns, filling up at a Fuel depot,
-- showing a freighter's fuel on hover, and finding a Fuel depot to fill up at. Split out of
-- scripts/logistics.lua, whose main chunk had reached Lua's limit of 200 locals (issue #69).
-- logistics.lua keeps the trips and the search (burning fuel is part of a trip's check, `burn`),
-- and hands this module the helpers it shares with it once they are all defined (fueling.install).
local fueling = {}
local lifecycle = require("scripts.trip-state")

-- scripts/logistics.lua, and its helpers, from fueling.install.
local logistics, fuel_tank, inventory, depots_at, loading_tile, new_token, ask_route, drive, end_trip, target
local RETRY_TICKS

function fueling.install(owner, shared)
  logistics = owner
  fuel_tank, inventory, depots_at = shared.fuel_tank, shared.inventory, shared.depots_at
  loading_tile, new_token, ask_route = shared.loading_tile, shared.new_token, shared.ask_route
  drive, end_trip, target = shared.drive, shared.end_trip, shared.target
  RETRY_TICKS = shared.retry_ticks
end

-- A freighter fills up before a leg unless its tank holds what the leg's road length takes, times
-- this (its path may differ from the road measured), plus this share of a full tank in reserve.
local FUEL_MARGIN = 1.25
local FUEL_RESERVE = 0.1

-- Fuel: a full tank and what a tile of driving burns, in joules (runtime settings, settings.lua).
local function fuel_capacity()
  return settings.global["jatz-freighter-fuel-capacity"].value * 1000000
end

-- Below this share of a full tank, a freighter's fuel shows yellow on hover.
local LOW_FUEL = 0.25

-- An amount of fuel (joules) as text: MJ, or GJ from 1,000 MJ (a mod's item can hold far more
-- than a tank).
local function energy_text(joules)
  if joules >= 1e9 then
    return "jatz-gui.energy-gj", string.format("%.1f", joules / 1e9)
  end
  return "jatz-gui.energy-mj", string.format("%.1f", joules / 1e6)
end
function fueling.energy_caption(joules)
  local key, amount = energy_text(joules)
  return { key, amount }
end

local function fuel_per_tile()
  return settings.global["jatz-freighter-fuel-per-tile"].value * 1000
end

-- What an item or fluid that burns gives, from game data (any mod's), or nil: its `fuel_value` and
-- the name of what it `burnt` into, if anything. Read from its prototype once per kind and name
-- (prototypes don't change while the game runs; reading one makes a new object every time).
local burnables = { item = {}, fluid = {} }
local function burnable(kind, name)
  local known = burnables[kind][name]
  if known == nil then
    local prototype = prototypes[kind][name]
    known = false
    if prototype and prototype.fuel_value > 0 then
      local burnt = kind == "item" and prototype.burnt_result
      known = { fuel_value = prototype.fuel_value, burnt = burnt and burnt.name or nil }
    end
    burnables[kind][name] = known
  end
  return known or nil
end

local function burnable_item(name)
  return burnable("item", name)
end

local function burnable_fluid(name)
  return burnable("fluid", name)
end

-- Whether a Fuel depot holds anything a freighter can fill up with: a burnable fluid in its tank,
-- or a burnable item in its chest.
local function has_fuel(depot)
  local tank = fuel_tank(depot.entity)
  local held = tank and tank.get_fluid(1)
  if held and held.amount > 0 and burnable_fluid(held.name) then
    return true
  end
  local chest = inventory(depot.entity)
  for _, item in pairs(chest.get_contents()) do
    local fuel = burnable_item(item.name)
    -- One that burns into another counts only while the depot has room for what it leaves.
    local burnt = fuel and fuel.burnt
    if fuel and (not burnt or chest.get_insertable_count({ name = burnt, quality = item.quality }) > 0) then
      return true
    end
  end
  return false
end

-- Fill a freighter's tank at a Fuel depot: burnable fluid first, then burnable items, a whole item
-- at a time (the last may fill it past full, as a burner holds the item it is burning). An item
-- that burns into another (a fuel cell into a used one) leaves that in the depot, so only as many
-- are taken as the depot has room for what they leave.
local function refuel(trip, depot)
  local capacity = fuel_capacity()
  local tank = fuel_tank(depot.entity)
  local held = tank and tank.get_fluid(1)
  local fluid = held and burnable_fluid(held.name)
  if fluid and trip.energy < capacity then
    local removed = tank.remove_fluid(1, math.min(held.amount, (capacity - trip.energy) / fluid.fuel_value))
    trip.energy = trip.energy + (removed and removed.amount or 0) * fluid.fuel_value
  end
  local chest = inventory(depot.entity)
  for index = 1, #chest do
    if trip.energy >= capacity then
      break
    end
    local stack = chest[index]
    local item = stack.valid_for_read and burnable_item(stack.name)
    if item then
      local quality = stack.quality.name
      local count = math.min(stack.count, math.ceil((capacity - trip.energy) / item.fuel_value))
      local burnt = item.burnt
      if burnt then
        count = math.min(count, chest.get_insertable_count({ name = burnt, quality = quality }))
      end
      if count > 0 then
        if count >= stack.count then
          stack.clear()
        else
          stack.count = stack.count - count
        end
        if burnt then
          chest.insert({ name = burnt, count = count, quality = quality })
        end
        trip.energy = trip.energy + count * item.fuel_value
      end
    end
  end
end

-- Show a freighter's fuel on hover, as its status: green, yellow below LOW_FUEL of a tank, red
-- once dry. Nothing while fuel is turned off.
-- Written only when what it shows changes (`trip.fuel_shown`, which names the freighter too, since
-- a repainted one is a new entity with no status yet).
-- `per_tile` and `capacity` are fuel_per_tile() and fuel_capacity(), given when the caller has read
-- them already (reading a setting makes a table each time).
local FUEL_STATUS = { label = { "jatz-gui.freighter-fuel", {}, {} } }
local function show_fuel(trip, per_tile, capacity)
  local drone = trip.drone
  if not drone.valid then
    return
  end
  local unit = drone.unit_number
  local shown = trip.fuel_shown
  if (per_tile or fuel_per_tile()) <= 0 then
    if not (shown and shown.unit == unit and shown.off) then
      drone.custom_status = nil
      shown = shown or {}
      trip.fuel_shown = shown
      shown.unit, shown.off, shown.diode = unit, true, nil
    end
    return
  end
  capacity = capacity or fuel_capacity()
  local energy = trip.energy or capacity
  local diode = energy <= 0 and "red" or energy < capacity * LOW_FUEL and "yellow" or "green"
  local held_key, held = energy_text(energy)
  local full_key, full = energy_text(capacity)
  if
    shown
    and shown.unit == unit
    and shown.diode == diode
    and shown.held_key == held_key
    and shown.held == held
    and shown.full_key == full_key
    and shown.full == full
  then
    return
  end
  -- The same tables again, filled in: what is shown changes every second or two for every freighter
  -- driving, and the game copies a status when it is written.
  shown = shown or {}
  trip.fuel_shown = shown
  shown.unit, shown.diode, shown.off = unit, diode, nil
  shown.held_key, shown.held, shown.full_key, shown.full = held_key, held, full_key, full
  local label = FUEL_STATUS.label
  FUEL_STATUS.diode = defines.entity_status_diode[diode]
  label[2][1], label[2][2], label[3][1], label[3][2] = held_key, held, full_key, full
  drone.custom_status = FUEL_STATUS
end

-- Fuel depots a freighter of `depot` could fill up at: same surface and force, road at the loading
-- zone, holding fuel, not on cooldown for this depot (no road route lately), nearest first in a
-- straight line from `from`. With `empty`, Fuel depots without fuel come too, ranked after all
-- those with fuel (rank 1): a search reaches one only when none with fuel has a road, and tells a
-- freighter at home that its road has Fuel depots, empty ones, from none at all.
local function fuel_candidates(depot, from, empty)
  local entity = depot.entity
  local found = {}
  local surface_index, force_index = entity.surface_index, entity.force_index
  local depots = storage.depots
  for unit_number in pairs(depots_at(surface_index, "fuel")) do
    local fuel = depots[unit_number]
    local candidate = fuel and fuel.entity
    if
      fuel
      and (depot.cooldowns[unit_number] or 0) <= game.tick
      and candidate.valid
      and candidate.force_index == force_index
    then
      local stocked = has_fuel(fuel)
      local position, on_road = loading_tile(candidate)
      if on_road and (stocked or empty) then
        local dx, dy = position.x - from.x, position.y - from.y
        found[#found + 1] = {
          id = unit_number,
          position = position,
          distance = math.sqrt(dx * dx + dy * dy),
          rank = stocked and 0 or 1,
        }
      end
    end
  end
  table.sort(found, function(a, b)
    if a.rank ~= b.rank then
      return a.rank < b.rank
    end
    return a.distance < b.distance or (a.distance == b.distance and a.id < b.id)
  end)
  return found
end

-- Start looking for the Fuel depot nearest by road from where a freighter stands; it waits while
-- the search runs. Returns false if there is none to look for.
local function seek_fuel(id, trip)
  lifecycle.clear_route_search(trip)
  local depot = storage.depots[trip.request]
  if not (trip.drone.valid and depot and depot.entity.valid) then
    return false
  end
  local from = trip.drone.position
  -- One still at home also looks for empty ones, so its depot can say which it is waiting for.
  local found = fuel_candidates(depot, from, (trip.movement == "departing"))
  if #found == 0 then
    return false
  end
  local search = {
    token = new_token(),
    request = trip.request,
    item = trip.item,
    from = from,
    -- Where it last arrived when the search started (see logistics.search_plan).
    origin = trip.origin,
    candidates = found,
    index = 1,
    trip = id,
    fuel = true,
  }
  lifecycle.begin_search(trip, "fuel", search.token, game.tick)
  logistics.command(trip, { type = defines.command.stop, distraction = defines.distraction.none })
  ask_route(search, depot.entity.surface, depot.entity.force)
  return true
end

-- Nowhere to fill up for this leg: go on where it was going on what it has. One that hasn't left
-- home yet and can't reach the provider on that stays home, never sent to wait at an empty Fuel
-- depot. Its depot waits for fuel in one if a road reaches an empty one (`empty_reachable`;
-- dispatch looks every second), and otherwise shows red, no Fuel depot connected by road, until
-- one is built or connected (or RETRY_TICKS pass).
local function go_without_fuel(id, trip, empty_reachable)
  lifecycle.fuel_checked(trip)
  if not trip.drone.valid then
    return end_trip(id, trip)
  end
  if (trip.movement == "departing") and trip.energy < (trip.leg or 0) * fuel_per_tile() then
    local depot = storage.depots[trip.request]
    if depot then
      local status = empty_reachable and logistics.status.no_fuel or logistics.status.no_fuel_depot
      depot.retry_at = game.tick + RETRY_TICKS
      depot.retry_status = status
      depot.status = status
    end
    return end_trip(id, trip)
  end
  drive(trip, target(trip))
end

-- Find a Fuel depot to fill up at, or go on without.
local function look_for_fuel(id, trip)
  if not seek_fuel(id, trip) then
    go_without_fuel(id, trip)
  end
end

-- Whether a freighter should fill up before a leg `length` tiles long by road: its tank holds
-- less than the leg takes (with FUEL_MARGIN) plus FUEL_RESERVE, or than a full tank if that is
-- less. Once a leg: after filling up, or finding nowhere to, it goes.
local function short_of_fuel(trip, length)
  local per_tile = fuel_per_tile()
  if trip.fuel_check == "checked" or not length or per_tile <= 0 then
    return false
  end
  local capacity = fuel_capacity()
  return trip.energy < math.min(length * per_tile * FUEL_MARGIN + capacity * FUEL_RESERVE, capacity)
end

fueling.fuel_capacity = fuel_capacity
fueling.fuel_per_tile = fuel_per_tile
fueling.burnable_fluid = burnable_fluid
fueling.has_fuel = has_fuel
fueling.refuel = refuel
fueling.show_fuel = show_fuel
fueling.fuel_candidates = fuel_candidates
fueling.go_without_fuel = go_without_fuel
fueling.look_for_fuel = look_for_fuel
fueling.short_of_fuel = short_of_fuel

return fueling
