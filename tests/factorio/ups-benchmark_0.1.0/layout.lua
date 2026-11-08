-- SPDX-License-Identifier: LGPL-3.0-only
-- The benchmark map, as plain data: road rectangles and depots for each surface. Pure Lua 5.2 with
-- no game API, so the in-game benchmark (control.lua) and the engine-free emulator
-- (tests/lua/ups-emulator.lua) build exactly the same map from the same preset.
--
-- Each surface is a grid of junctions `cell` tiles apart. A randomised depth-first maze joins every
-- junction, so routes wind through U and S bends and branches end in dead ends; a share of the
-- remaining grid links is added back as extra crossings, and every `arterial`-th grid line is a
-- 5-tile-wide road with gaps. Other roads are 1 tile wide. Depots stand beside 1-tile roads with
-- their loading zone on the road; some providers face a request depot across the same road tile.
-- Fuel depots, for the mods whose freighters fill up at them, are placed last from a random stream
-- of their own, so the other depots are exactly the same with or without them.
-- Coordinates are tiles; a depot is given by its loading tile and the side of the depot that tile
-- is on (the direction from the depot to the road).
local layout = {}

-- Items providers hold and request depots ask for: common intermediates with different stack sizes.
layout.items = {
  "iron-plate",
  "copper-plate",
  "steel-plate",
  "iron-gear-wheel",
  "electronic-circuit",
  "copper-cable",
  "coal",
  "stone",
  "plastic-bar",
  "stone-brick",
}
-- What fuel depots are kept stocked with.
layout.fuel = "solid-fuel"

-- Park-Miller minimal standard generator: exact in doubles, so every Lua and every run agrees.
local function random_source(seed)
  local state = seed % 2147483647
  if state <= 0 then
    state = state + 2147483646
  end
  return function(low, high)
    state = state * 16807 % 2147483647
    if not low then
      return state / 2147483647
    end
    return low + state % (high - low + 1)
  end
end

local function key(x, y)
  return x * 65536 + y
end

