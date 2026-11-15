-- SPDX-License-Identifier: LGPL-3.0-only
-- Quality (scripts/quality.lua) in deliveries, against the fake runtime of tests/lua/harness.lua:
-- requests by quality (exact, compared, any), highest first, each quality its own stock, promise
-- queue and cargo stacks, room by quality at the request depot, better freighters, robot freighter
-- requests by quality, and qualities a mod change removed. Split out of tests/lua/logistics.lua
-- (which keeps everything else about deliveries) to keep each file under the 256 KiB CI allows.
-- Run from the repository root with Lua 5.2 (tools/test_mod_setup.py does): lua5.2 tests/lua/quality.lua
package.path = "./?.lua;" .. package.path

local harness = require("tests.lua.harness")
local stack, script_inventory, entity, tank = harness.stack, harness.script_inventory, harness.entity, harness.tank
local answer, arrive, has_trip, forget_roads, check =
  harness.answer, harness.arrive, harness.has_trip, harness.forget_roads, harness.check
local supplied, trips_from = harness.supplied, harness.trips_from
local surface, requests
local function reset()
  local logistics = harness.reset()
  surface, requests = harness.state()
  return logistics
end

-- Quality (scripts/quality.lua). A provider's chest of real stacks of item a (stack size 50), each
-- { quality, count }, and a request depot's chest of real stacks with room for 1000 of any quality,
-- so cargo is unloaded into it.
local function graded_stock(provider, stacks)
  local stock = script_inventory(math.max(1, #stacks))
  for index, spec in ipairs(stacks) do
    stock[index].name, stock[index].count, stock[index].valid_for_read = "a", spec[2], true
    stock[index].quality = { name = spec[1] }
  end
  provider.get_inventory = function()
    return stock
  end
  return stock
end
local function stocked_chest(depot)
  local chest = script_inventory(48)
  chest.get_insertable_count = function()
    return 1000
  end
  depot.get_inventory = function()
    return chest
  end
  return chest
end
local function graded(name, count, grade)
  local made = stack(name, count)
  made.quality = { name = grade }
  return made
end
local function count_of(inventory_, grade)
  return inventory_.get_item_count({ name = "a", quality = grade })
end
-- A request depot asking for `count` of item a at `grade` (compared by `comparator`), with
-- `trucks` normal freighters, and a provider holding `stacks`.
local function quality_pair(logistics, count, grade, comparator, stacks, trucks)
  local request = entity("jatz-request-depot", 0.5, 0.5)
  local provider = entity("jatz-provider-depot", 10.5, 0.5)
  local stock = graded_stock(provider, stacks)
  local chest = stocked_chest(request)
  logistics.add(request)
  logistics.add(provider)
  assert(logistics.set_request(request, "a", count, grade, comparator))
  assert(logistics.put_freighters(request, stack("jatz-quinityn-freighter", trucks or 2)) == (trucks or 2))
  return request, provider, stock, chest
end

do -- A request names its quality and how others compare with it; nonsense is refused.
  local logistics = reset()
  local request = entity("jatz-request-depot", 0.5, 0.5)
  local liquid = tank("jatz-liquid-request-depot", 0.5, 10.5, "water", 0)
  logistics.add(request)
  logistics.add(liquid)
  check("a request for rare a", logistics.set_request(request, "a", 10, "rare"))
  local got = logistics.get_request(request)
  check("keeps its quality, with '=' left out", got.quality == "rare" and got.comparator == nil)
  check("a quality the game doesn't have is refused", not logistics.set_request(request, "a", 10, "mythic"))
  check("and so is its hidden one", not logistics.set_request(request, "a", 10, "quality-unknown"))
  check("as is another comparator", not logistics.set_request(request, "a", 10, "rare", "~"))
  check("leaving the request as it was", logistics.get_request(request).quality == "rare")
  assert(logistics.set_request(request, "a", 10, "rare", ">="))
  check("'>=' is kept as the game writes it back", logistics.get_request(request).comparator == "≥")
  assert(logistics.set_request(request, "a", 10, "epic", "any"))
  got = logistics.get_request(request)
  check("any quality keeps no quality", got.quality == nil and got.comparator == "any")
  assert(logistics.set_request(request, "a", 10, "normal", "="))
  got = logistics.get_request(request)
  check("normal '=' is stored as a request from before quality", got.quality == nil and got.comparator == nil)
  check("a fluid has no quality", not logistics.set_request(liquid, "water", 100, "rare"))
  check("nor any quality", not logistics.set_request(liquid, "water", 100, nil, "any"))
  check("a fluid's plain request still goes", logistics.set_request(liquid, "water", 100, "normal", "="))
end

do -- Rare only: the freighter promises, loads and brings the rare ones, whatever the freighter's
  -- and the depots' quality, and nothing of the others.
  local logistics = reset()
  local request, provider, stock, chest =
    quality_pair(logistics, 30, "rare", nil, { { "normal", 40 }, { "rare", 15 }, { "epic", 5 } })
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(request)[1]
  check("the freighter promises the rare ones only", trip.planned == 15 and trip.mix.rare == 15 and not trip.mix.normal)
  local promised = storage.promised[provider.unit_number]
  check("filed under rare a's key, not a's", promised["a/rare"][trip.key] == 15 and promised.a == nil)
  arrive(logistics, trip)
  check(
    "it loads them and nothing else",
    count_of(trip.cargo, "rare") == 15 and count_of(trip.cargo, "normal") == 0 and count_of(stock, "normal") == 40
  )
  arrive(logistics, trip)
  check("and brings them home", count_of(chest, "rare") == 15 and count_of(chest, "normal") == 0)
  check("which count for the request", logistics.missing(storage.depots[request.unit_number]) == 15)
end

do -- Any quality: highest first, each quality its own cargo stacks (two before research).
  local logistics = reset()
  local request, _, stock = quality_pair(
    logistics,
    100,
    nil,
    "any",
    { { "normal", 40 }, { "rare", 15 }, { "epic", 5 }, { "legendary", 30 } },
    2
  )
  logistics.on_tick()
  answer(logistics, 1, "route")
  local first = trips_from(request)[1]
  check(
    "the first freighter takes legendary, then epic, filling its two stacks",
    first.planned == 35 and first.mix.legendary == 30 and first.mix.epic == 5 and not first.mix.rare
  )
  game.tick = 60
  logistics.on_tick()
  answer(logistics, #requests, "route")
  local second = trips_from(request)[2]
  check("the next takes rare, then normal", second.planned == 55 and second.mix.rare == 15 and second.mix.normal == 40)
  arrive(logistics, first)
  check(
    "the first loads what it promised",
    count_of(first.cargo, "legendary") == 30 and count_of(first.cargo, "epic") == 5 and count_of(stock, "rare") == 15
  )
end

do -- Qualities compared: at least rare takes legendary and rare, never normal.
  local logistics = reset()
  local request =
    quality_pair(logistics, 100, "rare", "≥", { { "normal", 40 }, { "rare", 15 }, { "legendary", 10 } }, 2)
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(request)[1]
  check(
    "'≥ rare' promises legendary and rare",
    trip.planned == 25 and trip.mix.legendary == 10 and trip.mix.rare == 15
  )
  check("held counts only those", logistics.missing(storage.depots[request.unit_number]) == 75)
end

do -- Two depots at one provider, one for rare and one for any quality: neither promises what the
  -- other has.
  local logistics = reset()
  local rare, provider = quality_pair(logistics, 50, "rare", nil, { { "normal", 20 }, { "rare", 15 } }, 1)
  local any = entity("jatz-request-depot", 0.5, 10.5)
  stocked_chest(any)
  logistics.add(any)
  assert(logistics.set_request(any, "a", 50, nil, "any"))
  assert(logistics.put_freighters(any, stack("jatz-quinityn-freighter", 1)) == 1)
  logistics.on_tick()
  for id = 1, #requests do
    answer(logistics, id, "route")
  end
  local first, second = trips_from(rare)[1], trips_from(any)[1]
  local totals = storage.promise_totals[provider.unit_number]
  check(
    "the rare stock goes to one, the normal to the other",
    first and second and first.planned + second.planned == 35 and totals["a/rare"] == 15 and totals.a == 20
  )
end

do -- Changing the request keeps what its freighters promised of qualities it still takes.
  local logistics = reset()
  local request, provider =
    quality_pair(logistics, 100, nil, "any", { { "normal", 40 }, { "rare", 15 }, { "legendary", 30 } }, 1)
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(request)[1]
  check("setup: legendary and rare promised", trip.mix.legendary == 30 and trip.mix.rare == 15)
  assert(logistics.set_request(request, "a", 100, "rare"))
  check(
    "rare only: the rare part stays promised",
    trip.planned == 15 and trip.mix.rare == 15 and not trip.mix.legendary
  )
  check("and the legendary is free again", storage.promise_totals[provider.unit_number]["a/legendary"] == nil)
  assert(logistics.set_request(request, "a", 100))
  check("normal only: nothing it promised is wanted", trip.planned == 0 and trip.mix == nil)
end

do -- A depot that got what it wants some other way lets its freighters' lowest qualities go first.
  local logistics = reset()
  local request, _, _, chest = quality_pair(logistics, 35, nil, "any", { { "epic", 5 }, { "legendary", 30 } }, 1)
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(request)[1]
  check("setup: legendary 30 and epic 5 promised", trip.planned == 35 and trip.mix.epic == 5)
  chest.insert(graded("a", 10, "normal"))
  game.tick = 60
  logistics.on_tick()
  check("10 more than wanted go: the epic 5, then 5 legendary", trip.planned == 25 and trip.mix.legendary == 25)
  check("with nothing epic left in the mix", not trip.mix.epic)
end

do -- A provider whose stock of one quality was taken out keeps only what is left of each.
  local logistics = reset()
  local request, provider, stock = quality_pair(logistics, 100, nil, "any", { { "rare", 15 }, { "legendary", 30 } }, 1)
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(request)[1]
  stock[2].count = 10 -- 20 legendary taken out by an inserter
  game.tick = 60
  logistics.keep_promises(provider.unit_number, storage.depots[provider.unit_number])
  check("its legendary promise drops to the 10 left", trip.mix.legendary == 10 and trip.mix.rare == 15)
  check(
    "and its total with it",
    trip.planned == 25 and storage.promise_totals[provider.unit_number]["a/legendary"] == 10
  )
end

do -- Several qualities share a chest's room: each quality's part-filled stacks take only it, and
  -- empty ones any one each; what is coming fills its own room first. Never more than fits.
  local logistics = reset()
  local request = quality_pair(logistics, 1000, nil, "any", { { "rare", 15 } }, 1)
  local depot = storage.depots[request.unit_number]
  -- Three stacks: rare 30 (20 short of a stack), normal 20 (30 short), and one empty, as the game
  -- counts room: an empty stack for a quality it holds none of, plus that quality's part-filled.
  local chest = script_inventory(3)
  chest[1].name, chest[1].count, chest[1].valid_for_read, chest[1].quality = "a", 30, true, { name = "rare" }
  chest[2].name, chest[2].count, chest[2].valid_for_read, chest[2].quality = "a", 20, true, { name = "normal" }
  chest.get_insertable_count = function(id)
    local grade = type(id) == "table" and id.quality or "normal"
    return grade == "rare" and 70 or grade == "normal" and 80 or 50
  end
  request.get_inventory = function()
    return chest
  end
  local wanted, room, _, _, fits = logistics.graded_need(depot, chest, depot.request)
  check("room: the empty stack and both part-filled ones", room == 100 and wanted == 1000 - 50)
  check("by quality", fits.empty == 1 and fits.partial.rare == 20 and fits.partial.normal == 30)
  logistics.on_tick()
  answer(logistics, 1, "route")
  check("setup: a freighter brings 15 rare", trips_from(request)[1].mix.rare == 15)
  wanted, room = logistics.graded_need(depot, chest, depot.request)
  check("which fill rare's own room first: 85 left", room == 85 and wanted == 1000 - 50 - 15)
end

do -- A better freighter: sent first, made at its quality (the game gives it that quality's health),
  -- carrying more stacks (rounded down), faster, with a bigger tank, and parked with its own fuel.
  local logistics = reset()
  local request = entity("jatz-request-depot", 0.5, 0.5)
  local provider = entity("jatz-provider-depot", 10.5, 0.5, { a = 500 })
  logistics.add(request)
  logistics.add(provider)
  assert(logistics.set_request(request, "a", 500))
  assert(logistics.put_freighters(request, stack("jatz-quinityn-freighter", 1)) == 1)
  assert(logistics.put_freighters(request, graded("jatz-quinityn-freighter", 1, "rare")) == 1)
  local by_quality = logistics.freighters_by_quality(request)
  check(
    "the slot lists its freighters best first",
    by_quality[1].quality == "rare" and by_quality[2].quality == "normal"
  )
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(request)[1]
  check("the rare freighter goes first", trip.freighter_quality == "rare" and trip.drone.quality.name == "rare")
  check("with 3 stacks (2 x 1.6, rounded down)", #trip.cargo == 3 and trip.planned == 150)
  check("1.6 times as fast", math.abs(trip.drone.speed - 0.2 * 1.6) < 1e-9)
  check("with a 32 MJ tank, full", trip.energy == 32000000)
  game.tick = 60
  logistics.on_tick()
  answer(logistics, #requests, "route")
  local second = trips_from(request)[2]
  check(
    "then the normal one, as before",
    second.freighter_quality == nil and #second.cargo == 2 and second.energy == 20000000
  )
  arrive(logistics, trip)
  trip.energy = 30000000
  arrive(logistics, trip)
  local depot = storage.depots[request.unit_number]
  check("back home, it parks with its fuel, as a rare one", depot.graded_fuel.rare[1] == 30000000 and #depot.fuel == 0)
  local fuel = logistics.freighter_fuel(request)
  check("its tank shows as its quality's", fuel.home[1] == 30000000 and fuel.home_tanks[1] == 32000000)
end

do -- A freighter sent out has room to come back, however its fleet is split by quality (stacks of
  -- different qualities never merge): with 90 normal and 1 rare, the rare one goes first, and an
  -- epic one put in while it was out took its stack, the slot's last; the rare one came home to no
  -- room and was spilled (the review of 0e0a596, in the engine too). A slot saved with 10 stacks is
  -- made bigger.
  local logistics = reset()
  local request = entity("jatz-request-depot", 0.5, 0.5)
  local provider = entity("jatz-provider-depot", 10.5, 0.5, { a = 1 })
  logistics.add(request)
  logistics.add(provider)
  assert(logistics.set_request(request, "a", 1))
  storage.depots[request.unit_number].trucks = script_inventory(10)
  for _ = 1, 9 do
    assert(logistics.put_freighters(request, stack("jatz-quinityn-freighter", 10)) == 10)
  end
  assert(logistics.put_freighters(request, graded("jatz-quinityn-freighter", 1, "rare")) == 1)
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(request)[1]
  check("setup: the rare one goes first", trip.freighter_quality == "rare")
  check(
    "an epic one put in while it is out goes in",
    logistics.put_freighters(request, graded("jatz-quinityn-freighter", 1, "epic")) == 1
  )
  arrive(logistics, trip)
  arrive(logistics, trip)
  local slot = storage.depots[request.unit_number].trucks
  check(
    "the rare one comes back into the slot, nothing spilled",
    storage.trips[trip.key] == nil
      and slot.get_item_count({ name = "jatz-quinityn-freighter", quality = "rare" }) == 1
      and slot.get_item_count() == 92
      and #surface.spilled == 0
  )
end

do -- A rare freighter lost on the way: robots are asked for a rare one.
  local logistics = reset()
  local request = supplied(logistics, 0)
  assert(logistics.put_freighters(request, graded("jatz-quinityn-freighter", 1, "rare")) == 1)
  local truck = storage.depots[request.unit_number].chest
  local trucks = script_inventory(4)
  truck.get_inventory = function()
    return trucks
  end
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(request)[1]
  logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = trip.drone.unit_number })
  local proxy = surface.created[#surface.created]
  check(
    "the replacement asked for is rare",
    proxy.name == "item-request-proxy" and proxy.parameters.modules[1].id.quality == "rare"
  )
  check(
    "and remembered as rare",
    select(2, require("scripts.freighter-requests").target(storage.depots[request.unit_number])) == "rare"
  )
end

-- Insert plans as the game keeps them (probed on 2.1.24): sorted by quality, lowest first, plans of
-- one item at one quality joined into one, and a copy handed back each time they are read.
local function native_plans(plans)
  local joined, order = {}, {}
  for _, plan in ipairs(plans) do
    local grade = plan.id.quality or "normal"
    local key = plan.id.name .. "/" .. grade
    if not joined[key] then
      joined[key] = { id = { name = plan.id.name, quality = grade }, items = { in_inventory = {} } }
      order[#order + 1] = joined[key]
    end
    for _, position in ipairs(plan.items.in_inventory) do
      local list = joined[key].items.in_inventory
      list[#list + 1] = { inventory = position.inventory, stack = position.stack, count = position.count }
    end
  end
  table.sort(order, function(a, b)
    return prototypes.quality[a.id.quality].level < prototypes.quality[b.id.quality].level
  end)
  return order
end

-- A request depot's truck chest of `stacks` stacks, all full of item b, whose item request proxies
-- are found as in the game: what they ask for counts, and their plans' stacks are taken. The
-- freighter plans of every proxy made for it, as { quality, count }, and a function that empties
-- chest stack `index` (1-based).
local function full_truck_chest(request, stacks)
  local truck = storage.depots[request.unit_number].chest
  local chest = script_inventory(stacks)
  for index = 1, stacks do
    chest[index].name, chest[index].count, chest[index].valid_for_read = "b", 50, true
  end
  truck.get_inventory = function()
    return chest
  end
  local proxies = {}
  local create = surface.create_entity
  function surface.create_entity(parameters)
    local made = create(parameters)
    if parameters.name == "item-request-proxy" then
      made.proxy_target, made.removal_plan = truck, {}
      local plans = native_plans(parameters.modules)
      setmetatable(made, {
        __index = function(_, key)
          if key == "insert_plan" then
            return native_plans(plans)
          elseif key == "item_requests" then
            local list = {}
            for _, plan in ipairs(plans) do
              for _, position in ipairs(plan.items.in_inventory) do
                list[#list + 1] = { name = plan.id.name, quality = plan.id.quality, count = position.count or 1 }
              end
            end
            return list
          end
        end,
        __newindex = function(_, key, value)
          if key == "insert_plan" then
            plans = native_plans(value)
          else
            rawset(made, key, value)
          end
        end,
      })
      proxies[#proxies + 1] = made
      truck.item_request_proxy = made
    end
    return made
  end
  -- (Destroyed proxies are no longer found.)
  function surface.find_entities_filtered(filter)
    local found = {}
    for _, proxy in ipairs(filter.name == "item-request-proxy" and proxies or {}) do
      if proxy.valid then
        found[#found + 1] = proxy
      end
    end
    return found
  end
  local function planned()
    local list = {}
    for _, proxy in ipairs(surface.find_entities_filtered({ name = "item-request-proxy" })) do
      for _, plan in ipairs(proxy.insert_plan) do
        for _, position in ipairs(plan.items.in_inventory) do
          list[#list + 1] = { plan.id.quality, position.count }
        end
      end
    end
    return list
  end
  local function free(index)
    chest[index].name, chest[index].count, chest[index].valid_for_read = nil, 0, false
  end
  return planned, free
end
-- Whether the plans are `expected`, { quality, count } each, in any order: the game reads them back
-- sorted by quality, not in the order asked.
local function plans_are(planned, expected)
  local function sorted(list)
    local copy = {}
    for index, plan in ipairs(list) do
      copy[index] = plan[1] .. " " .. plan[2]
    end
    table.sort(copy)
    return table.concat(copy, ", ")
  end
  return sorted(planned()) == sorted(expected)
end

do -- Freighters asked for while the truck chest has no free stack keep the quality each was asked
  -- for at: one of another quality asked for next doesn't change them (the review of 7145d36: a
  -- normal one waiting, then a rare one, brought two rare). As stacks free up they are requested in
  -- the order asked, each quality its own stack; the same quality twice shares one.
  for _, case in ipairs({ { nil, "rare" }, { "rare", nil }, { "rare", "rare" } }) do
    local logistics = reset()
    local request = supplied(logistics, 0)
    local planned, free = full_truck_chest(request, 2)
    local first, second = case[1], case[2]
    local named = tostring(first) .. " then " .. tostring(second)
    check(named .. ": nothing is requested yet", logistics.request_freighters(request, 1, first) == 0)
    check(named .. ": still nothing", logistics.request_freighters(request, 1, second) == 0)
    free(2)
    game.tick = 60
    logistics.on_tick()
    local normal = "normal"
    if first == second then
      check(named .. ": once a stack is free, both share it", plans_are(planned, { { first, 2 } }))
    else
      check(
        named .. ": once a stack is free, the first asked for is requested, at its quality",
        plans_are(planned, { { first or normal, 1 } })
      )
      free(1)
      game.tick = 120
      logistics.on_tick()
      check(
        named .. ": and then the second, at its own",
        plans_are(planned, { { first or normal, 1 }, { second or normal, 1 } })
      )
    end
  end
end

do -- A quality asked for again after another keeps its place: rare, normal and rare asked for with no
  -- free stack wait in that order, and a rare one put in by hand counts for the last ask, so robots
  -- bring the rare and the normal asked first (the review of 52f7016: the two rare asks were joined,
  -- ahead of the normal, and robots brought two rare).
  local logistics = reset()
  local request = supplied(logistics, 0)
  local planned, free = full_truck_chest(request, 2)
  logistics.request_freighters(request, 1, "rare")
  logistics.request_freighters(request, 1)
  logistics.request_freighters(request, 1, "rare")
  local waiting = storage.depots[request.unit_number].replenishment.waiting
  check(
    "rare, normal, rare: each waits in the order asked",
    #waiting == 3 and waiting[1].quality == "rare" and waiting[2].quality == nil and waiting[3].quality == "rare"
  )
  assert(logistics.put_freighters(request, graded("jatz-quinityn-freighter", 1, "rare")) == 1)
  free(1)
  free(2)
  game.tick = 60
  logistics.on_tick()
  check(
    "a rare one put in by hand: robots bring the first rare and the normal",
    plans_are(planned, { { "rare", 1 }, { "normal", 1 } })
  )
end

do -- Freighters asked for with free stacks are requested at once, and the game reads their plans back
  -- sorted by quality and joined by quality; freighters put in by hand still count for the last
  -- asks, whatever their own quality (the review of 0e0a596: rare then normal asked, a normal put in
  -- by hand cancelled the rare, and robots still brought a normal).
  for _, case in ipairs({
    { asks = { "rare", "normal" }, by_hand = { "normal" }, left = { { "rare", 1 } } },
    { asks = { "normal", "rare" }, by_hand = { "normal" }, left = { { "normal", 1 } } },
    { asks = { "rare", "normal" }, by_hand = { "rare" }, left = { { "rare", 1 } } },
    { asks = { "rare", "normal", "rare" }, by_hand = { "normal" }, left = { { "rare", 1 }, { "normal", 1 } } },
    { asks = { "rare", "normal", "rare" }, by_hand = { "normal", "normal" }, left = { { "rare", 1 } } },
  }) do
    local logistics = reset()
    local request = supplied(logistics, 0)
    local planned, free = full_truck_chest(request, 3)
    for index = 1, 3 do
      free(index)
    end
    for _, grade in ipairs(case.asks) do
      assert(logistics.request_freighters(request, 1, grade) == 1)
    end
    for _, grade in ipairs(case.by_hand) do
      assert(logistics.put_freighters(request, graded("jatz-quinityn-freighter", 1, grade)) == 1)
    end
    check(
      table.concat(case.asks, ", ")
        .. " asked, "
        .. table.concat(case.by_hand, " and ")
        .. " by hand: the first asks are left",
      plans_are(planned, case.left)
    )
  end
end

do -- Freighters waiting for a free stack at a quality a mod change took away are asked for as normal.
  local logistics = reset()
  local request = supplied(logistics, 0)
  local planned, free = full_truck_chest(request, 2)
  logistics.request_freighters(request, 1, "rare")
  local saved = prototypes.quality.rare
  prototypes.quality.rare = nil
  logistics.add_all()
  free(1)
  game.tick = 60
  logistics.on_tick()
  check("the rare one waiting becomes a normal one", plans_are(planned, { { "normal", 1 } }))
  prototypes.quality.rare = saved
end

do -- Lost freighters waiting for a free stack: each replacement is of its own freighter's quality,
  -- whichever was lost first (the review of 7145d36: a legendary and then a rare lost brought two
  -- rare).
  for _, order in ipairs({ { "legendary", "rare" }, { "rare", "legendary" } }) do
    local logistics = reset()
    local request = supplied(logistics, 0)
    assert(logistics.put_freighters(request, graded("jatz-quinityn-freighter", 1, "legendary")) == 1)
    assert(logistics.put_freighters(request, graded("jatz-quinityn-freighter", 1, "rare")) == 1)
    local planned, free = full_truck_chest(request, 2)
    logistics.on_tick()
    answer(logistics, 1, "route")
    game.tick = 60
    forget_roads()
    logistics.on_tick()
    answer(logistics, 2, "route")
    local by_quality = {}
    for _, trip in ipairs(trips_from(request)) do
      by_quality[trip.freighter_quality] = trip
    end
    check("setup: a legendary and a rare freighter out", by_quality.legendary and by_quality.rare)
    for _, grade in ipairs(order) do
      local trip = by_quality[grade]
      logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = trip.drone.unit_number })
    end
    local named = order[1] .. " lost, then " .. order[2]
    check(named .. ": no stack free, nothing requested yet", #planned() == 0)
    free(1)
    free(2)
    game.tick = 120
    logistics.on_tick()
    check(
      named .. ": once stacks are free, a replacement of each quality",
      plans_are(planned, { { order[1], 1 }, { order[2], 1 } })
    )
  end
end

do -- A quality a mod change took away (the Quality mod removed) is forgotten, as the game's calls
  -- would refuse it: requests for it become normal, any quality stays any, trips plan none of it.
  local logistics = reset()
  local request, provider = quality_pair(logistics, 100, nil, "any", { { "rare", 15 }, { "legendary", 30 } }, 1)
  local rare = entity("jatz-request-depot", 0.5, 20.5)
  logistics.add(rare)
  assert(logistics.set_request(rare, "a", 10, "rare", "≥"))
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(request)[1]
  check("setup: rare and legendary promised", trip.mix.rare == 15 and trip.mix.legendary == 30)
  local saved = prototypes.quality.rare
  prototypes.quality.rare = nil
  logistics.add_all()
  local got = logistics.get_request(rare)
  check("a request for a lost quality becomes normal", got.quality == nil and got.comparator == nil)
  check("any quality stays any", logistics.get_request(request).comparator == "any")
  check("a trip plans none of it", trip.mix.legendary == 30 and not trip.mix.rare and trip.planned == 30)
  check("nor is any promised", storage.promise_totals[provider.unit_number]["a/rare"] == nil)
  prototypes.quality.rare = saved
end

do -- Freighters on the road whose quality a mod change took away count as normal, and drive at a
  -- normal freighter's speed: no rare speed kept for the rest of the trip, a dry one still crawling.
  local logistics = reset()
  local request = entity("jatz-request-depot", 0.5, 0.5)
  local provider = entity("jatz-provider-depot", 10.5, 0.5, { a = 500 })
  logistics.add(request)
  logistics.add(provider)
  assert(logistics.set_request(request, "a", 500))
  assert(logistics.put_freighters(request, graded("jatz-quinityn-freighter", 2, "rare")) == 2)
  logistics.on_tick()
  answer(logistics, 1, "route")
  game.tick = 60
  forget_roads()
  logistics.on_tick()
  answer(logistics, #requests, "route")
  local trips = trips_from(request)
  local driving, dry = trips[1], trips[2]
  check("setup: two rare freighters out", #trips == 2 and math.abs(driving.drone.speed - 0.2 * 1.6) < 1e-9)
  dry.energy = 0
  game.tick = 120
  logistics.on_tick()
  check("setup: one runs dry", dry.dry and math.abs(dry.drone.speed - 0.2 * 1.6 * 0.1) < 1e-9)
  local saved = prototypes.quality.rare
  prototypes.quality.rare = nil
  logistics.add_all()
  check("its freighter counts as normal", driving.freighter_quality == nil and dry.freighter_quality == nil)
  check("and drives at a normal freighter's speed", math.abs(driving.drone.speed - 0.2) < 1e-9)
  check("a dry one crawls at a normal freighter's share", math.abs(dry.drone.speed - 0.2 * 0.1) < 1e-9)
  prototypes.quality.rare = saved
end

do -- Room by quality, not in all (Claude's review): a depot taking rare and better, whose only room
  -- is 20 in a part-filled rare stack, sends no freighter for a provider's legendary (it would load
  -- nothing, over and over, or bring what has to be spilled), and says it is full.
  local logistics = reset()
  local request = quality_pair(logistics, 1000, "rare", ">=", { { "legendary", 30 } }, 2)
  local chest = script_inventory(1)
  chest[1].name, chest[1].count, chest[1].valid_for_read, chest[1].quality = "a", 30, true, { name = "rare" }
  chest.get_insertable_count = function(id)
    local grade = type(id) == "table" and id.quality or "normal"
    return grade == "rare" and 20 or 0
  end
  request.get_inventory = function()
    return chest
  end
  local depot = storage.depots[request.unit_number]
  local _, room, _, _, fits = logistics.graded_need(depot, chest, depot.request)
  check("setup: room for 20, all of it rare", room == 20 and fits.partial.rare == 20 and fits.empty == 0)
  for second = 0, 2 do
    game.tick = 60 * second
    forget_roads()
    logistics.on_tick()
  end
  check("no freighter goes for the legendary", #requests == 0 and not has_trip(request))
  check("and it says it is full", logistics.get_status(request) == "full")
end

do -- What is coming that needs more empty stacks than there are leaves no room (Claude's review).
  local logistics = reset()
  local request = quality_pair(logistics, 1000, nil, "any", { { "rare", 10 } }, 1)
  local depot = storage.depots[request.unit_number]
  logistics.on_tick()
  answer(logistics, 1, "route")
  check("setup: 10 rare coming", trips_from(request)[1].mix.rare == 10)
  -- Now the chest is full: no empty stack, no part-filled one.
  local chest = script_inventory(1)
  chest[1].name, chest[1].count, chest[1].valid_for_read, chest[1].quality = "b", 50, true, { name = "normal" }
  chest.get_insertable_count = function()
    return 0
  end
  local _, room, _, _, fits = logistics.graded_need(depot, chest, depot.request)
  check("a full chest has no room, whatever is coming", room == 0 and fits.partial.rare == 0)
end

do -- A freighter bringing rare cargo home is counted by quality even when what it brings is filed
  -- afresh (a configuration change), after its mix is gone (Claude's review: it was counted as
  -- normal, and its depot sent for the 15 again).
  local logistics = reset()
  local request = quality_pair(logistics, 30, "rare", nil, { { "normal", 40 }, { "rare", 15 } })
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(request)[1]
  arrive(logistics, trip)
  local depot = storage.depots[request.unit_number]
  check("setup: 15 rare on the way home", trip.state == "to-request" and logistics.missing(depot) == 15)
  logistics.add_all()
  check("still coming after everything is filed afresh", logistics.missing(depot) == 15)
end

do -- Cargo of a quality its request no longer takes still comes home, and keeps its room: a depot
  -- with one stack, whose freighter loaded a rare plate before its request changed, sends no other
  -- freighter for what it takes now until that is in (the review of 52f7016: a second freighter
  -- brought an epic one first, and the rare one was left on the ground). So for exactly epic, at
  -- least epic (several qualities), normal (a plain request), and any quality narrowed to at least
  -- epic.
  for _, case in ipairs({
    { "rare", nil, "epic", nil },
    { "rare", nil, "epic", ">=" },
    { "rare", nil, nil, nil },
    { nil, "any", "epic", ">=" },
  }) do
    local named = tostring(case[3]) .. " " .. tostring(case[4]) .. " after " .. tostring(case[1] or case[2])
    local logistics = reset()
    local request, provider = quality_pair(logistics, 50, case[1], case[2], { { "rare", 1 } }, 2)
    local other = entity("jatz-provider-depot", 20.5, 0.5)
    graded_stock(other, { { "epic", 1 }, { "normal", 1 } })
    logistics.add(other)
    -- One stack, with the game's room: a stack holds one quality, 50 of item a.
    local chest = script_inventory(1)
    chest.get_insertable_count = function(id)
      local grade = type(id) == "table" and id.quality or "normal"
      local slot = chest[1]
      if not slot.valid_for_read then
        return 50
      end
      return slot.quality and slot.quality.name == grade and 50 - slot.count or 0
    end
    request.get_inventory = function()
      return chest
    end
    logistics.on_tick()
    answer(logistics, 1, "route")
    local trip = trips_from(request)[1]
    check(named .. ": setup: a freighter for the rare plate", trip and trip.provider == provider.unit_number)
    arrive(logistics, trip)
    check(
      named .. ": setup: it brings the rare plate home",
      trip.state == "to-request" and trip.cargo.get_item_count({ name = "a", quality = "rare" }) == 1
    )
    assert(logistics.set_request(request, "a", 50, case[3], case[4]))
    local asked = #requests
    for second = 1, 3 do
      game.tick = 60 * second
      forget_roads()
      logistics.on_tick()
    end
    check(named .. ": no other freighter goes while the rare one takes the only stack", #requests == asked)
    check(named .. ": nor is it counted as wanted", logistics.missing(storage.depots[request.unit_number]) == 50)
    arrive(logistics, trip)
    check(named .. ": the rare plate goes in, none left on the ground", count_of(chest, "rare") == 1)
  end
end

do -- A freighter whose promise a request change dropped (another item, then back) has nothing to
  -- fetch: its provider removed, it goes home empty rather than look for another, over and over (the
  -- review of 52f7016: every road found started the same search again, and it never came home).
  for _, plain in ipairs({ true, false }) do
    local grade = not plain and "rare" or nil
    local named = tostring(grade)
    local logistics = reset()
    local request, near = quality_pair(logistics, 100, grade, nil, { { grade or "normal", 30 } }, 1)
    local far = entity("jatz-provider-depot", 40.5, 0.5)
    graded_stock(far, { { grade or "normal", 50 } })
    logistics.add(far)
    logistics.on_tick()
    answer(logistics, 1, "route")
    local trip = trips_from(request)[1]
    check(named .. ": setup: a freighter out for 30", trip and trip.planned == 30)
    assert(logistics.set_request(request, "b", 100))
    assert(logistics.set_request(request, "a", 100, grade))
    check(named .. ": setup: its promise dropped", trip.planned == 0)
    near.valid = false
    logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = near.unit_number })
    for _ = 1, 4 do
      if trip.search then
        answer(logistics, #requests, "route")
      end
    end
    check(named .. ": it stops looking", trip.search == nil)
    check(named .. ": and heads home", trip.state == "to-request")
    arrive(logistics, trip)
    local home, out = logistics.freighter_counts(request)
    check(named .. ": where it parks", home == 1 and out == 0)
  end
end

do -- A request or buffer depot replaced by itself at a lower quality has a smaller chest or tank:
  -- its request carries on, but never above what the new one holds (set_request's limit), so a
  -- request for more than fits doesn't wait for a full load it can never take. Item and liquid
  -- depots, request and buffer alike; a better one keeps the request it had.
  local function replace(logistics, old, new)
    old.valid = false
    logistics.replaced(old.unit_number, new)
  end
  -- A depot of `slots` slots (item a stacks to 50), as the game sizes a chest by quality.
  local function sized(role, slots)
    local made = entity(role, 0.5, 0.5)
    local chest = script_inventory(slots)
    made.get_inventory = function()
      return chest
    end
    return made
  end
  local logistics = reset()
  for _, role in ipairs({ "jatz-request-depot", "jatz-buffer-depot" }) do
    local old = sized(role, 4)
    logistics.add(old)
    assert(logistics.set_request(old, "a", 200, "rare", "≥"))
    local worse = sized(role, 1)
    replace(logistics, old, worse)
    local got = logistics.get_request(worse)
    check(
      role .. ": a smaller chest caps the request at its slots, keeping the item and quality",
      got.count == 50 and got.item == "a" and got.quality == "rare" and got.comparator == "≥"
    )
    local better = sized(role, 8)
    replace(logistics, worse, better)
    check(role .. ": a bigger one doesn't raise it", logistics.get_request(better).count == 50)
    assert(logistics.set_request(better, "a", 120))
    local same = sized(role, 8)
    replace(logistics, better, same)
    check(role .. ": and a request that still fits is left alone", logistics.get_request(same).count == 120)
  end
  for _, role in ipairs({ "jatz-liquid-request-depot", "jatz-liquid-buffer-depot" }) do
    local old = tank(role, 0.5, 0.5, "water", 0)
    logistics.add(old)
    assert(logistics.set_request(old, "water", 20000))
    local worse = tank(role, 0.5, 0.5, "water", 0)
    worse.get_fluid_capacity = function()
      return 15000.9
    end
    replace(logistics, old, worse)
    check(role .. ": a smaller tank caps the request at its size", logistics.get_request(worse).count == 15000)
    local better = tank(role, 0.5, 0.5, "water", 0)
    replace(logistics, worse, better)
    check(role .. ": a bigger one doesn't raise it", logistics.get_request(better).count == 15000)
  end
  -- A request for an item the game no longer has is left to the cleanup that forgets it.
  local old = sized("jatz-request-depot", 4)
  logistics.add(old)
  assert(logistics.set_request(old, "a", 10))
  storage.depots[old.unit_number].request.item = "gone"
  local new = sized("jatz-request-depot", 1)
  replace(logistics, old, new)
  check("a request for an item that is gone is not looked up", storage.depots[new.unit_number].request.count == 10)
  -- With 'Full loads only' the capped request is one a freighter can fill: it sets off. (Kept at 200
  -- in a chest of 50, it waited for a full load of 100 that never fits.)
  logistics = reset()
  local wide = sized("jatz-request-depot", 4)
  local provider = entity("jatz-provider-depot", 10.5, 0.5)
  graded_stock(provider, { { "normal", 500 } })
  logistics.add(wide)
  logistics.add(provider)
  assert(logistics.set_request(wide, "a", 200))
  logistics.set_full_loads(wide, true)
  assert(logistics.put_freighters(wide, stack("jatz-quinityn-freighter", 2)) == 2)
  local narrow = sized("jatz-request-depot", 1)
  local chest = narrow.get_inventory()
  chest.get_item_count = function()
    return 0
  end
  chest.get_insertable_count = function()
    return 50
  end
  replace(logistics, wide, narrow)
  logistics.on_tick()
  answer(logistics, 1, "route")
  check("a replaced depot set to full loads sends a freighter for what fits", has_trip(narrow))
end

do -- A Fuel depot replaced by itself at another quality keeps the freighters heading for it.
  local logistics = reset()
  local request = supplied(logistics, 1)
  local fuel = entity("jatz-fuel-depot", 5.5, 10.5)
  logistics.add(fuel)
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(request)[1]
  trip.refuel = fuel.unit_number
  local better = entity("jatz-fuel-depot", 5.5, 10.5)
  logistics.replaced(fuel.unit_number, better)
  check("its freighter heads for the new one", trip.refuel == better.unit_number)
end

do -- A provider replaced by itself at another quality while a freighter is on its way there: the
  -- promise moves with it, and goes once the freighter has loaded, for a promise of one key (normal
  -- items, a fluid) and of several qualities alike, so what is put in it later is free for the next
  -- freighter (the review of 7145d36: the promise stayed filed under the old one, never let go).
  local function upgraded(logistics, provider, made)
    local better = made()
    provider.valid = false
    logistics.replaced(provider.unit_number, better)
    return better
  end
  local function nothing_promised(provider)
    return storage.promised[provider.unit_number] == nil and storage.promise_totals[provider.unit_number] == nil
  end

  local logistics = reset()
  local request, near = supplied(logistics, 1)
  stocked_chest(request)
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(request)[1]
  check("setup: a freighter on its way to the near provider for 30", trip.provider == near.unit_number)
  local stock
  local better = upgraded(logistics, near, function()
    local made = entity("jatz-provider-depot", 10.5, 0.5)
    stock = graded_stock(made, { { "normal", 30 } })
    return made
  end)
  check("its promise is filed at the new provider", storage.promise_totals[better.unit_number].a == 30)
  arrive(logistics, trip)
  check("it loads the 30 there", count_of(trip.cargo, "normal") == 30 and count_of(stock, "normal") == 0)
  check("and its promise there goes", nothing_promised(better))
  stock[1].name, stock[1].count, stock[1].valid_for_read, stock[1].quality = "a", 30, true, { name = "normal" }
  arrive(logistics, trip)
  game.tick = 60
  logistics.on_tick()
  local next_trip = trips_from(request)[1]
  check(
    "30 put in it later go to the next freighter",
    next_trip and next_trip.provider == better.unit_number and next_trip.planned == 30
  )

  logistics = reset()
  local provider
  request, provider = quality_pair(logistics, 100, nil, "any", { { "rare", 15 }, { "legendary", 10 } }, 1)
  logistics.on_tick()
  answer(logistics, 1, "route")
  trip = trips_from(request)[1]
  check("setup: a freighter promises rare and legendary", trip.mix.rare == 15 and trip.mix.legendary == 10)
  better = upgraded(logistics, provider, function()
    local made = entity("jatz-provider-depot", 10.5, 0.5)
    made.get_inventory = provider.get_inventory
    return made
  end)
  arrive(logistics, trip)
  check("it loads both", count_of(trip.cargo, "rare") == 15 and count_of(trip.cargo, "legendary") == 10)
  check("and its promises of both go", nothing_promised(better))

  logistics = reset()
  request = tank("jatz-liquid-request-depot", 0.5, 0.5)
  provider = tank("jatz-liquid-provider-depot", 10.5, 0.5, "water", 1000)
  logistics.add(request)
  logistics.add(provider)
  assert(logistics.set_request(request, "water", 2000))
  assert(logistics.put_freighters(request, stack("jatz-quinityn-freighter", 1)) == 1)
  logistics.on_tick()
  answer(logistics, 1, "route")
  trip = trips_from(request)[1]
  check("setup: a liquid freighter promises 750 water", trip.planned == 750)
  better = upgraded(logistics, provider, function()
    return tank("jatz-liquid-provider-depot", 10.5, 0.5, "water", 1000)
  end)
  arrive(logistics, trip)
  check("it loads 750 water", better.held.amount == 250 and trip.fluid.amount == 750)
  check("and its promise goes", nothing_promised(better))
end

print("all quality checks passed")
