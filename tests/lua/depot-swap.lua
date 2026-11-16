-- SPDX-License-Identifier: LGPL-3.0-only
-- Request and buffer depots replacing each other in place (scripts/depot-swap.lua hands the new
-- depot everything through logistics.replaced), against the fake runtime of tests/lua/harness.lua:
-- the depot's new role, promises of freighters on their way to load there, and its request capped
-- at what the new chest holds. Kept apart from tests/lua/logistics.lua to keep each file under the
-- 256 KiB CI allows.
-- Run from the repository root with Lua 5.2 (tools/test_mod_setup.py does): lua5.2 tests/lua/depot-swap.lua
package.path = "./?.lua;" .. package.path

local harness = require("tests.lua.harness")
local stack, script_inventory, entity = harness.stack, harness.script_inventory, harness.entity
local answer, arrive, forget_roads, check = harness.answer, harness.arrive, harness.forget_roads, harness.check
local trips_from = harness.trips_from
local requests
local function reset()
  local logistics = harness.reset()
  requests = select(2, harness.state())
  return logistics
end

-- Give a depot a chest of real stacks (the fake chests only count), holding `count` of `name`, of
-- `size` stacks (a depot's 48 unless given).
local function stocked(depot, name, count, size)
  size = size or 48
  local chest = script_inventory(size)
  if count then
    chest[1] = stack(name, count)
    chest[1].quality = { name = "normal" }
  end
  function chest.get_item_count(id)
    local wanted = type(id) == "table" and id.name or id
    local total = 0
    for index = 1, size do
      if chest[index].valid_for_read and chest[index].name == wanted then
        total = total + chest[index].count
      end
    end
    return total
  end
  function chest.get_insertable_count()
    return 1000
  end
  depot.get_inventory = function()
    return chest
  end
  return chest
end

do -- A request depot replaced by a buffer depot (scripts/depot-swap.lua) keeps its request and
  -- freighters and is a buffer depot: request depots fetch from it. Replaced by a request depot
  -- again, it supplies no one.
  local logistics = reset()
  local other = entity("jatz-request-depot", 10.5, 0.5)
  local swapped = entity("jatz-request-depot", 0.5, 0.5, { a = 20 })
  logistics.add(other)
  logistics.add(swapped)
  assert(logistics.set_request(other, "a", 10))
  assert(logistics.put_freighters(other, stack("jatz-quinityn-freighter", 1)) == 1)
  assert(logistics.set_request(swapped, "b", 5))
  assert(logistics.put_freighters(swapped, stack("jatz-quinityn-freighter", 2)) == 2)
  local buffer = entity("jatz-buffer-depot", 0.5, 0.5)
  buffer.get_inventory, buffer.chest = swapped.get_inventory, swapped.chest
  swapped.valid = false
  logistics.replaced(swapped.unit_number, buffer)
  logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = swapped.unit_number })
  check(
    "a request depot replaced by a buffer depot is a buffer depot with its request and freighters",
    storage.depots[buffer.unit_number].role == "buffer"
      and logistics.get_request(buffer).item == "b"
      and logistics.freighter_counts(buffer) == 2
  )
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(other)[1]
  check("a request depot fetches from it", trip and trip.provider == buffer.unit_number)

  logistics = reset()
  other = entity("jatz-request-depot", 10.5, 0.5)
  swapped = entity("jatz-buffer-depot", 0.5, 0.5, { a = 20 })
  logistics.add(other)
  logistics.add(swapped)
  assert(logistics.set_request(other, "a", 10))
  assert(logistics.put_freighters(other, stack("jatz-quinityn-freighter", 1)) == 1)
  local request = entity("jatz-request-depot", 0.5, 0.5)
  request.get_inventory, request.chest = swapped.get_inventory, swapped.chest
  swapped.valid = false
  logistics.replaced(swapped.unit_number, request)
  check(
    "a buffer depot replaced by a request depot is a request depot",
    storage.depots[request.unit_number].role == "request"
  )
  logistics.on_tick()
  check("which no request depot fetches from", #requests == 0 and next(storage.depots[other.unit_number].trips) == nil)
end

do -- A buffer depot replaced by a request depot (scripts/depot-swap.lua) while a freighter is on
  -- its way to load there: the freighter loads, and its promise goes with it, so once the depot is
  -- a buffer depot again, what it still holds is free for the next request.
  local logistics = reset()
  local other = entity("jatz-request-depot", 10.5, 0.5)
  local swapped = entity("jatz-buffer-depot", 0.5, 0.5)
  local stock = stocked(swapped, "a", 20)
  local home = stocked(other)
  logistics.add(other)
  logistics.add(swapped)
  assert(logistics.set_request(other, "a", 10))
  assert(logistics.put_freighters(other, stack("jatz-quinityn-freighter", 1)) == 1)
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(other)[1]
  check("setup: a freighter is on its way to the buffer depot for 10", trip and trip.planned == 10)
  local function replace(old, name)
    local new = entity(name, 0.5, 0.5)
    new.get_inventory, new.chest = old.get_inventory, old.chest
    old.valid = false
    logistics.replaced(old.unit_number, new)
    logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = old.unit_number })
    logistics.on_depot_changed(new)
    return new
  end
  local request = replace(swapped, "jatz-request-depot")
  check(
    "its promise is filed where it is kept, at the new depot",
    trip.promise.provider == request.unit_number and storage.promise_totals[request.unit_number].a == 10
  )
  arrive(logistics, trip) -- at the depot
  arrive(logistics, trip) -- home
  check("it loads there and unloads at home", stock.get_item_count("a") == 10 and home.get_item_count("a") == 10)
  check(
    "and the depot keeps no promise for it",
    storage.promised[request.unit_number] == nil and storage.promise_totals[request.unit_number] == nil
  )
  local buffer = replace(request, "jatz-buffer-depot")
  assert(logistics.set_request(other, "a", 20))
  forget_roads()
  game.tick = 60
  logistics.on_tick()
  answer(logistics, #requests, "route")
  trip = trips_from(other)[1]
  check(
    "a buffer depot again, the 10 it holds go to the next request",
    trip and trip.provider == buffer.unit_number and trip.planned == 10
  )
end

do -- A request carried to the other kind of depot (scripts/depot-swap.lua) is at most what the new
  -- chest holds, as any request is (logistics.set_request): request and buffer depots' slots are
  -- separate startup settings. With "Full loads only", the full load is then one it has room for.
  local logistics = reset()
  local swapped = entity("jatz-buffer-depot", 0.5, 0.5)
  stocked(swapped, nil, nil, 48)
  local provider = entity("jatz-provider-depot", 10.5, 0.5)
  stocked(provider, "a", 150)
  logistics.add(swapped)
  logistics.add(provider)
  assert(logistics.set_request(swapped, "a", 200))
  assert(logistics.set_full_loads(swapped, true))
  assert(logistics.put_freighters(swapped, stack("jatz-quinityn-freighter", 1)) == 1)
  -- A request depot of 2 slots: 100 of an item stacking to 50.
  local request = entity("jatz-request-depot", 0.5, 0.5)
  stocked(request, nil, nil, 2)
  swapped.valid = false
  logistics.replaced(swapped.unit_number, request)
  logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = swapped.unit_number })
  check(
    "a buffer depot's request above what the smaller request depot holds is what it holds",
    logistics.get_request(request).item == "a"
      and logistics.get_request(request).count == 100
      and logistics.get_full_loads(request) == true
  )
  logistics.on_depot_changed(request)
  logistics.on_tick()
  answer(logistics, #requests, "route")
  local trip = trips_from(request)[1]
  check("and a full load of it is sent for", trip and trip.provider == provider.unit_number and trip.planned == 100)

  -- A request depot's request carried to a buffer depot with fewer slots, the same.
  logistics = reset()
  swapped = entity("jatz-request-depot", 0.5, 0.5)
  stocked(swapped, nil, nil, 48)
  logistics.add(swapped)
  assert(logistics.set_request(swapped, "a", 2400))
  local buffer = entity("jatz-buffer-depot", 0.5, 0.5)
  stocked(buffer, nil, nil, 10)
  swapped.valid = false
  logistics.replaced(swapped.unit_number, buffer)
  check(
    "a request depot's request is at most what the smaller buffer depot holds",
    logistics.get_request(buffer).count == 500
  )
end

-- Replacing the home must not reinterpret a pickup already admitted for a requester as a new
-- buffer pull. Both requester source modes can collect from a buffer, with either startup value.
for _, enabled in ipairs({ false, true }) do
  for _, preferred in ipairs({ false, true }) do
    for _, legacy in ipairs({ false, true }) do
      local logistics = reset()
      harness.STARTUP["jatz-buffer-priority-pull"].value = enabled
      local home = entity("jatz-request-depot", 0.5, 0.5)
      local source = entity("jatz-buffer-depot", 20.5, 0.5)
      local received, stock = stocked(home), stocked(source, "a", 20)
      logistics.add(home)
      logistics.add(source)
      assert(logistics.set_request(home, "a", 10))
      assert(logistics.set_from_buffers(home, preferred))
      assert(logistics.put_freighters(home, stack("jatz-quinityn-freighter", 1)) == 1)
      logistics.on_tick()
      answer(logistics, 1, "route")
      local trip = trips_from(home)[1]
      check("requester dispatched to buffer before home replacement", trip and trip.provider == source.unit_number)
      local replacement = entity("jatz-buffer-depot", 0.5, 0.5)
      replacement.get_inventory, replacement.chest = home.get_inventory, home.chest
      home.valid = false
      logistics.replaced(home.unit_number, replacement)
      logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = home.unit_number })
      logistics.on_depot_changed(replacement)
      if legacy then
        -- Saved by a version from before pickup admission was recorded, after its home was
        -- replaced: a buffer home with a buffer source, which that version never dispatched.
        trip.buffer_pull = nil
      end
      -- Saved trips survive module reload and configuration reconciliation with their admission.
      package.loaded["scripts.logistics"] = nil
      logistics = require("scripts.logistics")
      logistics.add_all()
      arrive(logistics, trip)
      arrive(logistics, trip)
      check(
        "requester pickup finishes after home becomes buffer and reloads",
        received.get_item_count("a") == 10
          and stock.get_item_count("a") == 10
          and #trips_from(replacement) == 0
          and logistics.freighter_counts(replacement) == 1
      )
    end
  end
