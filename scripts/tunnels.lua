-- SPDX-License-Identifier: LGPL-3.0-only
-- Road tunnels: pairs of portals, like underground belts, that join road networks under whatever
-- stands between them (the owner's request, November 8, 2026: freighters can't drive over the
-- factory, so they go under it).
--
-- A portal (prototypes/road-tunnel.lua) is a pipe-to-ground whose one underground connection is in
-- its own connection category, so the game pairs the two ends (and shows how far they reach while
-- placing) and no pipe ever connects to them. Its mouth is the tile in front of it, its `entry`,
-- which must be road: a freighter drives there, goes under, and comes out at the other end's
-- entry (scripts/logistics.lua: drive, into_tunnel, out_of_tunnel).
--
-- The engine's pathfinder knows nothing of tunnels, so routing through them is worked out here:
-- which road network a point is on (`net_of`: flooded with LuaSurface.get_connected_tiles over
-- both road tiles, remembered only for the points the routes start, end or tunnel from), and the
-- shortest way by road, through any number of tunnels or none (`plan`), weighing every road leg by
-- the length the pathfinder measured for it. Freighters still drive every leg on road with the
-- pathfinder.
local tunnels = {}

tunnels.name = "jatz-road-tunnel"
local ROADS = { "jatz-road", "jatz-depot-road" }
-- Road laid comes in bursts (robots laying road a tile at a time): what is known of a surface's
-- networks is forgotten at most once a second for it, and the routes in between are worked out from
-- what it was. Road removed is forgotten at once (`changed`).
local FORGET_TICKS = 60
-- Unit vectors of the four directions a portal can face (its mouth is that way).
local FACING = {
  [defines.direction.north] = { 0, -1 },
  [defines.direction.east] = { 1, 0 },
  [defines.direction.south] = { 0, 1 },
  [defines.direction.west] = { -1, 0 },
}

-- Depot loading zone tiles on a surface, as { x, y } tile centres: set by scripts/logistics.lua,
-- which knows its depots. A flood notes every one it reaches, so a depot's network is known
-- without a flood of its own.
tunnels.zones = nil

local function init_storage()
  -- Portals by unit number.
  storage.tunnel_portals = storage.tunnel_portals or {}
  -- How many portals each surface has: no surface without one pays for any of this.
  storage.tunnel_surfaces = storage.tunnel_surfaces or {}
  -- What is known of each surface's road networks: { made = tick, stale = bool, count = networks,
  -- points = { [tile key] = network, or false off road }, portals = list (see `portals_of`) }.
  storage.tunnel_nets = storage.tunnel_nets or {}
end

local function key(x, y)
  return x .. "," .. y
end

-- The centre of the tile in front of a portal (one tile wide and two deep, its centre between its
-- two tiles): where freighters drive in and come out.
function tunnels.entry(entity)
  local facing = FACING[entity.direction] or FACING[defines.direction.north]
  local position = entity.position
  return {
    x = math.floor(position.x + facing[1] * 1.5) + 0.5,
    y = math.floor(position.y + facing[2] * 1.5) + 0.5,
  }
end

-- The portal at the other end of `entity`'s tunnel, if it has one.
local function partner(entity)
  local neighbours = entity.fluidbox_neighbours
  for _, entities in pairs(neighbours or {}) do
    for _, other in pairs(entities) do
      if other.valid and other.name == tunnels.name then
        return other
      end
    end
  end
  return nil
end
tunnels.partner = partner

-- Forget what is known of a surface's networks: at once (`now`: a portal built, removed or turned,
-- or road removed, which can split a network), or, for road laid, once a second has passed since it
-- was last worked out (laying only joins networks: until then a freighter may go through a tunnel
-- where road now joins the two, which still gets it there).
function tunnels.changed(surface_index, now)
  init_storage()
  local nets = storage.tunnel_nets[surface_index]
  if not nets then
    return
  end
  if now then
    storage.tunnel_nets[surface_index] = nil
  else
    nets.stale = true
  end
end

-- A portal built (by anyone) or cloned.
function tunnels.add(entity)
  if not (entity and entity.valid and entity.name == tunnels.name) then
    return false
  end
  init_storage()
  local id = entity.unit_number
  if not storage.tunnel_portals[id] then
    -- Its surface is noted now: once it is gone, an entity answers only `valid`.
    storage.tunnel_portals[id] = { entity = entity, surface_index = entity.surface_index }
    local surfaces = storage.tunnel_surfaces
    surfaces[entity.surface_index] = (surfaces[entity.surface_index] or 0) + 1
    script.register_on_object_destroyed(entity)
  end
  tunnels.changed(entity.surface_index, true)
  return true
