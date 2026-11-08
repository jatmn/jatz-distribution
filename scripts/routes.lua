-- SPDX-License-Identifier: LGPL-3.0-only
-- Road routes for searches: asking the pathfinder how far a candidate is by road, remembering the
-- lengths it found, and handing its answers (and remembered ones) back to the search. Split out of
-- scripts/logistics.lua so its main chunk stays well below Lua's limit of 200 locals (issue #69).
-- logistics.lua keeps the searches themselves (`route_answered`, `finish_search`) and the entry
-- points (`logistics.on_script_path_request_finished`, `logistics.answer_remembered`), and hands
-- this module the helpers it shares with it once they are defined (routes.install).
local routes = {}

-- scripts/logistics.lua's helpers, from routes.install.
local owner_of, cancel_search, route_answered
local DRONE, ARRIVAL_RADIUS, ROAD_MEMORY_TICKS, DISPATCH_INTERVAL, SEARCH_TIMEOUT

function routes.install(_, shared)
  owner_of, cancel_search, route_answered = shared.owner_of, shared.cancel_search, shared.route_answered
  DRONE, ARRIVAL_RADIUS, ROAD_MEMORY_TICKS = shared.drone, shared.arrival_radius, shared.road_memory_ticks
  DISPATCH_INTERVAL, SEARCH_TIMEOUT = shared.dispatch_interval, shared.search_timeout
end

-- The freighter's box and collision mask, read from its prototype once (prototypes don't change
-- while the game runs; reading them makes new tables every time).
local drone_shape

-- Road lengths the pathfinder found, so the same question isn't asked again and again (a depot
-- asks about the same providers every time it sends a freighter, and every answer carries the
-- whole route, a table per tile, for Lua to collect): storage.road_lengths[surface index] =
-- { lengths = { [key] = tiles, or false for no road }, ticks = { [key] = tick found } }. A
-- surface's are forgotten whenever its road changes (on_roads_changed) and on configuration
-- changes, and each after ROAD_MEMORY_TICKS in case another mod changed tiles without an event.
-- An answer is remembered only if the surface's road hasn't changed since it was asked
-- (storage.road_versions[surface index], counted up by each change): it would be about old road.
-- Whether a tick's depot checks are under way (they are when a depot's search asks first).
routes.checking_depots = false
-- The search answer_remembered is giving its remembered answers to, and the next of them, taken at
-- once (ask_route) rather than queued: Lua only, set and used within one call.
local answering, chained, chained_length = nil, false, nil

local function road_key(from, to)
  return from.x .. " " .. from.y .. " " .. to.x .. " " .. to.y
end

-- Remembered answers wait in storage.road_answers and are given when the pathfinder's own would
-- come: after the tick's depot checks for a question one of them asked (the pathfinder answers
-- those in the same tick, after every depot has decided), the next tick for any other. Given
-- during the checks, a depot's freighter would promise stock before the others of its group had
-- looked (check_phase).
local function remember_road(search, length)
  if not search.road_key or search.road_version ~= (storage.road_versions or {})[search.surface_index] then
    return
  end
  storage.road_lengths = storage.road_lengths or {}
  local known = storage.road_lengths[search.surface_index]
  if not known then
    known = { lengths = {}, ticks = {} }
    storage.road_lengths[search.surface_index] = known
  end
  known.lengths[search.road_key] = length or false
  known.ticks[search.road_key] = game.tick
end

