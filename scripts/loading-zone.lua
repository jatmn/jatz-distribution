-- SPDX-License-Identifier: LGPL-3.0-only
-- Keep each depot's loading zone tile clear of decoratives (plants, decorative rocks, grass).
--
-- The marking is painted ground, drawn above decoratives that render low, but several base
-- decoratives render on "floor" or even "object" layers (medium and big sand rocks), which no
-- ground layer can sit above. So, as Factorio does under any placed building, decoratives whose
-- footprint overlaps the loading zone tile are removed when a depot is built or turned.
local orientation = require("prototypes.orientation")

local loading_zone = {}

local ROLES = { "provider", "request", "buffer", "fuel", "liquid-provider", "liquid-request", "liquid-buffer" }
loading_zone.depots = {}
for _, role in ipairs(ROLES) do
  loading_zone.depots["jatz-" .. role .. "-depot"] = true
end

-- Mining Drones' mining depot (Mining_Drones, Mining_Drones_Remastered and Mining_Drones_Mod all
-- name it this): a 5 by 8 assembling machine whose drones mine the area in front of it. Its
-- loading zone is the tile just past its back end, opposite the mining area, where Transport
-- Drones puts its road node too. Only when one of those mods is installed: event filters and
-- entity searches refuse names that don't exist.
loading_zone.mining_depot = "mining-depot"
local MINING_SHIFT = { north = { 0, 4.5 }, east = { -4.5, 0 }, south = { 0, -4.5 }, west = { 4.5, 0 } }
if prototypes.entity[loading_zone.mining_depot] then
  loading_zone.depots[loading_zone.mining_depot] = true
end

local DIRECTION_NAMES = {
  [defines.direction.north] = "north",
  [defines.direction.east] = "east",
  [defines.direction.south] = "south",
  [defines.direction.west] = "west",
}

-- The largest distance any decorative's footprint reaches from its tile's centre.
local reach
local function decorative_reach()
  if not reach then
    reach = 0
    for _, decorative in pairs(prototypes.decorative) do
      local box = decorative.collision_box
      reach = math.max(reach, -box.left_top.x, -box.left_top.y, box.right_bottom.x, box.right_bottom.y)
    end
  end
  return reach
end

-- The centre of a depot's loading zone tile.
function loading_zone.tile_centre(entity)
  local shifts = entity.name == loading_zone.mining_depot and MINING_SHIFT or orientation.loading_zone_shift
  local shift = shifts[DIRECTION_NAMES[entity.direction]]
  return entity.position.x + shift[1], entity.position.y + shift[2]
end

-- Remove every decorative whose footprint overlaps the depot's loading zone tile.
function loading_zone.clear(entity)
  local x, y = loading_zone.tile_centre(entity)
  local surface = entity.surface
  local search = decorative_reach() + 0.5
  local found = surface.find_decoratives_filtered({ area = { { x - search, y - search }, { x + search, y + search } } })
  for _, decorative in pairs(found) do
    local box = decorative.decorative.collision_box
    -- Decoratives sit on whole tiles; their footprint is measured from the tile's centre.
    local cx, cy = decorative.position.x + 0.5, decorative.position.y + 0.5
    if
      cx + box.right_bottom.x > x - 0.5
      and cx + box.left_top.x < x + 0.5
      and cy + box.right_bottom.y > y - 0.5
      and cy + box.left_top.y < y + 0.5
    then
      surface.destroy_decoratives({ position = decorative.position, name = decorative.decorative.name })
    end
  end
end

-- Clear the loading zones of every depot already in the game (new saves and updated ones).
function loading_zone.clear_all()
  local names = {}
  for name in pairs(loading_zone.depots) do
    names[#names + 1] = name
  end
  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered({ name = names })) do
      loading_zone.clear(entity)
    end
  end
end

return loading_zone