end

-- A portal gone, by its unit number: returns its surface index, or nil if it wasn't one.
function tunnels.removed(unit_number)
  local portals = storage.tunnel_portals
  local portal = portals and portals[unit_number]
  if not portal then
    return nil
  end
  portals[unit_number] = nil
  local surface_index = portal.surface_index
  local surfaces = storage.tunnel_surfaces
  surfaces[surface_index] = (surfaces[surface_index] or 1) - 1
  if surfaces[surface_index] <= 0 then
    surfaces[surface_index] = nil
  end
  storage.tunnel_nets[surface_index] = nil
  return surface_index
end

-- Every portal in the game, after a configuration change (or for a save from before tunnels).
function tunnels.add_all()
  init_storage()
  storage.tunnel_portals, storage.tunnel_surfaces, storage.tunnel_nets = {}, {}, {}
  -- Roads measured, and questions and waits about them, start afresh too: the searches and plans
  -- waiting do (logistics, on_configuration_changed; a freighter plans again at its next check).
  storage.tunnel_legs, storage.tunnel_leg_asks, storage.tunnel_waiters = nil, nil, nil
  if not prototypes.entity[tunnels.name] then
    return
  end
  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered({ name = tunnels.name })) do
      tunnels.add(entity)
    end
  end
end

-- Whether a surface has any portal at all.
local function has_tunnels(surface_index)
  local surfaces = storage.tunnel_surfaces
  return surfaces ~= nil and surfaces[surface_index] ~= nil
end
tunnels.on = has_tunnels

