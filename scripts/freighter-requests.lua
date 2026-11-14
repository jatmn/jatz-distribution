-- SPDX-License-Identifier: LGPL-3.0-only
-- Freighters asked of construction robots, and taken away by them: item request proxies on a
-- request depot's truck chest. Split out of scripts/logistics.lua, whose main chunk had reached
-- Lua's limit of 200 locals (issue #69). logistics.lua keeps the entry points
-- (`logistics.request_freighters` and the others), and hands this module the helpers it shares
-- with it when it loads (requests.install).
local requests = {}

-- One target owner, including saves from before replenishment had a named phase. Idle is nil;
-- outstanding plans live in Factorio, so reconciliation derives whether more chest room is needed.
-- Second: the quality robots bring for it (scripts/quality.lua; nil for normal): a freighter
-- ghost's from the panel, a lost freighter's for its replacement, the latest asked for. Those still
-- waiting for a free chest stack keep the quality each was asked for at
-- (`replenishment.waiting`, see request_up_to).
function requests.target(depot)
  if depot.freighter_target ~= nil then
    depot.replenishment = { phase = "reconciling", target = depot.freighter_target }
    depot.freighter_target = nil
  end
  return depot.replenishment and depot.replenishment.target, depot.replenishment and depot.replenishment.quality
end

function requests.set_target(depot, target, grade)
  depot.freighter_target = nil
  depot.replenishment = target and { phase = "reconciling", target = target, quality = grade } or nil
end

local function awaiting(depot, total, target)
  local short = total < target
  depot.replenishment.phase = short and "waiting-for-space" or "requested"
  if not short then
    depot.replenishment.waiting = nil
  end
end

-- scripts/logistics.lua, and its helpers, from requests.install.
local logistics, request_depot, truck_chest, freighter_chest, trucks_of, a_freighter, parked_fuel
local freighter_stack_size, FREIGHTER, QUALITY

function requests.install(owner, shared)
  logistics = owner
  request_depot, truck_chest, freighter_chest = shared.request_depot, shared.truck_chest, shared.freighter_chest
  trucks_of, a_freighter, parked_fuel = shared.trucks_of, shared.a_freighter, shared.parked_fuel
  freighter_stack_size, FREIGHTER, QUALITY = shared.freighter_stack_size, shared.freighter, shared.quality
end

-- Freighters can also be requested, like modules or fuel: an item request proxy asks construction
-- robots to deliver them into the depot's truck chest, from where they move into the slot. This is how a
-- player in remote view (or anywhere without freighters in hand) stocks a depot.
local PROXY = "item-request-proxy"

local function item_name(id)
  return type(id) == "string" and id or id.name
end
requests.item_name = item_name

