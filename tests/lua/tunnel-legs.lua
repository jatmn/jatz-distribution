-- SPDX-License-Identifier: LGPL-3.0-only
-- The measured roads of ways through tunnels (scripts/tunnels.lua): their questions to the
-- pathfinder, its answers and who waits for them. Run by tests/lua/logistics.lua, which hands it
-- its helpers (`h`): that file is at the size CI downloads.
return function(h)
  local reset, check, settle, trip_of = h.reset, h.check, h.settle, h.trip_of
  local tunnelled, joined_round, one_network, leg_road = h.tunnelled, h.joined_round, h.one_network, h.leg_road

  -- A freighter waits for its roads while tiles are laid elsewhere between each question and its
  -- answer (`laid`: road, or another tile), 61 ticks on, its checks run meanwhile.
  local function laid_meanwhile(laid)
    local logistics = reset()
    local request, _, _, _, restore = joined_round(logistics, "round")
    local requests = h.requests()
    local trip = trip_of(request)
    trip.drone.position = { x = 10.5, y = 0.5 }
    logistics.on_roads_changed(1, false, true)
    local waited = trip.planning ~= nil
    for _ = 1, 10 do
      local ids = {}
      for id in pairs(storage.tunnel_leg_asks or {}) do
        ids[#ids + 1] = id
      end
      if #ids == 0 then
        break
      end
      table.sort(ids)
      for _ = 1, 61 do
        game.tick = game.tick + 1
        logistics.on_tick_share(game.tick)
      end
      logistics.on_roads_changed(1, laid == "road", false)
      for _, id in ipairs(ids) do
        logistics.on_script_path_request_finished({ id = id, path = leg_road(requests[id].start, requests[id].goal) })
      end
    end
    local drive = trip.drone.commands[#trip.drone.commands]
    restore()
    return waited and trip.planning == nil and trip.tunnel ~= nil and drive.destination.x == 20.5
  end

  do -- Tiles laid elsewhere while a freighter waits for its roads to be measured: it goes on all the same.
    check("road laid elsewhere meanwhile, it goes on through the tunnel", laid_meanwhile("road"))
    check("concrete laid elsewhere meanwhile, it goes on through the tunnel", laid_meanwhile("concrete"))
  end

  do -- Road laid while it waits: the roads it needs are asked about.
    local logistics = reset()
    local request, _, _, _, restore = joined_round(logistics, "round")
    local requests = h.requests()
    local trip = trip_of(request)
    trip.drone.position = { x = 10.5, y = 0.5 }
    logistics.on_roads_changed(1, false, true)
    local id = #requests
    logistics.on_script_path_request_finished({ id = id, path = leg_road(requests[id].start, requests[id].goal) })
    for asked in pairs(storage.tunnel_leg_asks) do
      logistics.on_script_path_request_finished({ id = asked, try_again_later = true })
    end
    h.straight()
    logistics.on_roads_changed(1, true, false)
    game.tick = game.tick + 60
    logistics.on_tick()
    settle(logistics)
    local drive = trip.drone.commands[#trip.drone.commands]
    check("road laid straight across, it is taken", not (trip.planning or trip.tunnel) and drive.destination.x == 40.5)
    restore()
  end

  do -- Old answers resume nobody once road is removed (Pullfrog's review of 3569498).
    local logistics = reset()
    local request = tunnelled(logistics, true)
    local surface, requests = h.surface(), h.requests()
    local whole = surface.get_connected_tiles
    surface.get_connected_tiles = one_network
    logistics.on_roads_changed(1, true, false)
    logistics.on_tick()
    logistics.on_script_path_request_finished({ id = #requests })
    local old = {}
    for id in pairs(storage.tunnel_leg_asks) do
      old[#old + 1] = id
    end
    logistics.on_roads_changed(1, false, true)
    check("removed, all go", not next(storage.tunnel_leg_asks) and not next(storage.tunnel_waiters[1]))
    game.tick = game.tick + 60
    logistics.on_tick()
    logistics.on_script_path_request_finished({ id = #requests })
    local depot = storage.depots[request.unit_number]
    local token = depot.search.token
    for _, id in ipairs(old) do
      logistics.on_script_path_request_finished({ id = id, try_again_later = true })
      logistics.on_script_path_request_finished({ id = id, path = { { position = requests[id].goal } } })
    end
    check("old answers leave the new search alone", depot.search and depot.search.token == token)
    settle(logistics)
    check("its own answers send the freighter", trip_of(request).tunnel ~= nil)
    surface.get_connected_tiles = whole
  end

  do -- Questions never answered go with their waits once the roads expire.
    local logistics = reset()
    tunnelled(logistics, true)
    local plan, to = require("scripts.tunnels").plan, { x = 40.5, y = 2.5 }
    for index = 1, 11 do
      game.tick = game.tick + (index < 11 and 60 or 18000)
      plan(1, { x = index - 0.5, y = 2.5 }, to, false, "player", { id = index, order = index })
    end
    local count = 0
    for _, waiting in pairs(storage.tunnel_waiters[1]) do
      for id in pairs(waiting) do
        count = count + (id == 11 and 1 or 9)
      end
    end
    for _ in pairs(storage.tunnel_leg_asks) do
      count = count + 1
    end
    check("only the last plan's are left", count == 4)
  end

  do -- Destroyed while it waits to plan again, its on_object_destroyed still to come: it isn't
    -- driven, and is lost as any freighter (Pullfrog's review of 5d10933: it crashed).
    local logistics = reset()
    local request, _, _, _, restore = joined_round(logistics, "round")
    local trip = trip_of(request)
    trip.drone.position = { x = 10.5, y = 0.5 }
    logistics.on_roads_changed(1, false, true)
    local asked = next(storage.tunnel_leg_asks)
    logistics.on_script_path_request_finished({ id = asked, try_again_later = true })
    check("setup: busy, it plans again at its next check", trip.planning and trip.planning.since < game.tick)
    local unit = trip.drone.unit_number
    trip.drone.destroy()
    game.tick = game.tick + 60
    logistics.on_tick()
    check("destroyed, it isn't planned for again", trip.planning ~= nil)
    logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = unit })
    local home, out = logistics.freighter_counts(request)
    check("then it is lost", not h.has_trip(request) and home == 0 and out == 0)
    restore()
  end
end
