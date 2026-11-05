-- SPDX-License-Identifier: LGPL-3.0-only
-- Road collision layers. Runs in data-final-fixes, after every mod has added its tiles and
-- entities.
-- * Every tile except roads (the player's and the depots' own) is off-road, so freighter drones
--   can't path over it.
-- * Every buildable entity except belts, pipes, train tracks and vehicles collides with road
--   (the "jatz_road" layer on both road tiles, prototypes/roads.lua), so nothing else can be built
--   on road. A depot's loading zone tile is outside its box, so it can still be road.
local collision_mask_util = require("collision-mask-util")
local constants = require("prototypes.constants")

local roads = { [constants.road] = true, [constants.depot_road] = true }
for name, tile in pairs(data.raw.tile) do
  if not roads[name] then
    -- A tile without a mask collides with nothing, so start from an empty one.
    tile.collision_mask = tile.collision_mask or { layers = {} }
    tile.collision_mask.layers = tile.collision_mask.layers or {}
    tile.collision_mask.layers[constants.off_road_layer] = true
  end
end

-- Entity types that may stand on road.
local allowed_on_road = {}
for _, entity_type in ipairs({
  -- Belts.
  "transport-belt",
  "underground-belt",
  "splitter",
  "lane-splitter",
  "loader",
  "loader-1x1",
  "linked-belt",
  -- Pipes.
  "pipe",
  "pipe-to-ground",
  "infinity-pipe",
  -- Train tracks, ground and elevated, with their ramps and supports.
  "straight-rail",
  "curved-rail-a",
  "curved-rail-b",
  "half-diagonal-rail",
  "legacy-straight-rail",
  "legacy-curved-rail",
  "elevated-straight-rail",
  "elevated-curved-rail-a",
  "elevated-curved-rail-b",
  "elevated-half-diagonal-rail",
  "rail-ramp",
  "rail-support",
  -- Vehicles drive over road (the freighter among them), and trains cross it on their tracks.
  "car",
  "spider-vehicle",
  "locomotive",
  "cargo-wagon",
  "fluid-wagon",
  "artillery-wagon",
  "infinity-cargo-wagon",
}) do
  allowed_on_road[entity_type] = true
end

-- Entities players can build: the place result of an item, or placeable by one.
local buildable = {}
for _, prototypes in pairs(data.raw) do
  for _, prototype in pairs(prototypes) do
    if type(prototype.place_result) == "string" then
      buildable[prototype.place_result] = true
    end
  end
end

for entity_type in pairs(defines.prototypes.entity) do
  if not allowed_on_road[entity_type] then
    for name, entity in pairs(data.raw[entity_type] or {}) do
      if buildable[name] or entity.placeable_by then
        local mask = collision_mask_util.get_mask(entity)
        -- An entity that collides with nothing is meant to overlap anything; leave it so.
        if next(mask.layers) then
          mask.layers[constants.road_layer] = true
          entity.collision_mask = mask
        end
      end
    end
  end
end