-- The item request proxies targeting a request depot; how many freighters they still ask robots to
-- bring, and to take away; and the chest stacks (0-based) freighters are to be taken from.
local function freighter_requests(entity)
  local proxies, requested, removing, marked = {}, 0, 0, {}
  -- Its requests are on its truck chest.
  entity = truck_chest(entity)
  -- Usually none at all: then the ground needn't be searched for them.
  if not entity.item_request_proxy then
    return proxies, requested, removing, marked
  end
  local x, y = entity.position.x, entity.position.y
  for _, proxy in
    pairs(entity.surface.find_entities_filtered({
      name = PROXY,
      area = { { x - 0.5, y - 0.5 }, { x + 0.5, y + 0.5 } },
    }))
  do
    if proxy.proxy_target == entity then
      proxies[#proxies + 1] = proxy
      for _, request in pairs(proxy.item_requests) do
        if item_name(request.name) == FREIGHTER then
          requested = requested + request.count
        end
      end
      for _, plan in pairs(proxy.removal_plan) do
        if item_name(plan.id.name) == FREIGHTER then
          for _, position in pairs(plan.items.in_inventory or {}) do
            removing = removing + (position.count or 1)
            marked[position.stack] = (marked[position.stack] or 0) + (position.count or 1)
          end
        end
      end
    end
  end
  return proxies, requested, removing, marked
end
requests.freighter_requests = freighter_requests

-- How many freighters a request depot has asked robots to bring, and to take away.
function requests.requested_freighters(entity)
  if not request_depot(entity) then
    return 0, 0
  end
  local _, requested, removing = freighter_requests(entity)
  return requested, removing
end

-- Chest stacks (0-based) that are empty and in no request's plan, as a list.
local function free_chest_stacks(chest, proxies)
  local taken = {}
  for _, proxy in ipairs(proxies) do
    for _, plans in ipairs({ proxy.insert_plan, proxy.removal_plan }) do
      for _, plan in pairs(plans) do
        for _, position in pairs(plan.items.in_inventory or {}) do
          taken[position.stack] = true
        end
      end
    end
  end
  local free = {}
  for index = 1, #chest do
    if not chest[index].valid_for_read and not taken[index - 1] then
      free[#free + 1] = index - 1
    end
  end
  return free
end

-- Positions for `amount` freighters, a stack at a time, in the given chest stacks (0-based), which
-- are taken off the list; the amount that fits, and the positions.
local function spread(amount, stacks)
  local stack_size = freighter_stack_size()
  local positions, placed = {}, 0
  while placed < amount and #stacks > 0 do
    local count = math.min(stack_size, amount - placed)
    positions[#positions + 1] = { inventory = defines.inventory.chest, stack = table.remove(stacks, 1), count = count }
    placed = placed + count
  end
  return placed, positions
end

-- Add an insert or removal plan to a depot's request proxy, making one if it has none.
local function add_plan(entity, proxies, plan, removal)
  entity = truck_chest(entity)
  local proxy = proxies[1]
  if proxy then
    local plans = removal and proxy.removal_plan or proxy.insert_plan
    plans[#plans + 1] = plan
    if removal then
      proxy.removal_plan = plans
    else
      proxy.insert_plan = plans
    end
  else
    entity.surface.create_entity({
      name = PROXY,
      position = entity.position,
      force = entity.force,
      target = entity,
      modules = removal and {} or { plan },
      removal_plan = removal and { plan } or nil,
    })
  end
end

-- Ask construction robots to bring freighters into a request depot's chest until it has `goal`
-- (within its slot's limit), counting freighters in its slot, out, in its chest (except those
-- waiting to be taken away) and already requested. `goal` becomes the depot's target, what the
-- requests are for: freighters arriving some other way (put in by hand) count towards it, and
-- requests beyond it are cancelled. It is kept even when the chest has no free stacks for some or
-- all of them yet (it also holds the depot's cargo): trim_freighter_requests asks for the rest as
-- stacks free up. Robots bring freighters of quality `grade` (nil: normal), except those still
-- waiting for a free stack from before, which keep the quality they were asked for at. Returns how
-- many were requested now.
local function request_up_to(entity, goal, grade)
  local in_slot, out, capacity = logistics.freighter_counts(entity)
  if not in_slot then
    return 0
  end
  local chest = freighter_chest(entity)
  local proxies, requested, removing = freighter_requests(entity)
  local have = in_slot + out + logistics.waiting_freighters(entity) - removing + requested
  goal = math.min(goal, capacity)
  if goal <= have then
    return 0
  end
  local depot = request_depot(entity)
  -- What to ask for, by quality, those asked for first first: the ones still waiting from before
  -- (as many as its earlier target still lacks; freighters put in by hand count for the last
  -- asked), then the rest of the way to `goal`, of `grade`.
  local owed, left = {}, math.min(goal, depot.replenishment and depot.replenishment.target or 0) - have
  local function owe(name, count)
    if count <= 0 then
      return
    end
    for _, part in ipairs(owed) do
      if part.quality == name then
        part.count = part.count + count
        return
      end
    end
    owed[#owed + 1] = { quality = name, count = count }
  end
  for _, part in ipairs(depot.replenishment and depot.replenishment.waiting or {}) do
    local count = math.min(part.count, left)
    owe(part.quality, count)
    left = left - math.max(count, 0)
  end
  local earlier = 0
  for _, part in ipairs(owed) do
    earlier = earlier + part.count
  end
  owe(grade, goal - have - earlier)
  requests.set_target(depot, goal, grade)
  -- A stack at a time, into chest stacks that are empty and in no other plan; a plan for each
  -- quality, as a plan names its items' quality. What doesn't fit waits, by quality.
  local free, placed, waiting = free_chest_stacks(chest, proxies), 0, nil
  for _, part in ipairs(owed) do
    local amount, positions = spread(part.count, free)
    if amount > 0 then
      add_plan(entity, proxies, {
        id = { name = FREIGHTER, quality = part.quality or QUALITY },
        items = { in_inventory = positions },
      })
      -- A new proxy made for the first plan takes the others.
      if #proxies == 0 then
        proxies = freighter_requests(entity)
      end
      placed = placed + amount
    end
    if amount < part.count then
      waiting = waiting or {}
      waiting[#waiting + 1] = { quality = part.quality, count = part.count - amount }
    end
  end
  depot.replenishment.waiting = waiting
  awaiting(depot, have + placed, goal)
  return placed
end

-- Ask construction robots to bring `count` more freighters (or as many as the slot has room for)
-- into a request depot's chest: more than it has and has already asked for, including freighters
-- still waiting for a free chest stack (its target). Of quality `grade` (a name; normal if nil: the
-- panel passes the freighter ghost's). Returns how many were requested now.
function requests.request_freighters(entity, count, grade)
  local depot = request_depot(entity)
  if not depot or (grade ~= nil and not (type(grade) == "string" and prototypes.quality[grade])) then
    return 0
  end
  grade = grade ~= QUALITY and grade or nil
  local have, capacity = logistics.freighter_total(entity)
  local asked = math.max(have, requests.target(depot) or 0)
  local room = capacity - asked
  local amount = math.min(math.floor(tonumber(count) or room), room)
  if amount <= 0 then
    return 0
  end
  return request_up_to(entity, asked + amount, grade)
end

-- Have construction robots take `count` freighters (or all) out of a request depot's slot, as
-- from remote view: they move into an empty chest stack marked for removal, and robots carry them
-- to storage. Returns how many were marked.
function requests.remove_freighters(entity, count)
  local depot = request_depot(entity)
  if not depot then
    return 0
  end
  -- Taking freighters away on purpose: no longer top the depot up to an earlier target.
  requests.set_target(depot, nil)
  local slot = trucks_of(depot)
  local wanted = math.min(math.floor(tonumber(count) or slot.get_item_count()), slot.get_item_count())
  if wanted <= 0 then
    return 0
  end
  local chest = freighter_chest(entity)
  local proxies = freighter_requests(entity)
  -- A stack at a time from the slot into empty chest stacks, each marked for removal: one plan per
  -- quality, as a removal plan names its items' quality (scripts/quality.lua).
  local positions, order, moved = {}, {}, 0
  for _, index in ipairs(free_chest_stacks(chest, proxies)) do
    local from = a_freighter(depot)
    if moved >= wanted or not from then
      break
    end
    local into = chest[index + 1]
    into.transfer_stack(from, math.min(from.count, wanted - moved))
    if into.valid_for_read then
      local grade = into.quality.name
      if not positions[grade] then
        positions[grade] = {}
        order[#order + 1] = grade
      end
      local list = positions[grade]
      list[#list + 1] = { inventory = defines.inventory.chest, stack = index, count = into.count }
      moved = moved + into.count
    end
  end
  for _, grade in ipairs(order) do
    add_plan(
      entity,
      proxies,
      { id = { name = FREIGHTER, quality = grade }, items = { in_inventory = positions[grade] } },
      true
    )
    -- A new proxy made for the first plan takes the others.
    if #proxies == 0 then
      proxies = freighter_requests(entity)
    end
  end
  -- The freighters leaving take their fuel entries, as in take_freighters.
  parked_fuel(depot)
  return moved
end

-- Cancel the robots' removal of a request depot's freighters; they go back into its slot at the
-- next dispatch. Returns how many were waiting to be taken.
-- Freighters a request depot has or will have: in its slot, out on trips, in its chest (except
-- those being taken away) and coming. Also the slot's limit and how many are coming.
local function freighter_total(entity)
  local in_slot, out, capacity = logistics.freighter_counts(entity)
  local _, coming, removing = freighter_requests(entity)
  local in_chest = logistics.waiting_freighters(entity) - removing
  return in_slot + out + in_chest + coming, capacity, coming
end
requests.freighter_total = freighter_total

-- Ask robots for as many freighters as it takes for a request depot to have `total` (within its
-- slot's limit), of quality `grade` (nil: normal; a lost freighter's replacement is its quality).
-- Returns how many were requested.
function requests.match_freighters(entity, total, grade)
  local depot = request_depot(entity)
  if not depot then
    return 0
  end
  total = math.max(0, math.floor(tonumber(total) or 0))
  grade = grade ~= QUALITY and type(grade) == "string" and prototypes.quality[grade] and grade or nil
  local have = freighter_total(entity)
  if total > have then
    return request_up_to(entity, total, grade)
  end
  -- Already as many or more: freighter requests beyond `total` are cancelled. Freighters already
  -- in the depot stay; they are the player's, and taking them away is the player's call.
  requests.set_target(depot, total, grade)
  logistics.trim_freighter_requests(entity)
  return 0
end

-- Lower a depot's freighter requests by `excess`, editing its request proxies' plans in place,
-- from the last position back, rather than replacing them. An open container window keeps showing
-- the requests of the proxy it opened with: replacing the proxy (cancel, then request anew) left
-- the chest slot's ghost hidden until the window was reopened.
local function reduce_freighter_requests(entity, excess)
  local proxies = freighter_requests(entity)
  for index = #proxies, 1, -1 do
    if excess <= 0 then
      break
    end
    local proxy = proxies[index]
    local plans = proxy.insert_plan
    for plan_index = #plans, 1, -1 do
      local plan = plans[plan_index]
      if excess > 0 and item_name(plan.id.name) == FREIGHTER then
        local positions = plan.items.in_inventory or {}
        for position_index = #positions, 1, -1 do
          if excess <= 0 then
            break
          end
          local count = positions[position_index].count or 1
          local cut = math.min(count, excess)
          excess = excess - cut
          if cut >= count then
            table.remove(positions, position_index)
          else
            positions[position_index].count = count - cut
          end
        end
        if #positions == 0 then
          table.remove(plans, plan_index)
        else
          plan.items.in_inventory = positions
        end
      end
    end
    if #plans == 0 and #proxy.removal_plan == 0 then
      proxy.destroy()
    else
      proxy.insert_plan = plans
    end
  end
end

-- Keep a request depot's freighter requests to what they are for (`depot.replenishment.target`: the
-- total the depot should end up with), until it has them:
-- * beyond the target (freighters arrived some other way, put in by hand, say): the excess
--   requests are cancelled, so robots never bring more, nor overfill the slot;
-- * short of it with nothing requested to cover it: the shortfall is requested again. Factorio
--   drops an item request a player fills by hand even when they only put in part of it; the
--   target is what remembers the rest;
-- * once the depot has them all: the target is forgotten.
-- Without a target, requests are only kept within the slot's limit. Runs with every dispatch and
-- whenever freighters are put in by hand.
function requests.trim_freighter_requests(entity)
  local depot = request_depot(entity)
  -- Freighters asked of an item depot's own chest, by an item request proxy targeting the depot: a
  -- blueprint ghost's insert plan, a request from a save from before the truck chest, or another
  -- mod's. Inserters unloading the depot could take them before they reach the slot, so they are
  -- asked of its truck chest instead: dropped here, and requested again below as part of its
  -- target, which they become if it has none. Robots taking freighters away from its own chest (a
  -- save from before) stop; those stay in the depot.
  -- Several proxies can target it, and `item_request_proxy` names only the first found (another
  -- item's, say), so it only says whether to look: every one targeting the depot is looked at, and
  -- their freighters are added up before any becomes the target.
  if not depot.fluid and entity.item_request_proxy then
    local x, y = entity.position.x, entity.position.y
    local moved = 0
    for _, proxy in
      pairs(entity.surface.find_entities_filtered({
        name = PROXY,
        area = { { x - 0.5, y - 0.5 }, { x + 0.5, y + 0.5 } },
      }))
    do
      -- Not its truck chest's, at the same spot.
      if proxy.proxy_target == entity then
        local changed = false
        local inserts, removals = {}, {}
        for _, plan in pairs(proxy.insert_plan) do
          if item_name(plan.id.name) == FREIGHTER then
            for _, position in pairs(plan.items.in_inventory or {}) do
              moved = moved + (position.count or 1)
            end
            changed = true
          else
            inserts[#inserts + 1] = plan
          end
        end
        for _, plan in pairs(proxy.removal_plan) do
          if item_name(plan.id.name) == FREIGHTER then
            changed = true
          else
            removals[#removals + 1] = plan
          end
        end
        if changed then
          if #inserts == 0 and #removals == 0 then
            proxy.destroy()
          else
            proxy.insert_plan = inserts
            proxy.removal_plan = removals
          end
        end
      end
    end
    if moved > 0 and not requests.target(depot) then
      requests.set_target(depot, freighter_total(entity) + moved)
    end
  end
  if not requests.target(depot) and not truck_chest(entity).item_request_proxy then
    -- No target and no requests: nothing to keep.
    return
  end
  local total, capacity, coming = freighter_total(entity)
  if not requests.target(depot) and coming > 0 then
    -- Freighters requested without a target: Factorio's own request from a blueprint ghost (a
    -- player building over a ghost doesn't pass its tags on), or one set by another mod. What the
    -- depot has and is asking for is what it should end up with.
    requests.set_target(depot, total)
  end
  local target = requests.target(depot)
  local wanted = target and math.min(target, capacity)
  if not wanted then
    return
  end
  if total - coming >= wanted then
    -- All there, without the requests: they are done.
    if coming > 0 then
      logistics.cancel_freighter_requests(entity)
    end
    requests.set_target(depot, nil)
  elseif total > wanted then
    -- More coming than still needed: lower the requests by the excess, in place.
    reduce_freighter_requests(entity, total - wanted)
    awaiting(depot, wanted, wanted)
  elseif total < wanted then
    -- Short, with nothing requested to cover it: ask again for the rest, of the quality it was for.
    request_up_to(entity, wanted, select(2, requests.target(depot)))
  else
    awaiting(depot, total, wanted)
  end
end

return requests
