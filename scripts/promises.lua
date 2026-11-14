-- SPDX-License-Identifier: LGPL-3.0-only
-- What freighters have promised to load at providers and are bringing to request depots, filed as
-- trips change (storage.promised, storage.coming, storage.spoiling), and a provider's stock not yet
-- promised. Split out of scripts/logistics.lua so its main chunk stays well below Lua's limit of
-- 200 locals (issue #69). logistics.lua keeps the trips that file them, and hands this module the
-- helpers it shares with it once they are defined (ledger.install).
local quality = require("scripts.quality")
-- Item ids by key, made by quality.id: read straight from the table where it is hot (available).
local IDS = quality.ids

local ledger = {}

-- scripts/logistics.lua's helpers, from ledger.install.
local inventory, trips_of, upgrade, TO_PROVIDER, TO_REQUEST

function ledger.install(_, shared)
  inventory, trips_of, upgrade = shared.inventory, shared.trips_of, shared.upgrade
  TO_PROVIDER, TO_REQUEST = shared.to_provider, shared.to_request
end

-- Amounts by key (scripts/quality.lua: the item's name for normal quality, "item/quality"
-- otherwise, a fluid's name), as promises and what trips bring are filed. A trip plans `amount` of
-- its item: of the qualities in `trip.mix` (quality -> amount, adding up to it), or, with no mix (a
-- trip for normal quality, a fluid's, or one from before quality), all normal. Nil for nothing.
local function parts_of(trip, amount)
  if not amount or amount <= 0 then
    return nil
  end
  if trip.fluid or not trip.mix then
    return { [trip.item] = amount }
  end
  local parts
  for grade, part in pairs(trip.mix) do
    if part > 0 then
      parts = parts or {}
      parts[quality.key(trip.item, grade)] = part
    end
  end
  return parts
end
ledger.parts_of = parts_of

-- A trip's cargo by key: its item stacks by quality in a script inventory (`trip.cargo`), or for a
-- liquid depot's trip a fluid (`trip.fluid`: { amount, temperature }; fluids have no item data to
-- keep). Nil for none.
local function cargo_parts(trip)
  if trip.fluid then
    return parts_of(trip, trip.fluid.amount)
  end
  local cargo = trip.cargo
  if not (cargo and cargo.valid) then
    return nil
  end
  local parts
  for grade, count in pairs(cargo.get_item_quality_counts(trip.item)) do
    if count > 0 then
      parts = parts or {}
      parts[quality.key(trip.item, grade)] = count
    end
  end
  return parts
end

-- What a trip will bring, by key: what it promised to load while on its way out, its cargo on the
-- way back. Nil for nothing.
local function bringing(trip)
  if trip.state == TO_PROVIDER then
    return parts_of(trip, trip.planned)
  elseif trip.state == TO_REQUEST then
    return cargo_parts(trip)
  end
  return nil
end

-- Whether two tables of amounts by key (either may be nil, for none) are the same.
local function same(a, b)
  for k, amount in pairs(a or {}) do
    if not b or b[k] ~= amount then
      return false
    end
  end
  for k in pairs(b or {}) do
    if not a or a[k] == nil then
      return false
    end
  end
  return true
end

-- What a trip filed, by key: `trip.coming` or a promise's `parts`; one amount alone (a trip of one
-- key, or from before quality) was filed under its item, whatever its mix is now.
local function filed_parts(trip, filed, amount)
  if type(filed) == "table" then
    return filed
  end
  return amount and amount > 0 and { [trip.item] = amount } or nil
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
-- cargo changes: storage.coming[request depot unit_number][key][trip key] = amount (only amounts
-- above 0; by key, so by quality: a depot counts only those its request takes), and each trip
-- records what it has filed (`trip.coming`, amounts by key; a number, under its item, from before
-- quality; a trip's depot and item never change). So a depot's need is read without looking at
-- each of its trips and their cargo. Cargo that spoils changes with no trip change, so the earliest
-- tick a depot's filed cargo of an item may spoil is filed too (storage.spoiling[request
-- depot][item] = tick, by item), and `committed` files that depot's trips for the item again once
-- it comes (`file_spoiled`).
local file_promises

