-- SPDX-License-Identifier: LGPL-3.0-only
-- Road removed while freighters are out (scripts/logistics.lua: on_roads_changed, replan_cut): each
-- plans its way again at a check of its own, once the road is left alone, not all of them in the
-- event, tile after tile; and a road network flooded for one (scripts/tunnels.lua: net_of) is
-- kept for the next. Run by tests/lua/logistics.lua, which hands it its helpers (`h`): that file
-- is at the size CI downloads.
return function(h)
  local harness = require("tests.lua.harness")
  local entity, stack, check = harness.entity, harness.stack, harness.check
  local reset, trip_of = h.reset, h.trip_of

  -- How many commands to drive somewhere a freighter has had.
  local function drives(trip)
    local count = 0
    for _, command in ipairs(trip.drone.commands) do
      count = count + (command.type == defines.command.go_to_location and 1 or 0)
    end
    return count
  end

  do -- Three freighters out, and road removed a tile a tick for 20 ticks, as mining it by hand does.
    local logistics = reset()
    local requests = h.requests()
    local provider = entity("jatz-provider-depot", 30.5, 0.5, { a = 1000 })
    logistics.add(provider)
    local trips = {}
    for index = 1, 3 do
      local request = entity("jatz-request-depot", 0.5, 0.5 + 6 * index)
      logistics.add(request)
      assert(logistics.set_request(request, "a", 10))
      assert(logistics.put_freighters(request, stack("jatz-quinityn-freighter", 1)) == 1)
      logistics.on_tick()
      logistics.on_script_path_request_finished({ id = #requests, path = { { position = requests[#requests].goal } } })
      trips[index] = trip_of(request)
    end
    local before = {}
    for index, trip in ipairs(trips) do
      before[index] = drives(trip)
    end
    local function driven()
      local count, most = 0, 0
      for index, trip in ipairs(trips) do
        count = count + (drives(trip) > before[index] and 1 or 0)
        most = math.max(most, drives(trip) - before[index])
      end
      return count, most
    end
    local tick = 600
    local stroke = true
    for _ = 1, 20 do
      tick = tick + 1
      game.tick = tick
      logistics.on_roads_changed(1, false, true)
      stroke = stroke and driven() == 0
      logistics.on_tick_share(tick)
      stroke = stroke and driven() == 0
    end
    check("while road is removed tile after tile, no freighter plans its way again", stroke)
    -- The ticks in which a freighter planned its way again, and how many did in each.
    local ticks, most_at_once, last = 0, 0, 0
    for _ = 1, 60 + logistics.cut_quiet do
      tick = tick + 1
      game.tick = tick
      logistics.on_tick_share(tick)
      local now = driven()
      if now > last then
        ticks, most_at_once = ticks + 1, math.max(most_at_once, now - last)
      end
      last = now
    end
    local all, most = driven()
    check("left alone, each plans again at its own check, within a second", all == 3 and most == 1)
    check("one after another, not all in one tick", ticks == 3 and most_at_once == 1)
    local flagged = false
    for _, trip in ipairs(trips) do
      flagged = flagged or trip.road_cut ~= nil
    end
    check("and only once", not flagged)
  end

  do -- A freighter standing until the roads of its way through a tunnel are measured, past the
    -- time it would ask again, while road is removed tile after tile: the questions it waited on
    -- went with the roads measured (scripts/tunnels.lua: forget), and it plans its way again once
    -- the road is left alone, as every other freighter does, not at a check during the removing.
    local logistics = reset()
    local request, _, _, _, restore = h.joined_round(logistics, "round")
    local trip = trip_of(request)
    trip.drone.position = { x = 10.5, y = 0.5 }
    h.road_removed(logistics)
    local planning = trip.planning
    check("setup: it stands until its roads are measured", planning ~= nil)
    local commands = #trip.drone.commands
    -- Past its search timeout (scripts/logistics.lua: SEARCH_TIMEOUT), every check in the stroke.
    local tick = planning.since + 10 * 60
    local stood = true
    for _ = 1, 2 * 60 do
      tick = tick + 1
      game.tick = tick
      logistics.on_roads_changed(1, false, true)
      logistics.on_tick_share(tick)
      stood = stood and #trip.drone.commands == commands and trip.planning == planning
    end
    check("while road is removed tile after tile, it plans nothing", stood)
    for _ = 1, 60 + logistics.cut_quiet do
      tick = tick + 1
      game.tick = tick
      logistics.on_tick_share(tick)
    end
    check("left alone, it plans its way again", not trip.road_cut and #trip.drone.commands > commands)
    restore()
  end

  do -- A road network flooded to plan one freighter's way from where it stands serves the next
    -- plan too, on a later tick, until road is removed again.
    local logistics = reset()
    local request, _, _, _, restore = h.joined_round(logistics, "round")
    local surface = h.surface()
    local trip = trip_of(request)
    local floods, flood = 0, surface.get_connected_tiles
    function surface.get_connected_tiles(...)
      floods = floods + 1
      return flood(...)
    end
    trip.drone.position = { x = 10.5, y = 0.5 }
    h.road_removed(logistics)
    local first = floods
    check("road removed: the freighter's network is flooded as it plans from where it stands", first > 0)
    game.tick = game.tick + 5
    trip.drone.position = { x = 12.5, y = 1.5 }
    trip.origin, trip.plan, trip.planning = nil, nil, nil
    trip.road_cut = true
    logistics.replan_cut(trip)
    check("planning from another tile of it, ticks later, floods nothing", floods == first)
    game.tick = game.tick + 5
    h.road_removed(logistics)
    check("until road is removed again", floods > first)
    restore()
  end
end