-- Ask the pathfinder for the road route from the search's start to its current candidate, as the
-- freighter would drive it, unless its length is known. Only a depot's searches are remembered:
-- they start from its loading zone, while a freighter's start wherever it stands.
local function ask_route(search, surface, force)
  local goal = search.candidates[search.index].position
  if not search.trip then
    local key = road_key(search.from, goal)
    local surface_index = surface.index
    local known = storage.road_lengths and storage.road_lengths[surface_index]
    local length = known and known.lengths[key]
    if length ~= nil and game.tick - known.ticks[key] < ROAD_MEMORY_TICKS then
      if answering == search then
        chained, chained_length = true, length or nil
        return
      end
      storage.road_answers = storage.road_answers or {}
      local answers = storage.road_answers
      answers[#answers + 1] =
        { search = search, length = length or nil, tick = routes.checking_depots and game.tick or game.tick + 1 }
      return
    end
    search.road_key, search.surface_index = key, surface_index
    search.road_version = (storage.road_versions or {})[surface_index]
  end
  if not drone_shape then
    local drone = prototypes.entity[DRONE]
    drone_shape = { box = drone.collision_box, mask = drone.collision_mask }
  end
  local id = surface.request_path({
    bounding_box = drone_shape.box,
    collision_mask = drone_shape.mask,
    start = search.from,
    goal = goal,
    force = force,
    radius = ARRIVAL_RADIUS,
    pathfind_flags = { no_break = true },
  })
  -- Saves from before searches existed have no table yet, and their mod version is the same.
  storage.searches = storage.searches or {}
  storage.searches[id] = search
end

local function path_length(from, path)
  local length, x, y = 0, from.x, from.y
  for _, waypoint in ipairs(path) do
    local position = waypoint.position
    length = length + math.sqrt((position.x - x) ^ 2 + (position.y - y) ^ 2)
    x, y = position.x, position.y
  end
  return length
end

function routes.on_script_path_request_finished(event)
  local search = storage.searches and storage.searches[event.id]
  if not search then
    return
  end
  storage.searches[event.id] = nil
  if event.try_again_later then
    -- The pathfinder is busy: this search ends, and a new one starts at the next dispatch (or, for
    -- a freighter, the next once-a-second check), so a busy pathfinder is asked at most once a
    -- second per owner.
    local owner = owner_of(search)
    local depot = storage.depots[search.request]
    if owner and depot and depot.entity.valid then
      if search.trip then
        owner.search_token, owner.searching = nil, game.tick - SEARCH_TIMEOUT
      else
        cancel_search(depot)
      end
    end
    return
  end
  local length = event.path and path_length(search.from, event.path) or nil
  remember_road(search, length)
  route_answered(search, length)
end

-- Searches given their remembered answers in a tick, at least: a group of depots checked together
-- asks together, and each search that ends sends a freighter off (a new unit, its inventories and
-- its command), so they are spread over the next ticks, as the pathfinder's answers come. With
-- more waiting, as many as clear them all, evenly, within DISPATCH_INTERVAL of the oldest's
-- question: each depot sends at most one freighter a second anyway, and a search kept waiting
-- longer than SEARCH_TIMEOUT would be dropped and start again (Pullfrog's review of 5832360: limiting answers rather than searches,
-- a large group's searches each took one answer in turn and none finished before its timeout).
local REMEMBERED_PER_TICK = 3

-- Give a search its remembered answer, and then each next one it has (ask_route) at once, until
-- it ends or asks the pathfinder.
local function give_remembered(search, length)
  answering = search
  repeat
    chained = false
    route_answered(search, length)
    length = chained_length
  until not chained
  answering, chained_length = nil, nil
end

-- Give the searches whose remembered answers are due (ask_route) those answers, in the order
-- asked, up to the tick's share; the rest wait for the next tick. A search made stale meanwhile (its
-- owner holds another token, or is gone) is dropped and takes no one's turn.
local function answer_remembered()
  local answers = storage.road_answers
  if not answers or #answers == 0 then
    return
  end
  -- Questions asked while answering (other searches') go after those already waiting.
  storage.road_answers = {}
  local left = math.max(1, DISPATCH_INTERVAL - (game.tick - answers[1].tick))
  local share = math.max(REMEMBERED_PER_TICK, math.ceil(#answers / left))
  local waiting, given = {}, 0
  for _, answer in ipairs(answers) do
    -- A stale one is dropped.
    if owner_of(answer.search) then
      if answer.tick <= game.tick and given < share then
        given = given + 1
        give_remembered(answer.search, answer.length)
      else
        waiting[#waiting + 1] = answer
      end
    end
  end
  for _, answer in ipairs(storage.road_answers) do
    waiting[#waiting + 1] = answer
  end
  storage.road_answers = waiting
end
routes.answer_remembered = answer_remembered
routes.ask_route = ask_route

return routes
