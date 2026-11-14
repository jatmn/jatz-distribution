-- SPDX-License-Identifier: LGPL-3.0-only
-- Freighters running over enemy units, as trains do. Split out of scripts/logistics.lua, whose
-- main chunk had reached Lua's limit of 200 locals (issue #69). logistics.lua keeps the entry
-- points control.lua calls (`logistics.on_impact_tick`, `logistics.on_impact_share`) and deals the
-- looks out over the trips' phases (`trip_phases`); this module does the looking.
local paint = require("scripts.freighter-paint")

local impact = {}

-- How often moving freighters look for enemy units they are driving through, and the impact
-- damage each one hit takes, at most once a second from the same freighter. Freighters never
-- attack; this is them running enemies over, as trains do. 200 kills small and medium biters
-- outright and hurts bigger ones.
-- (Every 20 ticks, not 10: the position each look reads makes a table for Lua to collect, for every
-- freighter; the ground a look searches is all the freighter crossed since the last.)
local IMPACT_INTERVAL = 20
local IMPACT_DAMAGE = 200
-- How far either side of its centre a freighter hits, in tiles: 0.8 tiles across, the width its
-- collision box had before it was narrowed so it turns corners freely (prototypes/freighter-drone.lua).
local IMPACT_REACH = 0.4
local IMPACT_COOLDOWN = 60
-- What a freighter runs over: enemy units only, never players (characters), buildings or other
-- freighters.
local IMPACT_TYPES = { "unit", "spider-unit", "segmented-unit" }
-- How often a freighter looks, for logistics.on_impact_share.
impact.INTERVAL = IMPACT_INTERVAL

-- Moving freighters run over the enemy units they drive through, as trains do: each takes
-- IMPACT_DAMAGE as impact damage, at most once a second from the same freighter. The search
-- covers the ground the freighter crossed since the last look, so a fast one misses nothing in
-- between. A standing freighter (loading, or waiting for a route) hits nothing, players and other
-- freighters are never hit, and nothing makes the freighter stop or turn: it drives on.

-- The names of every entity prototype a freighter can run over (IMPACT_TYPES), from game data:
-- not the freighters themselves, which are units too but never hit.
local impact_names
-- Whether any force has a unit to run over: the game keeps each force's entity counts, so this is
-- a few lookups, not a search. Without any (a map without enemies), no freighter needs looking at.
local function units_exist()
  if not impact_names then
    impact_names = {}
    for name in pairs(prototypes.get_entity_filtered({ { filter = "type", type = IMPACT_TYPES } })) do
      if not paint.is_drone(name) then
        impact_names[#impact_names + 1] = name
      end
    end
  end
  for _, force in pairs(game.forces) do
    for _, name in ipairs(impact_names) do
      if force.get_entity_count(name) > 0 then
        return true
      end
    end
  end
  return false
end

-- One search filter for every look, filled in before each call (the game reads it during the
-- call): thousands of freighters look every IMPACT_INTERVAL ticks, and every table made for them is
-- garbage for Lua to collect.
local impact_filter = { area = { { 0, 0 }, { 0, 0 } }, type = IMPACT_TYPES }

-- Look at the freighters of the trips trips[from..to] still out: each that moved since its last
-- look runs over the enemy units in the ground it crossed. The ground is counted first, so a
-- freighter with none in its way (nearly always) makes no list of what it found.
function impact.run_over(trips, from, to, fresh)
  -- By force index: the force, and its enemies. By surface index: its count_entities_filtered.
  local forces, surfaces = {}, {}
  local reach = IMPACT_REACH
  local area = impact_filter.area
  for index = from, to do
    local trip = trips[index]
    -- (One in a tunnel is under ground: it hits nothing on its way through.)
    local drone = storage.trips[trip.id] == trip and trip.movement ~= "underground" and trip.drone
    if drone and drone.valid then
      -- Where its once-a-second check found it, if that was this tick (a read makes a new table).
      local here = trip.at_tick == game.tick and trip.at or drone.position
      local last = not fresh and trip.last_position
      trip.last_position = here
      -- Enemies hit in the last second, by unit_number, aren't hit again yet.
      local hits = trip.hits
      if hits then
        for unit_number, tick in pairs(hits) do
          if game.tick - tick >= IMPACT_COOLDOWN then
            hits[unit_number] = nil
          end
        end
      end
      local force_index = drone.force_index
      local side = forces[force_index]
      if not side then
        local force, enemies = drone.force, {}
        for _, other in pairs(game.forces) do
          if force.is_enemy(other) then
            enemies[#enemies + 1] = other
          end
        end
        side = { force = force, enemies = enemies }
        forces[force_index] = side
      end
      if last and (here.x ~= last.x or here.y ~= last.y) and #side.enemies > 0 then
        -- The surface's count, bound once (a method read off an object is a new function each time).
        local surface_index = drone.surface_index
        local count = surfaces[surface_index]
        if not count then
          count = drone.surface.count_entities_filtered
          surfaces[surface_index] = count
        end
        area[1][1], area[1][2] = math.min(here.x, last.x) - reach, math.min(here.y, last.y) - reach
        area[2][1], area[2][2] = math.max(here.x, last.x) + reach, math.max(here.y, last.y) + reach
        impact_filter.force = side.enemies
        if count(impact_filter) > 0 then
          local force = side.force
          for _, enemy in pairs(drone.surface.find_entities_filtered(impact_filter)) do
            -- Damage sets off other mods' handlers there and then, and they can remove the
            -- freighter or an enemy further down this list: check both are still there before
            -- reading either.
            if drone.valid and enemy.valid and not paint.is_drone(enemy.name) then
              local key = enemy.unit_number
              if not (key and hits and hits[key]) then
                if key then
                  hits = hits or {}
                  hits[key] = game.tick
                end
                enemy.damage(IMPACT_DAMAGE, force, "impact", drone, drone)
              end
            end
          end
        end
      end
      trip.hits = hits and next(hits) and hits or nil
    end
  end
end

-- Whether impact checks are paused (no units in the game), and so whether this look is the first
-- since they were: where freighters were at the last look is out of date once units turn up, so
-- that look only notes where they are.
local function impact_pause()
  if not units_exist() then
    storage.impact_paused = true
    return true
  end
  local fresh = storage.impact_paused
  storage.impact_paused = nil
  return false, fresh
end

-- Every freighter looked at at once.
function impact.on_tick()
  local paused, fresh = impact_pause()
  if paused then
    return
  end
  local trips = {}
  for id, trip in pairs(storage.trips) do
    trip.id = id
    trips[#trips + 1] = trip
  end
  impact.run_over(trips, 1, #trips, fresh)
end

-- Whether freighters look this tick: the start of each round of IMPACT_INTERVAL ticks asks whether
-- there are units at all (and whether this is the first look since there were none).
function impact.open(tick)
  if tick % IMPACT_INTERVAL == 0 or storage.impact_open == nil then
    local paused, fresh = impact_pause()
    storage.impact_open = not paused
    storage.impact_fresh = fresh
  end
  return storage.impact_open
end

return impact
