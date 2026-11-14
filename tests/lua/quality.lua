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

print("all quality checks passed")
