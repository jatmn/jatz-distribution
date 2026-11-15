-- SPDX-License-Identifier: LGPL-3.0-only
-- A large group of request depots (fetching the same item on one surface) is checked over several
-- ticks, a few depots each, and still decides together (scripts/logistics.lua: depots_due). Run by
-- tests/lua/logistics.lua, which is at the size CI downloads.
local harness = require("tests.lua.harness")
local entity, stack, check, trips_from = harness.entity, harness.stack, harness.check, harness.trips_from

-- Ten request depots for 100 of item a, with a near provider holding one freighter's load and a
-- far one holding plenty. The pathfinder answers each question in the tick it is asked, after the
-- tick's depot checks, as in the game.
local logistics, requests, near, far, depots
local function setup()
  logistics = harness.reset()
  local _
  _, requests = harness.state()
  near = entity("jatz-provider-depot", 10.5, 0.5, { a = 100 })
  far = entity("jatz-provider-depot", 200.5, 0.5, { a = 100000 })
  logistics.add(near)
  logistics.add(far)
  depots = {}
  for index = 1, 10 do
    local request = entity("jatz-request-depot", 0.5 + 3 * index, 20.5)
    logistics.add(request)
    assert(logistics.set_request(request, "a", 100))
    assert(logistics.put_freighters(request, stack("jatz-quinityn-freighter", 2)) == 2)
    depots[index] = request
  end
end
setup()

local function trips()
  local list = {}
  for _, trip in pairs(storage.trips) do
    list[#list + 1] = trip
  end
  return list
end

-- A second of spread checks from `from` (`ahead`, if given, runs before each tick's). Returns the
-- tick each depot asked the pathfinder in (by unit number), how many asked in each tick, and the
-- freighters out after each tick.
local function second(from, ahead)
  local asked, in_tick, out = {}, {}, {}
  for tick = from, from + 59 do
    game.tick = tick
    if ahead then
      ahead(tick)
    end
    local before = #requests
    logistics.on_tick_share(tick)
    for id = before + 1, #requests do
      local unit = storage.searches[id].request
      asked[unit] = asked[unit] and -1 or tick
      in_tick[tick] = (in_tick[tick] or 0) + 1
    end
    for id = before + 1, #requests do
      logistics.on_script_path_request_finished({ id = id, path = { { position = requests[id].goal } } })
    end
    out[tick] = #trips()
  end
  return asked, in_tick, out
end

local asked, in_tick, out = second(0)
local once, first, last, most = true, math.huge, -1, 0
for _, request in ipairs(depots) do
  local tick = asked[request.unit_number]
  once = once and tick ~= nil and tick >= 0
  first, last = math.min(first, tick or first), math.max(last, tick or last)
end
for _, count in pairs(in_tick) do
  most = math.max(most, count)
end
check("in a second, every depot of a large group searches once", once and #requests == 10)
check(
  "a few in a tick, over the ticks after the group's own",
  most <= logistics.group_share and last - first == math.ceil(10 / logistics.group_share) - 1
)
check("none sends a freighter before the last of the group has looked", out[last - 1] == 0 and out[last] == 1)
local sent = trips()
check(
  "they decide together: one freighter goes for the near stock, and nothing for the far provider",
  #sent == 1 and sent[1].provider == near.unit_number and out[59] == 1
)
local sender = storage.depots[sent[1].request]
check(
  "the wait for the last of its group doesn't delay a depot's next freighter",
  asked[sent[1].request] == first and sender.next_send == first + 60
)

-- The next second, from the roads they remember: the near provider has another load.
near.chest.contents.a = 200
local again, _, out_again = second(60)
sent = trips()
check("from remembered roads they ask nothing", next(again) == nil and #requests == 10)
check(
  "and still decide together, once the last has looked",
  out_again[60 + last - 1] == 1
    and #sent == 2
    and sent[1].provider == near.unit_number
    and sent[2].provider == near.unit_number
)

-- A provider gone (with no event yet) between the group's ticks is left out by the depots checked
-- after: they look to the far one, as depots checked in a later tick always did.
near.chest.contents.a = 300
for tick = 120, 120 + first do
  game.tick = tick
  logistics.on_tick_share(tick)
end
near.valid = false
for tick = 121 + first, 120 + last do
  game.tick = tick
  logistics.on_tick_share(tick)
end
local to_far = 0
for id = 11, #requests do
  to_far = to_far + (requests[id].goal.x == 200.5 and 1 or 0)
end
check(
  "a provider gone between the group's ticks is left out by the depots checked after",
  to_far > 0 and to_far == #requests - 10
)

-- What makes a provider one to fetch from can change between the group's ticks with no event: an
-- inserter empties it, a script gives it to another force. The depots checked after the change look
-- at it again, as depots checked in a later tick always did (Pullfrog's review of 773be46: they were
-- given the group's first look, and fetched nothing, or from the other force's depot).
local function changed_between(change)
  setup()
  local looked = second(0, function(tick)
    if tick == first + 1 then
      change()
    end
  end)
  local after, right = 0, 0
  for _, request in ipairs(depots) do
    if looked[request.unit_number] > first then
      after = after + 1
      local fetching = trips_from(request)
      right = right + ((#fetching == 1 and fetching[1].provider == far.unit_number) and 1 or 0)
    end
  end
  return after, right
end

local after, right = changed_between(function()
  near.chest.contents.a = 0
end)
check(
  "the near provider emptied between the group's ticks, every depot checked after fetches from the far one",
  after == #depots - logistics.group_share and right == after
)
after, right = changed_between(function()
  near.force_index = 2
end)
check(
  "the near provider given to another force between the group's ticks, every depot checked after fetches from the far one",
  after == #depots - logistics.group_share and right == after
)
