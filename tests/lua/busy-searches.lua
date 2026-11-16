-- SPDX-License-Identifier: LGPL-3.0-only
-- A freighter's search and a busy pathfinder (scripts/routes.lua: on_script_path_request_finished;
-- scripts/logistics.lua: logistics.ask_again): the question it was too busy for is asked again at
-- the freighter's next check, and the candidates already answered stand. Run by
-- tests/lua/logistics.lua, which hands it its helpers (`h`): that file is at the size CI downloads.
return function(h)
  local harness = require("tests.lua.harness")
  local entity, stack, check = harness.entity, harness.stack, harness.check
  local answer = harness.answer
  local reset, trip_of = h.reset, h.trip_of

  -- A freighter on the road to a provider that is then removed, two others left: one 15 tiles from
  -- where it stands, whose road goes a long way round (90 tiles), and one 25 tiles off. Its search
  -- has the first's road and has asked about the second's. Returns the trip, the two providers and
  -- the path requests.
  local function searching(logistics)
    local requests = h.requests()
    local request = entity("jatz-request-depot", 0.5, 0.5)
    local gone = entity("jatz-provider-depot", 10.5, 0.5, { a = 20 })
    local round = entity("jatz-provider-depot", 20.5, 0.5, { a = 20 })
    local straight = entity("jatz-provider-depot", 30.5, 0.5, { a = 20 })
    logistics.add(request)
    logistics.add(gone)
    assert(logistics.set_request(request, "a", 10))
    assert(logistics.put_freighters(request, stack("jatz-quinityn-freighter", 1)) == 1)
    logistics.on_tick()
    answer(logistics, 1, "route")
    local trip = trip_of(request)
    logistics.add(round)
    logistics.add(straight)
    trip.drone.position = { x = 5.5, y = 2.5 }
    gone.valid = false
    logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = gone.unit_number })
    local first = requests[#requests]
    check("setup: its search asks about the nearer provider first", trip.search and first.goal.x == 20.5)
    logistics.on_script_path_request_finished({
      id = #requests,
      path = {
        { position = { x = 5.5, y = 40 } },
        { position = { x = 20.5, y = 40 } },
        { position = first.goal },
      },
    })
    check("setup: its road is long, so the next is asked about", trip.search and requests[#requests].goal.x == 30.5)
    return trip, round, straight, requests
  end

  do -- Busy for its second question: that one is asked again, a second later, and the first stands.
    local logistics = reset()
    local trip, _, straight, requests = searching(logistics)
    local asked = #requests
    answer(logistics, asked, "busy")
    check("a busy answer asks nothing at once, and the search stands", trip.search ~= nil and #requests == asked)
    game.tick = game.tick + 60
    logistics.on_tick()
    check(
      "at its next check it asks the same question again, not the one answered",
      #requests == asked + 1 and requests[#requests].goal.x == 30.5 and requests[#requests].start.x == 5.5
    )
    answer(logistics, #requests, "busy")
    game.tick = game.tick + 60
    logistics.on_tick()
    check(
      "and again while the pathfinder is busy, once a second",
      #requests == asked + 2 and requests[#requests].goal.x == 30.5
    )
    answer(logistics, #requests, "route")
    check(
      "answered, it goes to the nearer by road of the two",
      trip.provider == straight.unit_number and not trip.search and #requests == asked + 2
    )
  end

  do -- Busy for as long as a search may take: it starts afresh, as one never answered does.
    local logistics = reset()
    local trip, _, _, requests = searching(logistics)
    for _ = 1, 9 do
      answer(logistics, #requests, "busy")
      game.tick = game.tick + 60
      logistics.on_tick()
    end
    check("setup: asked again each second, 9 times", trip.search and requests[#requests].goal.x == 30.5)
    answer(logistics, #requests, "busy")
    game.tick = game.tick + 60
    logistics.on_tick()
    check(
      "ten seconds on, the search starts afresh, from its first candidate",
      trip.search and requests[#requests].goal.x == 20.5
    )
  end

  do -- Its searches restarted meanwhile (its depot set to request from buffer depots): it starts
    -- afresh, and the old search's question isn't asked again.
    local logistics = reset()
    local trip, _, _, requests = searching(logistics)
    local asked = #requests
    answer(logistics, asked, "busy")
    assert(logistics.set_from_buffers(storage.depots[trip.request].entity, true))
    game.tick = game.tick + 60
    logistics.on_tick()
    check(
      "restarted since, it searches afresh from its first candidate",
      trip.search and #requests == asked + 1 and requests[#requests].goal.x == 20.5
    )
  end
end