-- file_coming for a trip of one key, its item's (normal quality, or a fluid: never a `trip.mix`,
-- `trip.graded`) that filed one amount or none (`trip.coming` a number or nil): as before quality,
-- by amount, so the usual trip makes no table. Returns false, doing nothing, for any other trip:
-- one that planned other qualities brings them home after its mix is gone, and its cargo must be
-- counted by quality (Claude's review: filed afresh on a configuration change, it was counted as
-- normal only, and its depot sent for it again).
local function file_coming_one(trip, ended)
  if trip.mix or trip.graded or type(trip.coming) == "table" then
    return false
  end
  local amount = 0
  if not ended then
    if trip.state == TO_PROVIDER then
      amount = trip.planned or 0
    elseif trip.state == TO_REQUEST then
      if trip.fluid then
        amount = trip.fluid.amount
      else
        amount = trip.cargo and trip.cargo.valid and trip.cargo.get_item_count(trip.item) or 0
      end
    end
  end
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
    return true
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
    return true
  end
  local trips = items and items[trip.item]
  if trips then
    trips[trip.key] = nil
    if next(trips) == nil then
      items[trip.item] = nil
      if next(items) == nil then
        coming[trip.request] = nil
      end
      -- Nothing of the item is coming (in any quality): no cargo of it left to spoil.
      local spoiling = storage.spoiling[trip.request]
      if spoiling and spoiling[trip.item] then
        for key in pairs(items) do
          if quality.split(key) == trip.item then
            trip.coming = nil
            return true
          end
        end
        spoiling[trip.item] = nil
        if next(spoiling) == nil then
          storage.spoiling[trip.request] = nil
        end
      end
    end
  end
  trip.coming = nil
  return true
end

local function file_coming(trip, ended)
  if file_coming_one(trip, ended) then
    return
  end
  local amounts = not ended and bringing(trip) or nil
  local spoil_tick = amounts and spoils_at(trip)
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
  local filed = filed_parts(trip, trip.coming, trip.coming)
  if same(filed, amounts) then
    trip.coming = amounts
    return
  end
  local coming = storage.coming
  local items = coming[trip.request]
  -- What it filed and no longer brings goes.
  for k in pairs(filed or {}) do
    local trips = items and items[k]
    if trips and not (amounts and amounts[k]) then
      trips[trip.key] = nil
      if next(trips) == nil then
        items[k] = nil
      end
    end
  end
  for k, amount in pairs(amounts or {}) do
    items = items or {}
    coming[trip.request] = items
    local trips = items[k] or {}
    items[k] = trips
    trips[trip.key] = amount
  end
  trip.coming = amounts
  if items and next(items) == nil then
    coming[trip.request] = nil
    items = nil
  end
  -- Nothing of the item is coming, in any quality: no cargo of it left to spoil.
  local spoiling = not amounts and storage.spoiling[trip.request]
  if spoiling and spoiling[trip.item] then
    for k in pairs(items or {}) do
      if quality.split(k) == trip.item then
        return
      end
    end
    spoiling[trip.item] = nil
    if next(spoiling) == nil then
      storage.spoiling[trip.request] = nil
    end
  end
end

-- What a request depot's freighters, except trip `except` (by id), are bringing of the item it
-- requests, in the qualities it takes (or of `only`, one key). Trips for an item (or a quality) the
-- depot no longer asks for bring nothing it needs.
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

  local function sum(trips, skipped)
    local total = 0
    for key, amount in pairs(trips or {}) do
      if key ~= skipped then
        total = total + amount
      end
    end
    return total
  end
  local NO_TRIPS = {}

  function committed(depot, except, only)
    if not (storage.coming and storage.spoiling) then
      file_promises()
    end
    local request = depot.request
    local item = request and request.item
    local spoiling = item and storage.spoiling[depot.entity.unit_number]
    local due = spoiling and spoiling[item]
    if due and game.tick >= due then
      file_spoiled(depot, item)
    end
    local items = item and storage.coming[depot.entity.unit_number]
    if not items then
      return 0
    end
    local skipped = except and storage.trips[except]
    skipped = skipped and skipped.key
    if only then
      return sum(items[only], skipped)
    end
    local total = 0
    if depot.fluid or (request.quality == nil and request.comparator == nil) then
      -- One key, the item's (normal quality, or a fluid): the most common case, inlined.
      for key, amount in pairs(items[item] or NO_TRIPS) do
        if key ~= skipped then
          total = total + amount
        end
      end
      return total
    end
    for _, grade in ipairs(quality.matching(request)) do
      total = total + sum(items[quality.key(item, grade)], skipped)
    end
    return total
  end
end

