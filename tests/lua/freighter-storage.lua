-- SPDX-License-Identifier: LGPL-3.0-only
-- Freighter storage on liquid request and buffer depots (scripts/logistics.lua: fluid_limit,
-- fit_request, store_in_freighters, drain_reserve). Run by tests/lua/logistics.lua, which hands it
-- its helpers (`h`): that file is at the size CI downloads.
return function(h)
  local reset, check, liquids, entity, stack = h.reset, h.check, h.liquids, h.entity, h.stack
  local script_inventory, answer, arrive, trips_from = h.script_inventory, h.answer, h.arrive, h.trips_from

  do -- Freighter storage: a liquid depot can hold, and ask for, as much as all its freighters carry.
    local logistics = reset()
    local request, provider = liquids(logistics, 1000000, 40)
    local item_depot = entity("jatz-request-depot", 30.5, 0.5)
    logistics.add(item_depot)
    check("a request above the tank is its size", logistics.get_request(request).count == 25000)
    check("keeping the amount set", logistics.get_request(request).asked == 1000000)
    request.held.name, request.held.amount = "water", 25000
    logistics.on_tick()
    check(
      "with its tank full, it asks for nothing more",
      #h.requests() == 0 and logistics.get_status(request) == "satisfied"
    )
    check("off by default", not logistics.get_freighter_storage(request))
    check("an item depot has no such setting", not logistics.set_freighter_storage(item_depot, true))
    check("ticked on a liquid request depot", logistics.set_freighter_storage(request, true))
    check("it asks for what its 40 freighters carry, 40 x 750", logistics.get_request(request).count == 30000)
    game.tick = 60
    logistics.on_tick()
    answer(logistics, #h.requests(), "route")
    local trip = trips_from(request)[1]
    check("a freighter goes though the tank is full", trip and trip.planned == 750)
    check("one out still counts", logistics.get_request(request).count == 30000)
    arrive(logistics, trip)
    arrive(logistics, trip)
    local stored = logistics.freighter_stored(request)
    check(
      "what the tank has no room for stays in the parked freighters",
      stored.fluid == "water" and stored.amount == 750 and stored.room == 5000 and request.held.amount == 25000
    )
    check("rather than going back", not storage.trips[trip.drone.unit_number] and provider.held.amount == 250)
    check("and counts as held", logistics.missing(storage.depots[request.unit_number]) == 30000 - 25750)
    request.held.amount = 24000 -- used meanwhile
    game.tick = 120
    logistics.on_tick()
    check(
      "it goes into the tank as it has room",
      request.held.amount == 24750 and logistics.freighter_stored(request).amount == 0
    )
    check(
      "unticked, it asks for the tank's size again",
      logistics.set_freighter_storage(request, false) and logistics.get_request(request).count == 25000
    )
    assert(logistics.set_freighter_storage(request, true))
    logistics.take_freighters(request, nil, nil, script_inventory(10))
    assert(logistics.put_freighters(request, stack("jatz-quinityn-freighter", 20)) == 20)
    game.tick = 180
    logistics.on_tick()
    check(
      "with fewer freighters, less: 20 x 750 is under the tank's size",
      logistics.get_request(request).count == 25000
    )
  end

  do -- An amount set that is infinity (or text too long for a number) is what the depot holds, as
    -- before `asked` was kept, for both liquid roles: no tag or blueprint can hold infinity. A
    -- finite amount above the limit is kept, and so is an infinite one in a save from before.
    local logistics = reset()
    local request = liquids(logistics, 1000000, 40)
    local buffer = h.tank("jatz-liquid-buffer-depot", 40.5, 0.5)
    logistics.add(buffer)
    for name, tank in pairs({ request = request, buffer = buffer }) do
      local depot = storage.depots[tank.unit_number]
      assert(logistics.set_request(tank, "water", math.huge))
      check(name .. ": infinity is the tank's size", logistics.get_request(tank).count == 25000)
      check(name .. ": kept as that, not as infinity", depot.request.asked == 25000)
      assert(logistics.set_request(tank, "water", tonumber("9" .. string.rep("0", 400))))
      check(name .. ": so is a number too large to hold", depot.request.count == 25000 and depot.request.asked == 25000)
      assert(logistics.set_request(tank, "water", 1e100))
      check(name .. ": a finite amount above it is kept", logistics.get_request(tank).asked == 1e100)
      depot.request.asked = math.huge -- saved by a version that kept it
      logistics.fit_request(depot)
      check(name .. ": a saved infinity is fitted too", depot.request.count == 25000 and depot.request.asked == 25000)
    end
  end

  do -- Freighter storage with the request changed to another fluid: neither goes where the other is
    -- wanted, and no freighter goes back and forth with what has nowhere to go.
    local logistics = reset()
    local request, provider = liquids(logistics, 1000000, 40)
    assert(logistics.set_freighter_storage(request, true))
    request.held.name, request.held.amount = "water", 25000
    provider.held.amount = 2000
    logistics.on_tick()
    answer(logistics, #h.requests(), "route")
    local trip = trips_from(request)[1]
    arrive(logistics, trip)
    arrive(logistics, trip)
    check("setup: 750 water in the parked freighters", logistics.freighter_stored(request).amount == 750)
    game.tick = 60
    logistics.on_tick()
    answer(logistics, #h.requests(), "route")
    trip = trips_from(request)[1]
    arrive(logistics, trip)
    assert(logistics.set_request(request, "steam", 1000000))
    arrive(logistics, trip)
    check(
      "water fetched before the request changed to steam goes back, not into the freighters",
      trip.state == "returning" and logistics.freighter_stored(request).amount == 750
    )
    arrive(logistics, trip)
    check("into its provider", provider.held.amount == 1250)
    request.held.amount = 0
    game.tick = 120
    logistics.on_tick()
    check(
      "the freighters' water isn't pumped into a tank now meant for steam",
      request.held.amount == 0 and logistics.freighter_stored(request).amount == 750
    )
    request.held.name, request.held.amount = "steam", 25000
    provider.held.name, provider.held.amount = "steam", 2000
    local asked = #h.requests()
    game.tick = 180
    logistics.on_tick()
    check(
      "with its tank full of steam, none is fetched for freighters holding water",
      #h.requests() == asked and #trips_from(request) == 0
    )
    assert(logistics.set_request(request, "water", 1000000))
    request.held.name, request.held.amount = "water", 0
    game.tick = 240
    logistics.on_tick()
    check(
      "asked for again, the water goes into the tank",
      request.held.amount == 750 and logistics.freighter_stored(request).amount == 0
    )
  end

  do -- Freighters holding a fluid whose mod was removed forget it on load (add_all), as the request
    -- and the trips do, rather than pumping a fluid the game no longer knows; other fluids stay.
    local logistics = reset()
    prototypes.fluid["mod-fluid"] = { fuel_value = 0 }
    local request = liquids(logistics, 1000000, 40)
    local buffer = h.tank("jatz-liquid-buffer-depot", 40.5, 0.5)
    local other = h.tank("jatz-liquid-request-depot", 60.5, 0.5)
    logistics.add(buffer)
    logistics.add(other)
    for _, tank in ipairs({ request, buffer, other }) do
      local insert = tank.insert_fluid
      tank.insert_fluid = function(spec) -- as the game does
        assert(prototypes.fluid[spec.name], "Unknown fluid name: " .. spec.name)
        return insert(spec)
      end
    end
    -- Ticked, asking for the mod's fluid; unticked, asking for water while holding the mod's fluid
    -- from before; ticked, holding water.
    assert(logistics.set_request(request, "mod-fluid", 1000000))
    assert(logistics.set_freighter_storage(request, true))
    assert(logistics.set_request(buffer, "water", 1000))
    assert(logistics.set_request(other, "water", 1000))
    assert(logistics.set_freighter_storage(other, true))
    storage.depots[request.unit_number].reserve = { name = "mod-fluid", amount = 750, temperature = 40 }
    storage.depots[buffer.unit_number].reserve = { name = "mod-fluid", amount = 500, temperature = 40 }
    storage.depots[other.unit_number].reserve = { name = "water", amount = 600, temperature = 60 }
    prototypes.fluid["mod-fluid"] = nil
    logistics.add_all()
    check(
      "a removed fluid's request and stored fluid are forgotten, ticked or not",
      not logistics.get_request(request)
        and not storage.depots[request.unit_number].reserve
        and not storage.depots[buffer.unit_number].reserve
        and logistics.freighter_stored(request).amount == 0
    )
    local kept = storage.depots[other.unit_number].reserve
    check(
      "another fluid's is kept as it was",
      kept and kept.name == "water" and kept.amount == 600 and kept.temperature == 60
    )
    game.tick = 60
    check("the game carries on", pcall(logistics.on_tick))
    check(
      "pumping the water into its tank",
      other.held.name == "water" and other.held.amount == 600 and other.held.temperature == 60
    )
  end
end
