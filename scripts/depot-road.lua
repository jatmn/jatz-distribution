-- SPDX-License-Identifier: LGPL-3.0-only
-- Every depot lays a road tile under its loading zone sign when built, so road a tile away
-- connects to it and players aren't left wondering why a depot next to their road isn't on it.
-- The tile is jatz-depot-road (prototypes/roads.lua): it drives and looks like road, but only
-- depots lay it, so it marks road the depot owns. When the depot is removed (by any means) or
-- turned, the ground it covered comes back exactly as it was, tile and hidden tiles alike, unless
-- something else now claims the spot:
-- * road or ground that was already there when the depot was built is left alone, since nothing
--   is laid over road and the depot never owned it;
-- * a tile a player places over the depot's road is theirs, and stays;
-- * another depot loading from the same tile keeps the road until the last of them goes.
-- Mining the depot's road by hand puts back the ground it covered too, and gives no item.
-- Nothing is laid on water or on space platforms (where the tile is the platform itself).
local loading_zone = require("scripts.loading-zone")

local depot_road = {}

local ROAD, DEPOT_ROAD = "jatz-road", "jatz-depot-road"
depot_road.name = DEPOT_ROAD

-- storage.depot_roads[unit_number] = { phase = "owned", surface = index, x, y, tile, hidden, double }: the tile
-- position the depot laid road on, and the ground it covered there. `{ phase = "released" }` means the player
-- mined or covered the depot's road: it isn't laid again for that depot until it is turned.
local function records()
  storage.depot_roads = storage.depot_roads or {}
  if not storage.depot_roads_version then
    for id, record in pairs(storage.depot_roads) do
      if record == false then
        storage.depot_roads[id] = { phase = "released" }
      else
        record.phase = record.phase or "owned"
      end
    end
    storage.depot_roads_version = 1
  end
  return storage.depot_roads
end

local function tile_position(entity)
  local x, y = loading_zone.tile_centre(entity)
  return math.floor(x), math.floor(y)
end

-- Another depot's record for the same tile, if any.
local function sharing(surface_index, x, y, except)
  for unit_number, record in pairs(records()) do
    if
      record.phase == "owned"
      and unit_number ~= except
      and record.surface == surface_index
      and record.x == x
      and record.y == y
    then
      return record
    end
  end
end

-- Put the ground a record covered back on its tile: the tile and exactly the hidden tiles there
-- were (laying road may have hidden the ground under it).
local function put_back(surface, record)
  local position = { record.x, record.y }
  surface.set_tiles({ { name = record.tile, position = position } }, true, false, true, false)
  surface.set_hidden_tile(position, record.hidden)
  if record.hidden then
    surface.set_double_hidden_tile(position, record.double)
  end
end

-- Put back the ground a record covered, if the depot's road is still there and no other depot
-- loads from that tile. Returns true if road was removed.
local function restore(unit_number, record)
  if sharing(record.surface, record.x, record.y, unit_number) then
    return false
  end
  local surface = game.surfaces[record.surface]
  if not surface or not record.tile then
    return false
  end
  if surface.get_tile(record.x, record.y).name ~= DEPOT_ROAD then
    return false
  end
  put_back(surface, record)
  return true
end

-- Remove the road a depot laid (removed or turned depot). Returns the surface index if road went.
function depot_road.lift(unit_number)
  local record = records()[unit_number]
  -- Forget the depot whether or not it still owns road (`released`: the player took the spot).
  records()[unit_number] = nil
  if not record or record.phase ~= "owned" then
    return nil
  end
  return restore(unit_number, record) and record.surface or nil
end

-- Lay road under a depot's loading zone sign, first lifting any it laid elsewhere (a turned
-- depot). Returns the surface indices where road was laid and removed (either may be nil).
function depot_road.lay(entity)
  local unit_number = entity.unit_number
  local removed = depot_road.lift(unit_number)
  local surface = entity.surface
  if surface.platform then
    return nil, removed
  end
  local x, y = tile_position(entity)
  local tile = surface.get_tile(x, y)
  if not tile.valid or tile.name == ROAD or tile.name == "out-of-map" or tile.collides_with("water_tile") then
    return nil, removed
  end
  script.register_on_object_destroyed(entity)
  if tile.name == DEPOT_ROAD then
    -- Another depot's road: share its record of the ground underneath. Depot road nobody owns
    -- (from a cloned area, say) is adopted, with the ground hidden under it as what it covered.
    local other = sharing(surface.index, x, y, unit_number)
    local position = { x, y }
    local record = { phase = "owned", surface = surface.index, x = x, y = y }
    if other then
      -- Copied as they are, nil included: a missing hidden tile must stay missing.
      record.tile, record.hidden, record.double = other.tile, other.hidden, other.double
    else
      record.tile, record.hidden = surface.get_hidden_tile(position), surface.get_double_hidden_tile(position)
    end
    records()[unit_number] = record
    return nil, removed
  end
  local position = { x, y }
  records()[unit_number] = {
    phase = "owned",
    surface = surface.index,
    x = x,
    y = y,
    tile = tile.name,
    hidden = surface.get_hidden_tile(position),
    double = surface.get_double_hidden_tile(position),
  }
  surface.set_tiles({ { name = DEPOT_ROAD, position = position } }, true, false, true, false)
  return surface.index, removed
end

-- A depot replaced by a new entity standing where it stood, facing the same way
-- (scripts/legacy-depots.lua): the road it laid is the new one's.
function depot_road.replaced(old_unit_number, entity)
  local record = records()[old_unit_number]
  if record == nil then
    return
  end
  records()[old_unit_number] = nil
  records()[entity.unit_number] = record
  script.register_on_object_destroyed(entity)
end

-- Tile positions arrive as { x = .., y = .. } from the game, and may be { x, y } from scripts.
local function xy(position)
  return position.x or position[1], position.y or position[2]
end

-- Ownership ends for every depot sharing the tile. Mining restores its layers once; covering
-- preserves the player's replacement. A released record prevents reload from claiming it again.
local function release(surface_index, position, reason)
  local x, y = xy(position)
  local ground
  for unit_number, record in pairs(records()) do
    if record.phase == "owned" and record.surface == surface_index and record.x == x and record.y == y then
      ground = ground or record
      records()[unit_number] = { phase = "released", reason = reason }
    end
  end
  local surface = game.surfaces[surface_index]
  if reason == "mined" and ground and ground.tile and surface then
    put_back(surface, ground)
  end
end

function depot_road.mined(surface_index, position)
  release(surface_index, position, "mined")
end

function depot_road.covered(surface_index, position)
  release(surface_index, position, "covered")
end

-- Depots already in the game without a road record (the mod added to a save) get their road.
-- Returns the surface indices where road was laid, as a set.
function depot_road.lay_all(names)
  local laid = {}
  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered({ name = names })) do
      if entity.unit_number and records()[entity.unit_number] == nil then
        local surface_index = depot_road.lay(entity)
        if surface_index then
          laid[surface_index] = true
        end
      end
    end
  end
  return laid
end

return depot_road
