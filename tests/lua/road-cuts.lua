-- SPDX-License-Identifier: LGPL-3.0-only
-- Road removed while freighters are out (scripts/logistics.lua: on_roads_changed, replan_cut): each
-- plans its way again at a check of its own, once the road is left alone, not all of them in the
-- event, tile after tile; a road network flooded for one (scripts/tunnels.lua: net_of) is kept
-- for the next; and with the tiles removed known, only the freighters whose way they can have been
-- on plan again, and only the roads measured that they can have been on are forgotten
-- (tunnels.untouched, tunnels.forget). Run by tests/lua/logistics.lua, which hands it its helpers
-- (`h`): that file is at the size CI downloads.
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

  -- The tiles of a removal known (control.lua passes an event's on): on the map of joined_round
  -- a freighter drives 20.1 tiles of road from its depot's loading zone (0.5, 2.5) to the west
  -- mouth (20.5, 0.5), goes under, and 10.2 tiles on from the east mouth (30.5, 0.5) to the
  -- provider's loading zone (40.5, 2.5).
  local arrive = harness.arrive
  local tunnels = require("scripts.tunnels")
  local function removed(logistics, x, y)
    logistics.on_roads_changed(1, false, true, { { position = { x = x, y = y } } })
  end
  -- Whether a question about the road between two tiles was asked from `first` on.
  local function asked_between(requests, first, ax, ay, bx, by)
    for id = first, #requests do
      local start, goal = requests[id].start, requests[id].goal
      local sx, sy, gx, gy = math.floor(start.x), math.floor(start.y), math.floor(goal.x), math.floor(goal.y)
      if (sx == ax and sy == ay and gx == bx and gy == by) or (sx == bx and sy == by and gx == ax and gy == ay) then
        return true
      end
    end
    return false
  end

  do -- Road removed where no road of its way can have been: it drives on, and nothing is asked.
    local logistics = reset()
    local request, _, _, _, restore = h.joined_round(logistics, "round")
    local requests = h.requests()
    local trip = trip_of(request)
    trip.drone.position = { x = 10.5, y = 0.5 }
    local plan, commands, asked = trip.plan, #trip.drone.commands, #requests
    check(
      "setup: its plan holds where it starts and how long each of its roads is",
      plan
        and #plan.hops == 1
        and plan.hops.from.x == 0.5
        and plan.hops.from.y == 2.5
        and #plan.hops.roads == 2
        and math.abs(plan.hops.roads[1] - math.sqrt(20 ^ 2 + 2 ^ 2)) < 1e-6
        and math.abs(plan.hops.roads[2] - math.sqrt(10 ^ 2 + 2 ^ 2)) < 1e-6
    )
    -- 100 tiles off every road measured (the longest goes round, 50 tiles south and back).
    removed(logistics, 10, -100)
    check("road removed 100 tiles off: it isn't to plan again", not trip.road_cut and trip.plan == plan)
    local hops = tunnels.plan(1, plan.hops.from, plan.to, nil, "player", { id = "check", order = 0 })
    check(
      "and every road is still measured: a plan of its way asks nothing",
      hops and #hops == 1 and #requests == asked
    )
    -- 14.2 and 15.7 tiles from the ends of its first road, of 20.1 tiles: not on it, though the
    -- road round may have gone by there.
    removed(logistics, 10, 13)
    check("road removed 10 tiles off its way: it isn't to plan again", not trip.road_cut and trip.plan == plan)
    game.tick = game.tick + 60 + logistics.cut_quiet
    logistics.on_tick_share(game.tick)
    check("and drives on as it was", #trip.drone.commands == commands and trip.planning == nil)
    asked = #requests
    check("setup: its first road is measured", storage.tunnel_legs[1].lengths["0,2,20,0"] ~= nil)
    -- 0.5 tiles off that road, 9.5 tiles from each end.
    removed(logistics, 10, 1)
    check("road removed on its way: it is to plan again, from where it stands", trip.road_cut and not trip.plan)
    -- (Roads measured are kept by the tiles of their two ends: scripts/tunnels.lua, leg_key.)
    local lengths = storage.tunnel_legs[1].lengths
    check(
      "that road is measured no more, the one beyond the tunnel still is",
      lengths["0,2,20,0"] == nil and math.abs(lengths["30,0,40,2"] - math.sqrt(10 ^ 2 + 2 ^ 2)) < 1e-6
    )
    game.tick = game.tick + logistics.cut_quiet
    logistics.replan_cut(trip)
    check("and waits for its roads from there", trip.planning ~= nil and #requests > asked)
    check(
      "the road beyond the tunnel, 19 tiles from the tile removed, is still measured: not asked again",
      not asked_between(requests, asked + 1, 30, 0, 40, 2)
    )
    h.settle(logistics)
    check("then drives on to the tunnel", trip.planning == nil and trip.tunnel ~= nil)
    restore()
  end

  do -- Out of the tunnel, only the road still ahead counts.
    local logistics = reset()
    local request, _, _, _, restore = h.joined_round(logistics, "round")
    local trip = trip_of(request)
    trip.drone.position = { x = 20.5, y = 0.5 }
    arrive(logistics, trip)
    arrive(logistics, trip)
    arrive(logistics, trip)
    local plan = trip.plan
    check("setup: out of the east mouth, on its way's second road", plan and plan.step == 2 and not trip.tunnel)
    removed(logistics, 10, 1)
    check("road removed on the road it has driven: it drives on", not trip.road_cut and trip.plan == plan)
    removed(logistics, 35, 1)
    check("road removed on the road ahead: it is to plan again", trip.road_cut and not trip.plan)
    restore()
  end

  do -- Standing at a depot to load, with no plan: where it stands is what counts.
    local logistics = reset()
    local request, _, _, _, restore = h.joined_round(logistics, "round")
    local trip = trip_of(request)
    trip.drone.position = { x = 20.5, y = 0.5 }
    arrive(logistics, trip)
    arrive(logistics, trip)
    arrive(logistics, trip)
    trip.drone.position = { x = 40.5, y = 2.5 }
    logistics.on_ai_command_completed({
      unit_number = trip.drone.unit_number,
      result = defines.behavior_result.success,
    })
    local origin = trip.origin
    check(
      "setup: it stands at the provider's loading zone, loading",
      trip.service and not trip.plan and origin.x == 40.5
    )
    removed(logistics, 10, 1)
    check("road removed 30 tiles off: it still stands where it arrived", trip.origin == origin and not trip.road_cut)
    removed(logistics, 40, 3)
    check("road removed beside it: it plans from where it stands", trip.origin == nil and trip.road_cut)
    restore()
  end

  do -- What can't be told is taken as changed, as before.
    local logistics = reset()
    local request, _, _, _, restore = h.joined_round(logistics, "round")
    local trip = trip_of(request)
    local plan = trip.plan
    local roads = plan.hops.roads
    -- A plan from before it held its roads.
    plan.hops.roads = nil
    removed(logistics, 10, 13)
    check("a plan from a save before its roads were kept: it is to plan again", trip.road_cut and not trip.plan)
    trip.road_cut, trip.plan = nil, plan
    plan.hops.roads = roads
    -- More tiles in one event than are gone through one by one (scripts/tunnels.lua, TILES_AT_ONCE).
    local many = {}
    for index = 1, 1001 do
      many[index] = { position = { x = 10, y = 100 + index } }
    end
    logistics.on_roads_changed(1, false, true, many)
    check("1,001 tiles removed in one event, wherever: it is to plan again", trip.road_cut and not trip.plan)
    check("and no road stays measured", next(storage.tunnel_legs[1].lengths) == nil)
    restore()
  end

  do -- Roads measured as none, and those of a save from before their ends were kept.
    local logistics = reset()
    h.tunnelled(logistics, true)
    local from, to = { x = 0.5, y = 2.5 }, { x = 40.5, y = 2.5 }
    -- The search's own answer: no road between the two networks.
    tunnels.plan(1, from, to, false, "player", { id = "check", order = 0 })
    h.settle(logistics)
    local legs = storage.tunnel_legs[1]
    local none, some = 0, 0
    for _, length in pairs(legs.lengths) do
      none, some = none + (length == false and 1 or 0), some + (length and 1 or 0)
    end
    check("setup: a road measured as none, and roads measured", none == 1 and some > 0)
    removed(logistics, 10, 1)
    local left = 0
    for _, length in pairs(storage.tunnel_legs[1].lengths) do
      left = left + (length == false and 1 or 0)
    end
    check("road removed between its ends: none it stays", storage.tunnel_legs[1] == legs and left == 1)
    legs.spans = nil
    removed(logistics, 10, 100)
    check(
      "roads measured by a save from before their ends were kept: all forgotten, wherever road is removed",
      next(storage.tunnel_legs[1].lengths) == nil and storage.tunnel_legs[1].spans ~= nil
    )
  end
end
