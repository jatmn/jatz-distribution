-- SPDX-License-Identifier: LGPL-3.0-only
-- Mark every tile except roads as off-road, so freighter drones can't path over it. Runs in
-- data-final-fixes, after every mod has added its tiles.
local constants = require("prototypes.constants")

for name, tile in pairs(data.raw.tile) do
  if name ~= constants.road then
    -- A tile without a mask collides with nothing, so start from an empty one.
    tile.collision_mask = tile.collision_mask or { layers = {} }
    tile.collision_mask.layers = tile.collision_mask.layers or {}
    tile.collision_mask.layers[constants.off_road_layer] = true
  end
end
