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
-- shortest way from one network to another through the tunnels (`route`). Freighters still drive
-- every leg on road with the pathfinder; tunnels are only used between networks it can't join, never
-- as shortcuts within one.
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
  nets.count = nets.count + 1
  local net = nets.count
  local this_tick = flooded.tiles
  for _, tile in ipairs(tiles) do
    local found = key(tile.x, tile.y)
    this_tick[found] = net
    if noted[found] then
      nets.points[found] = net
    end
  end
  nets.points[wanted] = net
  return net
end

local function distance(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

-- The way from `from` to `to` on a surface through tunnels, when they are on different road
-- networks: its length, and the first tunnel to go through ({ entry, exit, length, from, to }:
-- where to drive in, where it comes out, how far apart, and the two portals' unit numbers). Nil
-- when there are no tunnels there, both are on the same network (the pathfinder drives that), or
-- no tunnels join them.
-- Each leg on road counts as the straight line (a road is never shorter), so the length is never
-- more than the way really is, as the search for the nearest provider needs (a road is never
-- shorter than the straight line, and this never shorter than the straight line from `from` to
-- `to`). Few portals are expected, so every one is looked at for each step.
function tunnels.route(surface_index, from, to)
  if not (has_tunnels(surface_index) and from and to) then
    return nil
  end
  local nets = nets_of(surface_index)
  local portals = nets.portals
  if #portals == 0 then
    return nil
  end
  local surface = game.surfaces[surface_index]
  local start, goal = net_of(nets, surface, from), net_of(nets, surface, to)
  if not (start and goal) or start == goal then
    return nil
  end
  -- Shortest known way to stand at each portal's entry, and the first tunnel taken to get there.
  local best, first, done = {}, {}, {}
  for index, portal in ipairs(portals) do
    if net_of(nets, surface, portal.entry) == start then
      best[index] = distance(from, portal.entry)
    end
  end
  local length, hop
  while true do
    local current, shortest = nil, math.huge
    for index, cost in pairs(best) do
      if not done[index] and cost < shortest then
        current, shortest = index, cost
      end
    end
    if not current or (length and shortest >= length) then
      break
    end
    done[current] = true
    local portal = portals[current]
    local net = net_of(nets, surface, portal.entry)
    -- Arrived there through a tunnel, on the goal's network: drive on to the goal.
    if first[current] and net == goal then
      local total = shortest + distance(portal.entry, to)
      if not length or total < length then
        length, hop = total, first[current]
      end
    end
    -- Through this portal's tunnel, to a mouth on road.
    local other = portal.other
    if other and not done[other] and portal.length and net_of(nets, surface, portals[other].entry) then
      local cost = shortest + portal.length
      if not best[other] or cost < best[other] then
        best[other] = cost
        first[other] = first[current] or current
      end
    end
    -- On road to another portal on the same network (a mouth off road is on none).
    for index, next_portal in ipairs(portals) do
      if net and not done[index] and index ~= current and net_of(nets, surface, next_portal.entry) == net then
        local cost = shortest + distance(portal.entry, next_portal.entry)
        if not best[index] or cost < best[index] then
          best[index] = cost
          first[index] = first[current]
        end
      end
    end
  end
  if not hop then
    return nil
  end
  local entrance = portals[hop]
  local exit = portals[entrance.other]
  return length,
    {
      entry = entrance.entry,
      exit = exit.entry,
      length = entrance.length,
      from = entrance.id,
      to = exit.id,
    }
end

-- The way out of a portal's mouth, as an orientation (0 north, 0.25 east...), if it is still there.
function tunnels.facing(unit_number)
  local portal = storage.tunnel_portals and storage.tunnel_portals[unit_number]
  local entity = portal and portal.entity
  return entity and entity.valid and entity.direction / 16 or nil
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
