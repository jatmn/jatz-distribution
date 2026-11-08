-- SPDX-License-Identifier: LGPL-3.0-only
-- What freighters have promised to load at providers and are bringing to request depots, filed as
-- trips change (storage.promised, storage.coming, storage.spoiling), and a provider's stock not yet
-- promised. Split out of scripts/logistics.lua so its main chunk stays well below Lua's limit of
-- 200 locals (issue #69). logistics.lua keeps the trips that file them, and hands this module the
-- helpers it shares with it once they are defined (ledger.install).
local ledger = {}

-- scripts/logistics.lua's helpers, from ledger.install.
local inventory, trips_of, upgrade, TO_PROVIDER, TO_REQUEST

function ledger.install(_, shared)
  inventory, trips_of, upgrade = shared.inventory, shared.trips_of, shared.upgrade
  TO_PROVIDER, TO_REQUEST = shared.to_provider, shared.to_request
end

-- A trip's cargo: item stacks in a script inventory (`trip.cargo`), or for a liquid depot's trip a
-- fluid (`trip.fluid`: { amount, temperature }; fluids have no item data to keep).
local function cargo_amount(trip)
  if trip.fluid then
    return trip.fluid.amount
  end
  return trip.cargo and trip.cargo.valid and trip.cargo.get_item_count(trip.item) or 0
end

-- What a trip will bring: what it promised to load while on its way out, its cargo on the way back.
local function bringing(trip)
  if trip.state == TO_PROVIDER then
    return trip.planned or 0
  elseif trip.state == TO_REQUEST then
    return cargo_amount(trip)
  end
  return 0
end

-- The tick from which a returning trip's cargo of its item may have spoiled: its stacks' earliest
-- spoil_tick, or nil if none can. The game spoils a whole stack at once, just after that tick,
-- inside the cargo inventory and with no event.
local spoils_at
do
  -- Whether an item spoils, by name (prototype data: Lua only, built again after a load).
  local spoils = {}
  function spoils_at(trip)
    if trip.state ~= TO_REQUEST or trip.fluid then
      return nil
    end
    local item = trip.item
    if spoils[item] == nil then
      local prototype = prototypes.item[item]
      spoils[item] = prototype ~= nil and prototype.get_spoil_ticks() > 0
    end
    if not spoils[item] then
      return nil
    end
    local cargo = trip.cargo
    if not (cargo and cargo.valid) then
      return nil
    end
    local first
    for index = 1, #cargo do
      local stack = cargo[index]
      if stack.valid_for_read and stack.name == item then
        local tick = stack.spoil_tick
        if tick > 0 and (not first or tick < first) then
          first = tick
        end
      end
    end
    return first
  end
end

-- What a request depot's freighters are bringing, filed by `promise` as their state, promise or
-- cargo changes: storage.coming[request depot unit_number][item][trip key] = amount (only
-- amounts above 0), and each trip records the amount it has filed (`trip.coming`; a trip's depot
-- and item never change). So a depot's need is read without looking at each of its trips and
-- their cargo. Cargo that spoils changes with no trip change, so the earliest tick a depot's
-- filed cargo of an item may spoil is filed too (storage.spoiling[request depot][item] = tick),
-- and `committed` files that depot's trips for the item again once it comes (`file_spoiled`).
local file_promises
local function file_coming(trip, ended)
  local amount = not ended and bringing(trip) or 0
  local spoil_tick = amount ~= 0 and spoils_at(trip)
  if spoil_tick then
    local spoiling = storage.spoiling
    local items = spoiling[trip.request]
    if not items then
      items = {}
      spoiling[trip.request] = items
    end
    local due = items[trip.item]
    if not due or spoil_tick < due then
      items[trip.item] = spoil_tick
    end
  end
  if (trip.coming or 0) == amount then
    return
  end
  local coming = storage.coming
  local items = coming[trip.request]
  if amount ~= 0 then
    if not items then
      items = {}
      coming[trip.request] = items
    end
    local trips = items[trip.item]
    if not trips then
      trips = {}
      items[trip.item] = trips
    end
    trips[trip.key] = amount
    trip.coming = amount
    return
  end
  local trips = items and items[trip.item]
  if trips then
    trips[trip.key] = nil
    if next(trips) == nil then
      items[trip.item] = nil
      if next(items) == nil then
        coming[trip.request] = nil
      end
      -- Nothing of the item is coming: no cargo of it left to spoil.
      local spoiling = storage.spoiling[trip.request]
      if spoiling then
        spoiling[trip.item] = nil
        if next(spoiling) == nil then
          storage.spoiling[trip.request] = nil
        end
      end
    end
  end
  trip.coming = nil
end

-- What a request depot's freighters, except trip `except` (by id), are bringing of the item it
-- robot_requests. Trips for an item the depot no longer asks for bring nothing it needs.
local committed
do
  -- File a request depot's trips bringing `item` again from their cargo, as some of it may have
  -- spoiled: from the tick storage.spoiling holds for it (a stack is still there on its
  -- spoil_tick and gone the tick after, so it may be filed again on both). Each trip files its
  -- next spoil tick.
  local function file_spoiled(depot, item)
    local unit = depot.entity.unit_number
    local items = storage.spoiling[unit]
    items[item] = nil
    if next(items) == nil then
      storage.spoiling[unit] = nil
    end
    for id in pairs(trips_of(depot)) do
      local trip = storage.trips[id]
      if trip and trip.item == item then
        file_coming(trip)
      end
    end
  end

  function committed(depot, except)
    if not (storage.coming and storage.spoiling) then
      file_promises()
    end
    local item = depot.request and depot.request.item
    local spoiling = item and storage.spoiling[depot.entity.unit_number]
    local due = spoiling and spoiling[item]
    if due and game.tick >= due then
      file_spoiled(depot, item)
    end
    local items = item and storage.coming[depot.entity.unit_number]
    local trips = items and items[item]
    if not trips then
      return 0
    end
    local skipped = except and storage.trips[except]
    skipped = skipped and skipped.key
    local total = 0
    for key, amount in pairs(trips) do
      if key ~= skipped then
        total = total + amount
      end
    end
    return total
  end
end

-- What freighters on their way to a provider have promised to load there:
-- storage.promised[provider unit_number][item][trip key] = amount, for every trip driving out
-- (TO_PROVIDER) with a promise, except one that gave up on its provider and is looking for another
-- (`trip.passed`, logistics.give_up): that stock is free again at once. Each trip records where its
-- promise is filed (`trip.promise`), and `promise` files it again whenever its provider, state,
-- promise or `passed` changes, so a provider's
-- unpromised stock is read without looking at every trip in the game. Their total by provider and
-- item is kept with them (storage.promise_totals[provider unit_number][item], each promise rounded
-- up to a whole unit, so it is exact for items and never less than the promises for fluid): an item
-- provider's unpromised stock, and whether a provider's stock covers every promise there, are then
-- read without looking at each promise (Pullfrog's review of feca8c7). A trip's key is the
-- unit_number of the freighter it set off with (`trip.key`), which stays the same when it is
-- repainted. With `ended`, the trip is over and its promise goes. What it is bringing its request
-- depot is filed again too (`file_coming`), so call it whenever that may have changed: its state,
-- promise or cargo.
local function promise(trip, ended)
  if not (storage.promised and storage.promise_totals and storage.coming and storage.spoiling and trip.key) then
    -- A save from before promises were filed: file every trip's (this one's too, if still out).
    return file_promises()
  end
  file_coming(trip, ended)
  local filed = trip.promise
  local amount = not ended and trip.state == TO_PROVIDER and not trip.passed and trip.planned or 0
  if filed and filed.provider == trip.provider and filed.amount == amount then
    return
  end
  local promised, totals = storage.promised, storage.promise_totals
  if filed then
    local items = promised[filed.provider]
    local trips = items and items[trip.item]
    if trips then
      trips[trip.key] = nil
      local sums = totals[filed.provider]
      local total = sums[trip.item] - math.ceil(filed.amount)
      sums[trip.item] = total ~= 0 and total or nil
      if next(trips) == nil then
        items[trip.item] = nil
        if next(items) == nil then
          promised[filed.provider] = nil
          totals[filed.provider] = nil
        end
      end
    end
  end
  trip.promise = nil
  if amount ~= 0 and trip.provider then
    local items = promised[trip.provider] or {}
    promised[trip.provider] = items
    local trips = items[trip.item] or {}
    items[trip.item] = trips
    trips[trip.key] = amount
    local sums = totals[trip.provider] or {}
    totals[trip.provider] = sums
    sums[trip.item] = (sums[trip.item] or 0) + math.ceil(amount)
    trip.promise = { provider = trip.provider, amount = amount }
  end
end

-- File every trip's promise, and what it is bringing, afresh: on first use in a save from before
-- they were filed, and after trips were checked against the game as loaded (add_all).
function file_promises()
  storage.promised, storage.promise_totals, storage.coming, storage.spoiling = {}, {}, {}, {}
  for id, trip in pairs(storage.trips) do
    trip.key = trip.key or id
    trip.promise, trip.coming = nil, nil
    -- (Its cargo is read: one from the first version carried a plain count.)
    promise(upgrade(trip))
  end
end

-- Providers' bound get_item_count, by their inventory: Lua only, built again after a load.
local stock_counters = setmetatable({}, { __mode = "k" })

-- How much of `item` a provider has that no freighter on its way there has promised to load, or with
-- `gross`, how much it has.
local function available(provider, item, gross)
  local count
  if provider.fluid then
    count = provider.entity.get_fluid_count(item)
  else
    -- Its item inventory, kept (reading it from the entity makes a new object every time), and its
    -- get_item_count bound once (a method read off an object is a new function every time).
    local held = provider.stock_inventory
    if not (held and held.valid) then
      held = inventory(provider.entity)
      provider.stock_inventory = held
    end
    local counter = stock_counters[held]
    if not counter then
      counter = held.get_item_count
      stock_counters[held] = counter
    end
    count = counter(item)
  end
  if gross then
    return count
  end
  if not (storage.promised and storage.promise_totals) then
    file_promises()
  end
  local unit_number = provider.entity.unit_number
  if not provider.fluid then
    -- Whole items: their kept total is exact.
    local totals = storage.promise_totals[unit_number]
    return count - (totals and totals[item] or 0)
  end
  -- Fluid promises can be fractions: added up afresh, as exact as they are.
  local items = storage.promised[unit_number]
  for _, amount in pairs(items and items[item] or {}) do
    count = count - amount
  end
  return count
end

ledger.file_promises = file_promises
ledger.committed = committed
ledger.promise = promise
ledger.available = available

return ledger
