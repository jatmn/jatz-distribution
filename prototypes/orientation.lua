-- SPDX-License-Identifier: LGPL-3.0-only
-- How each depot sits when placed without rotating: its loading zone is always to the south.
--
-- The artwork's direction names say where each depot's front faces. Cargo depots and the
-- Fuel depot load through an opening at the front, so the mod shows their "south" artwork
-- by default (the opening faces the player) and turns their pipe ports with it. Liquid
-- depots keep their pipes to the north and load from the opposite, south side.
-- Factorio then rotates pictures, ports and the loading zone together with the entity.
local orientation = {}

-- Depots shown half a turn from their artwork's default, so the opening faces south.
orientation.half_turn = { provider = true, request = true, buffer = true, fuel = true }

-- Where the loading zone tile sits for each entity direction: one tile beyond the 3x3
-- footprint, south of an unrotated depot, following the depot as it turns clockwise.
orientation.loading_zone_shift = {
  north = { 0, 2 },
  east = { -2, 0 },
  south = { 0, -2 },
  west = { 2, 0 },
}

-- The depot's Sprite4Way, as seen when the entity faces each direction.
function orientation.pictures(role, art)
  if not orientation.half_turn[role] then
    return art
  end
  return { north = art.south, east = art.west, south = art.north, west = art.east }
end

-- The depot's pipe connections for an unrotated entity (Factorio rotates them from there).
function orientation.ports(role, ports)
  local turned = {}
  for index, port in ipairs(ports) do
    local copy = {}
    for key, value in pairs(port) do
      copy[key] = value
    end
    if orientation.half_turn[role] then
      copy.position = { -port.position[1], -port.position[2] }
      copy.direction = (port.direction + 8) % 16
    end
    turned[index] = copy
  end
  return turned
end

-- A Sprite4Way drawing `sprite` (a table without shift) on the loading zone tile.
function orientation.loading_zone(sprite)
  local patch = {}
  for direction, shift in pairs(orientation.loading_zone_shift) do
    local copy = {}
    for key, value in pairs(sprite) do
      copy[key] = value
    end
    copy.shift = { shift[1], shift[2] }
    patch[direction] = copy
  end
  return patch
end

return orientation
