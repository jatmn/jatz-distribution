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
  local shift = orientation.loading_zone_shift[DIRECTION_NAMES[entity.direction]]
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

local function on_changed(event)
  local entity = event.entity or event.destination
  if entity and entity.valid and loading_zone.depots[entity.name] then
    loading_zone.clear(entity)
  end
end

function loading_zone.register()
  local filters = {}
  for name in pairs(loading_zone.depots) do
    filters[#filters + 1] = { filter = "name", name = name }
  end
  -- Every way a depot can be built: by hand, robots, other mods' scripts, revived ghosts, platforms.
  for _, event in ipairs({
    defines.events.on_built_entity,
    defines.events.on_robot_built_entity,
    defines.events.script_raised_built,
    defines.events.script_raised_revive,
    defines.events.on_space_platform_built_entity,
  }) do
    script.on_event(event, on_changed, filters)
  end
  -- Turning or flipping a depot moves its loading zone.
  script.on_event(defines.events.on_player_rotated_entity, on_changed)
  script.on_event(defines.events.on_player_flipped_entity, on_changed)
end

return loading_zone