-- One surface: returns { roads = { {x1, y1, x2, y2}, ... }, depots = { ... }, tiles = n }.
local function surface_layout(preset, random, fuel_random)
  local n, cell, arterial = preset.grid, preset.cell, preset.arterial
  local origin = -math.floor(n * cell / 2)
  local function at(i)
    return origin + i * cell
  end
  -- Links between junction (i, j) and its east (h) or south (v) neighbour.
  local links = {}
  local function link_key(i, j, horizontal)
    return (horizontal and "h" or "v") .. i .. ":" .. j
  end
  -- Maze: iterative depth-first search over the junctions.
  local seen = { [key(0, 0)] = true }
  local stack = { { 0, 0 } }
  while #stack > 0 do
    local top = stack[#stack]
    local i, j = top[1], top[2]
    local options = {}
    for _, step in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local ni, nj = i + step[1], j + step[2]
      if ni >= 0 and nj >= 0 and ni < n and nj < n and not seen[key(ni, nj)] then
        options[#options + 1] = { ni, nj }
      end
    end
    if #options == 0 then
      stack[#stack] = nil
    else
      local pick = options[random(1, #options)]
      local ni, nj = pick[1], pick[2]
      links[link_key(math.min(i, ni), math.min(j, nj), nj == j)] = true
      seen[key(ni, nj)] = true
      stack[#stack + 1] = pick
    end
  end
  -- Extra crossings, and the wide arterial lines with gaps.
  local function wide(i, j, horizontal)
    if horizontal then
      return j % arterial == 0
    end
    return i % arterial == 0
  end
  for i = 0, n - 1 do
    for j = 0, n - 1 do
      for _, horizontal in ipairs({ true, false }) do
        local ni, nj = horizontal and i + 1 or i, horizontal and j or j + 1
        if ni < n and nj < n then
          local name = link_key(i, j, horizontal)
          if not links[name] then
            local chance = wide(i, j, horizontal) and preset.arterial_share or preset.loops
            if random() < chance then
              links[name] = true
            end
          end
        end
      end
    end
  end
  -- Road rectangles and the set of road tiles.
  local roads, road = {}, {}
  local function fill(x1, y1, x2, y2)
    roads[#roads + 1] = { x1, y1, x2, y2 }
    for x = x1, x2 do
      for y = y1, y2 do
        road[key(x, y)] = true
      end
    end
  end
  local narrow = {}
  for name in pairs(links) do
    local horizontal, i, j = name:sub(1, 1) == "h", name:match("^.(%d+):(%d+)$")
    i, j = tonumber(i), tonumber(j)
    local half = wide(i, j, horizontal) and 2 or 0
    if horizontal then
      fill(at(i) - half, at(j) - half, at(i + 1) + half, at(j) + half)
    else
      fill(at(i) - half, at(j) - half, at(i) + half, at(j + 1) + half)
    end
    if half == 0 then
      narrow[#narrow + 1] = { i = i, j = j, horizontal = horizontal }
    end
  end
  -- Dead-end spurs: half a cell of road from a junction towards a neighbour it has no link to.
  for i = 0, n - 1 do
    for j = 0, n - 1 do
      if random() < preset.spurs then
        local x, y = at(i), at(j)
        local reach = math.floor(cell / 2)
        local step = random(1, 4)
        if step == 1 and i < n - 1 and not links[link_key(i, j, true)] then
          fill(x + 1, y, x + reach, y)
        elseif step == 2 and j < n - 1 and not links[link_key(i, j, false)] then
          fill(x, y + 1, x, y + reach)
        elseif step == 3 and i > 0 and not links[link_key(i - 1, j, true)] then
          fill(x - reach, y, x - 1, y)
        elseif step == 4 and j > 0 and not links[link_key(i, j - 1, false)] then
          fill(x, y - reach, x, y - 1)
        end
      end
    end
  end
  table.sort(narrow, function(a, b)
    if a.horizontal ~= b.horizontal then
      return a.horizontal
    end
    return a.i < b.i or (a.i == b.i and a.j < b.j)
  end)
  -- Depots: a 3x3 footprint clear of road and other depots, its loading tile on road.
  local used = {}
  local function footprint(tx, ty, side)
    -- Centre tile of the depot: two tiles from the loading tile, away from the road.
    local cx, cy = tx, ty
    if side == "north" then
      cy = ty + 2
    elseif side == "south" then
      cy = ty - 2
    elseif side == "east" then
      cx = tx - 2
    else
      cx = tx + 2
    end
    return cx, cy
  end
  local function free(tx, ty, side)
    if not road[key(tx, ty)] then
      return false
    end
    local cx, cy = footprint(tx, ty, side)
    for x = cx - 1, cx + 1 do
      for y = cy - 1, cy + 1 do
        if road[key(x, y)] or used[key(x, y)] then
          return false
        end
      end
    end
    return true
  end
  local function claim(tx, ty, side)
    local cx, cy = footprint(tx, ty, side)
    for x = cx - 1, cx + 1 do
      for y = cy - 1, cy + 1 do
        used[key(x, y)] = true
      end
    end
  end
  -- A random spot beside a narrow road: the loading tile, and the depot's side of the road.
  local function spot(across, source)
    local draw = source or random
    for _ = 1, 50 do
      local edge = narrow[draw(1, #narrow)]
      local offset = draw(3, cell - 3)
      local tx, ty, sides
      if edge.horizontal then
        tx, ty, sides = at(edge.i) + offset, at(edge.j), { "south", "north" }
      else
        tx, ty, sides = at(edge.i), at(edge.j) + offset, { "east", "west" }
      end
      -- side: where the road is, seen from the depot. A depot north of the road has it south.
      local first = draw(1, 2)
      local side, other = sides[first], sides[3 - first]
      if free(tx, ty, side) and (not across or free(tx, ty, other)) then
        return tx, ty, side, other
      end
    end
  end
  local depots = {}
  local providers = math.floor(preset.depots * preset.provider_share + 0.5)
  local requests = preset.depots - providers
  local across = math.floor(requests * preset.across_share + 0.5)
  local stocked = {}
  local function add(role, tx, ty, side, item)
    claim(tx, ty, side)
    local depot = { role = role, x = tx, y = ty, side = side, item = item }
    if role == "request" then
      depot.freighters = random(preset.freighters[1], preset.freighters[2])
    elseif role == "provider" then
      stocked[item] = true
    end
    depots[#depots + 1] = depot
    return depot
  end
  local items = layout.items
  -- Providers and request depots facing each other across one road tile: the shortest trips.
  for index = 1, across do
    local tx, ty, side, other = spot(true)
    if tx then
      local item = items[(index - 1) % #items + 1]
      add("provider", tx, ty, side, item)
      add("request", tx, ty, other, item)
      providers, requests = providers - 1, requests - 1
    end
  end
  for index = 1, providers do
    local tx, ty, side = spot(false)
    if tx then
      add("provider", tx, ty, side, items[(index - 1) % #items + 1])
    end
  end
  local offered = {}
  for _, item in ipairs(items) do
    if stocked[item] then
      offered[#offered + 1] = item
    end
  end
  for _ = 1, requests do
    local tx, ty, side = spot(false)
    if tx and #offered > 0 then
      add("request", tx, ty, side, offered[random(1, #offered)])
    end
  end
  for _ = 1, math.floor(preset.depots * preset.fuel_share + 0.5) do
    local tx, ty, side = spot(false, fuel_random)
    if tx then
      add("fuel", tx, ty, side, layout.fuel)
    end
  end
  local tiles = 0
  for _ in pairs(road) do
    tiles = tiles + 1
  end
  return { roads = roads, depots = depots, tiles = tiles, extent = { at(0) - 3, at(n - 1) + 3 } }
end

-- The whole map for a preset: { surfaces = { { name = ..., roads = ..., depots = ... }, ... } }.
-- Each request depot's `fuel` is the share of a full tank its freighters start with, spread evenly
-- from 5% to full (no random draw, so the layout stays the same): as after hours of play, when
-- freighters come home with whatever their last trips left, so filling up is part of the run.
-- Every `minimum_every`-th provider's `minimum` is the share of a full chest it keeps (a circuit
-- condition on its own contents, where the mod has one; again no random draw): freighters' promises
-- count against it, so its promises are checked in full every second.
function layout.generate(preset)
  local random = random_source(preset.seed)
  local surfaces = {}
  local requests, providers = 0, 0
  for index = 1, preset.surfaces do
    local surface = surface_layout(preset, random, random_source(preset.seed + 7919 * index))
    surface.name = "ups-benchmark-" .. index
    surfaces[index] = surface
    for _, depot in ipairs(surface.depots) do
      if depot.role == "request" then
        requests = requests + 1
        depot.fuel = 0.05 + 0.95 * (requests * 0.6180339887 % 1)
      elseif depot.role == "provider" then
        providers = providers + 1
        if preset.minimum_every and providers % preset.minimum_every == 0 then
          depot.minimum = preset.minimum_share
        end
      end
    end
  end
  return { surfaces = surfaces }
end

-- Totals, for the report.
function layout.summary(map)
  local summary =
    { surfaces = #map.surfaces, providers = 0, minimums = 0, requests = 0, fuel = 0, freighters = 0, road_tiles = 0 }
  for _, surface in ipairs(map.surfaces) do
    summary.road_tiles = summary.road_tiles + surface.tiles
    for _, depot in ipairs(surface.depots) do
      if depot.role == "request" then
        summary.requests = summary.requests + 1
        summary.freighters = summary.freighters + depot.freighters
      elseif depot.role == "fuel" then
        summary.fuel = summary.fuel + 1
      else
        summary.providers = summary.providers + 1
        if depot.minimum then
          summary.minimums = summary.minimums + 1
        end
      end
    end
  end
  return summary
end

return layout
