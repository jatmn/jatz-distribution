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

  do -- An amount set that is infinity (or text too long for a number) asks to fill the depot, for
    -- both liquid roles: kept as the most a blueprint parameter holds, as no tag or blueprint can
    -- hold infinity, so it follows the limit like any amount above it. A finite amount above the
    -- limit is kept, and an infinite one in a save from before is fitted the same way.
    local logistics = reset()
    local fill = logistics.request_fill
    local request = liquids(logistics, 1000000, 40)
    local buffer = h.tank("jatz-liquid-buffer-depot", 40.5, 0.5)
    logistics.add(buffer)
    assert(logistics.put_freighters(buffer, stack("jatz-quinityn-freighter", 40)) == 40)
    check("filling is a blueprint parameter's most", fill == 2147483647)
    for name, tank in pairs({ request = request, buffer = buffer }) do
      local depot = storage.depots[tank.unit_number]
      assert(logistics.set_request(tank, "water", math.huge))
      check(name .. ": infinity is the tank's size", logistics.get_request(tank).count == 25000)
      check(name .. ": kept as filling the depot, not as infinity", depot.request.asked == fill)
      assert(logistics.set_freighter_storage(tank, true))
      check(name .. ": so it follows the limit", logistics.get_request(tank).count == 30000)
      assert(logistics.set_freighter_storage(tank, false))
      assert(logistics.set_request(tank, "water", tonumber("9" .. string.rep("0", 400))))
      check(name .. ": so is a number too large to hold", depot.request.count == 25000 and depot.request.asked == fill)
      assert(logistics.set_request(tank, "water", 1e100))
      check(name .. ": a finite amount above it is kept", logistics.get_request(tank).asked == 1e100)
      depot.request.asked = math.huge -- saved by a version that kept it
      logistics.fit_request(depot)
      check(name .. ": a saved infinity is fitted too", depot.request.count == 25000 and depot.request.asked == fill)
    end
  end

  do -- A request saved before `asked` was kept holds only the amount it was capped to. One at its
    -- tank's size (capped from whatever was typed: the owner's playtest of the reported save) asks
    -- to fill the depot, so ticking freighter storage, or adding freighters, sends them out; one
    -- below it keeps its amount. Both fit a tank made smaller (the request depot tank size setting)
    -- and Full loads only then still sends freighters. No configuration change is needed.
    local logistics = reset()
    local request, provider = liquids(logistics, 1000, 40)
    provider.held.amount = 20000
    local depot = storage.depots[request.unit_number]
    depot.request = { item = "water", count = 25000 } -- from a save before
    request.held.name, request.held.amount = "water", 25000
    assert(logistics.set_freighter_storage(request, true))
    check(
      "an old request at its tank's size fills the freighters ticked",
      logistics.get_request(request).count == 30000
    )
    check("kept as filling the depot", depot.request.asked == logistics.request_fill)
    game.tick = 60
    logistics.on_tick()
    answer(logistics, #h.requests(), "route")
    check("so a freighter goes though the tank is full", #trips_from(request) == 1)
    assert(logistics.put_freighters(request, stack("jatz-quinityn-freighter", 20)) == 20)
    game.tick = 120
    logistics.on_tick()
    check("and freighters added raise it", logistics.get_request(request).count == 45000)

    -- An old request below its tank's size keeps its amount, ticked or not.
    logistics = reset()
    request = liquids(logistics, 1000, 40)
    depot = storage.depots[request.unit_number]
    depot.request = { item = "water", count = 10000 }
    assert(logistics.set_freighter_storage(request, true))
    check("an old request below its tank's size keeps it", logistics.get_request(request).count == 10000)
    check("as the amount set", depot.request.asked == 10000)

    -- The tank made bigger: 25,000 was a liquid request depot's tank before it had a setting, so
    -- an old request for that fills the bigger one, without typing it again.
    logistics = reset()
    request = liquids(logistics, 1000, 3)
    request.get_fluid_capacity = function()
      return 35000
    end
    storage.depots[request.unit_number].request = { item = "water", count = 25000 }
    logistics.fit_request(storage.depots[request.unit_number])
    check("an old request at the old 25,000 fills a bigger tank", logistics.get_request(request).count == 35000)

    -- The tank made smaller: an old request below 25,000 was never capped, so it keeps its amount
    -- above the smaller tank, as far as the depot can hold, rather than fill it.
    logistics = reset()
    request = liquids(logistics, 1000, 40)
    request.get_fluid_capacity = function()
      return 10000
    end
    depot = storage.depots[request.unit_number]
    depot.request = { item = "water", count = 20000 }
    logistics.fit_request(depot)
    check("an old 20,000 fits a 10,000 tank", depot.request.count == 10000 and depot.request.asked == 20000)
    assert(logistics.set_freighter_storage(request, true))
    check("and asks for no more than it with freighters added", logistics.get_request(request).count == 20000)

    -- A liquid buffer depot's old request at its tank's size fills it too; one below keeps its amount.
    for old, asked in pairs({ [25000] = logistics.request_fill, [10000] = 10000 }) do
      logistics = reset()
      local buffer = h.tank("jatz-liquid-buffer-depot", 40.5, 0.5)
      logistics.add(buffer)
      assert(logistics.put_freighters(buffer, stack("jatz-quinityn-freighter", 40)) == 40)
      depot = storage.depots[buffer.unit_number]
      depot.request = { item = "water", count = old }
      assert(logistics.set_freighter_storage(buffer, true))
      check(
        "a liquid buffer depot's old request for " .. old .. " asks for " .. asked,
        depot.request.asked == asked and depot.request.count == math.min(asked, 30000)
      )
    end

    -- The tank made smaller than one load (1,000, freighters carrying 2,625): old requests at the
    -- old 25,000 cap and below it fit it, and Full loads only sends a freighter for what fits.
    for old, asked in pairs({ [25000] = logistics.request_fill, [10000] = 10000 }) do
      logistics = reset()
      request, provider = liquids(logistics, 1000, 3)
      provider.held.amount = 20000
      request.get_fluid_capacity = function()
        return 1000
      end
      storage.research_levels = { [request.force.index] = { stacks = 0, fluid = 1875, speed = 1, tick = 0 } }
      assert(logistics.set_full_loads(request, true))
      depot = storage.depots[request.unit_number]
      depot.request = { item = "water", count = old }
      game.tick = 60
      logistics.on_tick()
      check(
        "an old request for " .. old .. " fits a 1,000 tank",
        depot.request.count == 1000 and depot.request.asked == asked
      )
      check(
        "and Full loads only sends a freighter for it",
        #h.requests() == 1 and logistics.get_status(request) == "searching"
      )
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