-- What is known of a surface's networks, made afresh when forgotten, or when stale and a second
-- old. Each paired portal is listed once per end: { id, entity, entry, other (its partner's place
-- in the list), length (entry to entry) }.
local function nets_of(surface_index)
  local nets = storage.tunnel_nets[surface_index]
  if nets and nets.stale and game.tick - nets.made >= FORGET_TICKS then
    nets = nil
  end
  if nets then
    return nets
  end
  nets = { made = game.tick, count = 0, points = {}, portals = {} }
  storage.tunnel_nets[surface_index] = nets
  local places = {}
  for id, registered in pairs(storage.tunnel_portals) do
    local entity = registered.entity
    if entity.valid and registered.surface_index == surface_index then
      local other = partner(entity)
      if other then
        local list = nets.portals
        list[#list + 1] = { id = id, entity = entity, entry = tunnels.entry(entity), partner = other.unit_number }
        places[id] = #list
      end
    end
  end
  for _, portal in ipairs(nets.portals) do
    portal.other = places[portal.partner]
    local other = portal.other and nets.portals[portal.other]
    if other then
      local dx, dy = other.entry.x - portal.entry.x, other.entry.y - portal.entry.y
      portal.length = math.sqrt(dx * dx + dy * dy)
    end
  end
  return nets
end

-- Every tile flooded this tick, by tile key, with its network: Lua only, and only for the tick and
-- the surface's networks it was flooded for, so it never differs between players' games. After road
-- is removed, every freighter on the surface plans its way from where it stands; one flood a
-- network then serves them all.
local flooded = { tick = -1, nets = nil, tiles = {} }

-- The road network `position` is on (a number), or false if it isn't on road. Unknown, its
-- network is flooded once, noting every portal entry and depot loading zone it reaches.
-- A network keeps its number while what is known of the surface lasts: one flooded again (from a
-- point asked about on a later tick) takes the number of any point already remembered on it, so
-- points remembered on it before still agree (a new number left them on a network with no
-- portals, and routes from them found no tunnel: Pullfrog's review of 4d4f64a). Road laid since
-- this was worked out (forgotten at most once a second) can have joined networks remembered
-- apart: they become one, under the lowest of their numbers.
local function net_of(nets, surface, position)
  local x, y = math.floor(position.x), math.floor(position.y)
  local wanted = key(x, y)
  local known = nets.points[wanted]
  if known ~= nil then
    return known
  end
  if flooded.tick ~= game.tick or flooded.nets ~= nets then
    flooded.tick, flooded.nets, flooded.tiles = game.tick, nets, {}
  end
  known = flooded.tiles[wanted]
  if known then
    nets.points[wanted] = known
    return known
  end
  local tiles = surface.get_connected_tiles({ x, y }, ROADS)
  if #tiles == 0 then
    nets.points[wanted] = false
    return false
  end
  -- The points worth remembering: where a route can start, end or go under.
  local noted = { [wanted] = true }
  for _, portal in ipairs(nets.portals) do
    noted[key(math.floor(portal.entry.x), math.floor(portal.entry.y))] = true
  end
  for _, zone in ipairs(tunnels.zones and tunnels.zones(surface.index) or {}) do
    noted[key(math.floor(zone.x), math.floor(zone.y))] = true
  end
  local points, keys, seen, net = nets.points, {}, {}, nil
  for index, tile in ipairs(tiles) do
    local found = key(tile.x, tile.y)
    keys[index] = found
    local id = points[found]
    if id then
      seen[id] = true
      net = net and math.min(net, id) or id
    end
  end
  local this_tick = flooded.tiles
  if not net then
    nets.count = nets.count + 1
    net = nets.count
  elseif next(seen, next(seen)) then
    -- Networks remembered apart, joined since: every point on any of them takes the one number.
    for point, id in pairs(points) do
      if id and seen[id] then
        points[point] = net
      end
    end
    for tile, id in pairs(this_tick) do
      if seen[id] then
        this_tick[tile] = net
      end
    end
  end
  for _, found in ipairs(keys) do
    this_tick[found] = net
    if noted[found] then
      points[found] = net
    end
  end
  points[wanted] = net
  return net
end

-- Road lengths the pathfinder measured between points (a tunnel's entry, a depot's loading zone,
-- where a freighter stood), so that a way through tunnels is weighed by the road it really takes,
-- as the road round it is (the owner, November 14, 2026: "There should never be a penalty for
-- underground road path even multiple in series"). Per surface: { version = its road version when
-- measured (storage.road_versions, counted up by scripts/logistics.lua at every road change),
-- lengths = { [leg] = tiles, or false for no road }, ticks = { [leg] = tick measured }, asked =
-- { [leg] = tick the pathfinder was asked } }, forgotten when its road changes and each length
-- after LEG_MEMORY_TICKS (another mod may change tiles without an event), as scripts/routes.lua's.
-- A question unanswered after ASK_TICKS (lost with a save loaded meanwhile, say) is asked again, as
-- a search's is.
local LEG_MEMORY_TICKS = 5 * 60 * 60
local ASK_TICKS = 10 * 60

-- Asks the pathfinder for a leg's road (set by scripts/routes.lua): returns the request's id.
tunnels.ask = nil
-- Called with each owner waiting for a leg once it is measured (set by scripts/logistics.lua):
-- `busy` when the pathfinder couldn't answer this time.
tunnels.resume = nil

local function road_version(surface_index)
  local versions = storage.road_versions
  return versions and versions[surface_index] or 0
end

local function legs_of(surface_index)
  storage.tunnel_legs = storage.tunnel_legs or {}
  local legs = storage.tunnel_legs[surface_index]
  local version = road_version(surface_index)
  if not legs or legs.version ~= version then
    legs = { version = version, lengths = {}, ticks = {}, asked = {} }
    storage.tunnel_legs[surface_index] = legs
  end
  return legs
end

-- A leg's key, the same either way along it, by the tiles of its ends.
local function leg_key(a, b)
  local ax, ay, bx, by = math.floor(a.x), math.floor(a.y), math.floor(b.x), math.floor(b.y)
  if ax > bx or (ax == bx and ay > by) then
    ax, ay, bx, by = bx, by, ax, ay
  end
  return ax .. "," .. ay .. "," .. bx .. "," .. by
end

local function distance(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

-- What is known of a leg's road: its length, false for no road, or nil if not measured.
local function measured(legs, leg)
  local length = legs.lengths[leg]
  if length ~= nil and game.tick - legs.ticks[leg] >= LEG_MEMORY_TICKS then
    return nil
  end
  return length
end

-- The way from `from` to `to` on a surface, through any number of tunnels or none, as the shortest
-- by road the pathfinder measured: a Dijkstra over the two ends and every tunnel entry, its road
-- legs measured, or counted as the straight line (a road is never shorter) until they are. Once
-- every road leg of the shortest way is measured, no other can be shorter; until then, those legs
-- are asked of the pathfinder (`tunnels.ask`) and `waiter` (see tunnels.resume) waits for them.
-- `road`: the road from `from` to `to` if just measured (a search's answer: false for none).
-- Returns the tunnels to go through in turn ({ entry, exit, length, from, to } each: where to drive
-- in, where it comes out, how far apart, and the two portals' unit numbers; none for the road) and
-- the way's length; false while waiting; nil when there is nothing to weigh (no tunnel on the
-- surface, an end off road, no way at all): the road, if any, as the pathfinder finds it.
-- Few portals are expected, so every one is looked at for each step.
function tunnels.plan(surface_index, from, to, road, force, waiter)
  if not (has_tunnels(surface_index) and from and to) then
    return nil
  end
  local nets = nets_of(surface_index)
  local portals = nets.portals
  local surface = game.surfaces[surface_index]
  local start, goal = net_of(nets, surface, from), net_of(nets, surface, to)
  if not (start and goal) then
    return nil
  end
  local legs = legs_of(surface_index)
  if road ~= nil then
    local leg = leg_key(from, to)
    legs.lengths[leg], legs.ticks[leg] = road, game.tick
  end
  -- States: 1 is at `from`, 2 at `to`; 2 + i at portal i's entry, come by road, and 2 + count + i
  -- there, come out of its partner's tunnel. Only `from` and a tunnel's way out go on by road: two
  -- roads one after the other are never shorter than the road from one end to the other, so asking
  -- about them would only cost the pathfinder's time.
  local count = #portals
  local points, on = { from, to }, { start, goal }
  for index, portal in ipairs(portals) do
    points[2 + index], points[2 + count + index] = portal.entry, portal.entry
    on[2 + index] = net_of(nets, surface, portal.entry)
    on[2 + count + index] = on[2 + index]
  end
  -- `by[state]`: how it was reached from previous[state]: a leg key not yet measured, true for a
  -- measured road, or the portal whose tunnel led there.
  local best, previous, by, done = { [1] = 0 }, {}, {}, {}
  while true do
    local current, shortest = nil, math.huge
    for state, cost in pairs(best) do
      if not done[state] and cost < shortest then
        current, shortest = state, cost
      end
    end
    if not current or current == 2 then
      break
    end
    done[current] = true
    -- On road to `to` and every portal of its network (a mouth off road is on none), and from
    -- `from` to `to` wherever the pathfinder found a road (just laid, it may join networks still
    -- known apart).
    local net = (current == 1 or current > 2 + count) and on[current]
    if net or current == 1 then
      for state = 2, count + 2 do
        local direct = current == 1 and state == 2 and road
        if (net and points[state] ~= points[current] and not done[state] and on[state] == net) or direct then
          local leg = leg_key(points[current], points[state])
          local length = measured(legs, leg)
          local known = length ~= nil
          if length == nil then
            length = distance(points[current], points[state])
          end
          if length then
            local cost = shortest + length
            if not best[state] or cost < best[state] then
              best[state], previous[state], by[state] = cost, current, known or leg
            end
          end
        end
      end
    end
    -- Through this portal's tunnel, to a mouth on road.
    local portal = current > 2 and portals[(current - 3) % count + 1]
    local other = portal and portal.other and portal.length and 2 + count + portal.other
    if other and on[other] and not done[other] then
      local cost = shortest + portal.length
      if not best[other] or cost < best[other] then
        best[other], previous[other], by[other] = cost, current, portal
      end
    end
  end
  if not best[2] then
    return nil
  end
  -- The way back from `to`: its tunnels, and its roads not yet measured.
  local hops, unknown, state = {}, {}, 2
  while state ~= 1 do
    local how, before = by[state], previous[state]
    if type(how) == "string" then
      unknown[#unknown + 1] = { leg = how, from = points[before], to = points[state] }
    elseif how ~= true then
      table.insert(hops, 1, {
        entry = how.entry,
        exit = portals[how.other].entry,
        length = how.length,
        from = how.id,
        to = portals[how.other].id,
      })
    end
    state = before
  end
  if #unknown == 0 then
    return hops, best[2]
  end
  storage.tunnel_waiters = storage.tunnel_waiters or {}
  local waiting = storage.tunnel_waiters[surface_index] or {}
  storage.tunnel_waiters[surface_index] = waiting
  for _, leg in ipairs(unknown) do
    local asked = legs.asked[leg.leg]
    if not asked or game.tick - asked >= ASK_TICKS then
      legs.asked[leg.leg] = game.tick
      storage.tunnel_leg_asks = storage.tunnel_leg_asks or {}
      storage.tunnel_leg_asks[tunnels.ask(surface, force, leg.from, leg.to)] =
        { surface_index = surface_index, leg = leg.leg, from = leg.from, version = legs.version }
    end
    waiting[leg.leg] = waiting[leg.leg] or {}
    waiting[leg.leg][waiter.id] = waiter
  end
  return false
end

-- A pathfinder answer, if it was a leg's (`length`: the road's, nil for none): remembered for the
-- road it was asked about, and every owner waiting for the leg resumes. Returns whether it was.
function tunnels.answered(id, length, busy)
  local asks = storage.tunnel_leg_asks
  local ask = asks and asks[id]
  if not ask then
    return false
  end
  asks[id] = nil
  local legs = storage.tunnel_legs and storage.tunnel_legs[ask.surface_index]
  if legs and legs.version == ask.version then
    legs.asked[ask.leg] = nil
    if not busy then
      legs.lengths[ask.leg], legs.ticks[ask.leg] = length or false, game.tick
    end
  end
  local waiting = storage.tunnel_waiters and storage.tunnel_waiters[ask.surface_index]
  local waiters = waiting and waiting[ask.leg]
  if waiters then
    waiting[ask.leg] = nil
    -- In the order they began waiting, the same in every player's game.
    local list = {}
    for _, waiter in pairs(waiters) do
      list[#list + 1] = waiter
    end
    table.sort(list, function(a, b)
      return a.order < b.order
    end)
    for _, waiter in ipairs(list) do
      tunnels.resume(waiter, busy)
    end
  end
  return true
end

-- The way out of a portal's mouth, as an orientation (0 north, 0.25 east...), if it is still there.
function tunnels.facing(unit_number)
  local portal = storage.tunnel_portals and storage.tunnel_portals[unit_number]
  local entity = portal and portal.entity
  return entity and entity.valid and entity.direction / 16 or nil
end

local ROAD_TILES = { [ROADS[1]] = true, [ROADS[2]] = true }
-- How a freighter comes out of portal `unit_number`, whose entry tile's centre is `exit`: where it
-- appears (just inside the mouth's edge, on the entry tile), the first point it drives to (straight
-- out: a tile on, if that is road too, else the entry tile's centre) and the way it faces (out of
-- the mouth). The game turns a unit to the first point of its route the moment it is given one, and
-- the route on from the entry tile often starts across the road, so without this first stretch
-- straight out it was never seen to leave the mouth (the owner's video, November 8, 2026). Nil if
-- the portal is gone.
-- It appears 0.25 from the entry tile's centre, so its collision box (0.2 each way) ends 0.05 short
-- of the portal's tile. At 0.3 the box ended on that edge, and the game, which rounds positions to
-- 1/256 tile towards zero, put it on the edge itself out of a mouth facing west or north at negative
-- coordinates: touching the portal's tile, which is off road, so no route led on from there, and a
-- loaded freighter took its load back to the provider (the owner's save, November 8, 2026).
local WAY_OUT_INSET = 0.25
function tunnels.way_out(unit_number, exit)
  local portal = storage.tunnel_portals and storage.tunnel_portals[unit_number]
  local entity = portal and portal.entity
  if not (entity and entity.valid) then
    return nil
  end
  local facing = FACING[entity.direction] or FACING[defines.direction.north]
  local start = { x = exit.x - facing[1] * WAY_OUT_INSET, y = exit.y - facing[2] * WAY_OUT_INSET }
  local beyond = { x = exit.x + facing[1], y = exit.y + facing[2] }
  local tile = entity.surface.get_tile(math.floor(beyond.x), math.floor(beyond.y))
  local out = tile.valid and ROAD_TILES[tile.name] and beyond or { x = exit.x, y = exit.y }
  return start, out, entity.direction / 16
end

-- Whether a tunnel planned by `route` is still there, its two portals still paired.
function tunnels.open(hop)
  local portals = storage.tunnel_portals or {}
  local entrance, exit = portals[hop.from], portals[hop.to]
  entrance, exit = entrance and entrance.entity, exit and exit.entity
  if not (entrance and exit and entrance.valid and exit.valid) then
    return false
  end
  local other = partner(entrance)
  return other ~= nil and other.unit_number == hop.to
end

return tunnels