end
harness.STARTUP["jatz-buffer-priority-pull"].value = false

-- A reroute is a new source selection: it uses the home's role at that selection, rather than
-- inheriting the pickup rule from the original trip. Exercise both changes of admission.
for _, buffer_first in ipairs({ false, true }) do
  local logistics = reset()
  harness.STARTUP["jatz-buffer-priority-pull"].value = true
  local home = entity(buffer_first and "jatz-buffer-depot" or "jatz-request-depot", 0.5, 0.5)
  local source = entity(buffer_first and "jatz-buffer-depot" or "jatz-provider-depot", 20.5, 0.5)
  local alternate = entity("jatz-buffer-depot", 40.5, 0.5)
  local received, stock = stocked(home), stocked(source, "a", 20)
  local alternate_stock = stocked(alternate, "a", 20)
  for _, depot in ipairs({ home, source, alternate }) do
    logistics.add(depot)
  end
  if buffer_first then
    logistics.set_priority(home, 8)
    logistics.set_priority(source, 6)
  else
    logistics.set_priority(source, 10)
  end
  logistics.set_priority(alternate, 4)
  logistics.set_request(home, "a", 10)
  logistics.put_freighters(home, stack("jatz-quinityn-freighter", 1))
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(home)[1]
  check("reroute starts with the original supplier", trip and trip.provider == source.unit_number)
  local function replace(name)
    local replacement = entity(name, 0.5, 0.5)
    replacement.get_inventory, replacement.chest = home.get_inventory, home.chest
    home.valid = false
    logistics.replaced(home.unit_number, replacement)
    logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = home.unit_number })
    logistics.on_depot_changed(replacement)
    home = replacement
  end
  replace(buffer_first and "jatz-request-depot" or "jatz-buffer-depot")
  stock[1].clear()
  arrive(logistics, trip)
  answer(logistics, #requests, "route")
  check("empty source reroutes to the other buffer", trip.provider == alternate.unit_number)
  if buffer_first then
    replace("jatz-buffer-depot")
  end
  logistics.set_priority(alternate, logistics.get_priority(home))
  arrive(logistics, trip)
  arrive(logistics, trip)
  check(
    "rerouted pickup retains the admission of its selected source",
    received.get_item_count("a") == (buffer_first and 10 or 0)
      and alternate_stock.get_item_count("a") == (buffer_first and 10 or 20)
      and #trips_from(home) == 0
      and logistics.freighter_counts(home) == 1
  )
end
harness.STARTUP["jatz-buffer-priority-pull"].value = false

do -- A saved buffer pull keeps its admission through reload, so pickup still checks priority.
  local logistics = reset()
  harness.STARTUP["jatz-buffer-priority-pull"].value = true
  local home = entity("jatz-buffer-depot", 0.5, 0.5)
  local source = entity("jatz-buffer-depot", 20.5, 0.5)
  local received, stock = stocked(home), stocked(source, "a", 20)
  logistics.add(home)
  logistics.add(source)
  logistics.set_priority(home, 8)
  logistics.set_request(home, "a", 10)
  logistics.put_freighters(home, stack("jatz-quinityn-freighter", 1))
  logistics.on_tick()
  answer(logistics, 1, "route")
  local trip = trips_from(home)[1]
  check("saved buffer pickup was admitted upward", trip and trip.provider == source.unit_number)
  logistics.set_priority(source, 8)
  package.loaded["scripts.logistics"] = nil
  logistics = require("scripts.logistics")
  logistics.add_all()
  arrive(logistics, trip)
  arrive(logistics, trip)
  check(
    "saved buffer pickup rechecks priority after reload",
    received.get_item_count("a") == 0 and stock.get_item_count("a") == 20 and #trips_from(home) == 0
  )
  harness.STARTUP["jatz-buffer-priority-pull"].value = false
end

print("all depot swap checks passed")