-- What freighters on their way to a provider have promised to load there:
-- storage.promised[provider unit_number][key][trip key] = amount (by key: by quality, see
-- scripts/quality.lua; a trip promising several qualities has an entry under each), for every trip driving out
-- (TO_PROVIDER) with a promise, except one that gave up on its provider and is looking for another
-- (`trip.passed`, logistics.give_up): that stock is free again at once. Each trip records where its
-- promise is filed (`trip.promise`), and `promise` files it again whenever its provider, state,
-- promise or `passed` changes, so a provider's
-- unpromised stock is read without looking at every trip in the game. Their total by provider and
-- key is kept with them (storage.promise_totals[provider unit_number][key], each promise rounded
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
  if not trip.mix and not (filed and filed.parts) then
    -- One key, the item's (normal quality, or a fluid), as before quality: no tables made.
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
    return
  end
  local parts = trip.provider and parts_of(trip, amount) or nil
  local had = filed and filed_parts(trip, filed.parts, filed.amount)
  if filed and filed.provider == trip.provider and filed.amount == amount and same(had, parts) then
    return
  end
  local promised, totals = storage.promised, storage.promise_totals
  if filed then
    local items = promised[filed.provider]
    for k, part in pairs(had or {}) do
      local trips = items and items[k]
      if trips and trips[trip.key] then
        trips[trip.key] = nil
        local sums = totals[filed.provider]
        local total = sums[k] - math.ceil(part)
        sums[k] = total ~= 0 and total or nil
        if next(trips) == nil then
          items[k] = nil
        end
      end
    end
    if items and next(items) == nil then
      promised[filed.provider] = nil
      totals[filed.provider] = nil
    end
  end
  trip.promise = nil
  if parts then
    local items = promised[trip.provider] or {}
    promised[trip.provider] = items
    local sums = totals[trip.provider] or {}
    totals[trip.provider] = sums
    for k, part in pairs(parts) do
      local trips = items[k] or {}
      items[k] = trips
      trips[trip.key] = part
      sums[k] = (sums[k] or 0) + math.ceil(part)
    end
    trip.promise = { provider = trip.provider, amount = amount, parts = parts }
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

-- How much of `item` (a key: an item at one quality, scripts/quality.lua, or a fluid) a provider has
-- that no freighter on its way there has promised to load, or with `gross`, how much it has.
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
    count = counter(IDS[item] or quality.id(item))
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

-- How much of what `request` asks for (an item in the qualities it takes, or a fluid) a provider
-- has that no freighter on its way there has promised to load.
local function available_for(provider, request)
  if provider.fluid or (request.quality == nil and request.comparator == nil) then
    return available(provider, request.item)
  end
  local total = 0
  for _, grade in ipairs(quality.matching(request)) do
    total = total + math.max(0, available(provider, quality.key(request.item, grade)))
  end
  return total
end

-- What a freighter can promise to load at a provider for `request`: up to `limit`, as far as the
-- provider has it unpromised, and of an item at most what `stacks` cargo stacks of `size` hold.
-- Qualities a request takes several of come highest first, each its own stacks (stacks of
-- different qualities never merge), and with `fits` (logistics.graded_need's room by quality:
-- `partial` part-filled room per quality, `empty` stacks; not changed) each only as far as it fits
-- at the request depot, so no freighter is sent for a quality there is no room for. Returns the
-- amount and, for an item request that isn't for normal quality alone, the mix (quality -> amount)
-- for `trip.mix`.
local function allocate(provider, request, limit, stacks, size, fits)
  if provider.fluid or (request.quality == nil and request.comparator == nil) then
    return math.max(0, math.min(limit, available(provider, request.item))), nil
  end
  local total, mix = 0, {}
  local room = stacks and stacks * size or math.huge
  local empty = fits and fits.empty
  for _, grade in ipairs(quality.matching(request)) do
    local take = math.min(math.max(0, available(provider, quality.key(request.item, grade))), limit - total, room)
    if fits then
      local partial = fits.partial[grade] or 0
      take = math.min(take, partial + empty * fits.size)
      -- What it takes beyond its part-filled stacks takes empty ones.
      empty = empty - math.ceil(math.max(0, take - partial) / fits.size)
    end
    if take > 0 then
      mix[grade] = take
      total = total + take
      if stacks then
        room = room - math.ceil(take / size) * size
      end
    end
    if total >= limit or room <= 0 then
      break
    end
  end
  return total, total > 0 and mix or nil
end

ledger.file_promises = file_promises
ledger.available_for = available_for
ledger.allocate = allocate
ledger.committed = committed
ledger.promise = promise
ledger.available = available

return ledger
