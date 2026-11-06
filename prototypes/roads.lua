-- SPDX-License-Identifier: LGPL-3.0-only
-- Roads: the only ground dispatched freighters drive on. The road is a placeable floor tile
-- like stone path, drawn with the slag path art from Yuoki Industries - Railways
-- (assets/roads/README.md; CC BY-NC-SA 4.0, not covered by this file's licence).
--
-- Every other tile gets the "jatz_off_road" collision layer (prototypes/off-road.lua, run in
-- data-final-fixes so tiles from every mod are included), and the freighter drone collides
-- with that layer only. The engine's own pathfinder then keeps freighters on roads.
-- Both road tiles carry the "jatz_road" layer, which every building except belts, pipes and train
-- tracks collides with (prototypes/off-road.lua), so nothing else can be built on road.
local constants = require("prototypes.constants")
local tile_collision_masks = require("__base__/prototypes/tile/tile-collision-masks")

local name = constants.road
local art = "__jatz-distribution__/" .. constants.road_art
local stone_path = data.raw.tile["stone-path"]

local collision_mask = tile_collision_masks.ground()
collision_mask.layers[constants.road_layer] = true

local road = {
  type = "tile",
  name = name,
  order = "d[road]",
  subgroup = constants.subgroup,
  needs_correction = false,
  minable = { mining_time = 0.1, result = name },
  mined_sound = stone_path.mined_sound,
  collision_mask = collision_mask,
  walking_speed_modifier = 1.3,
  vehicle_friction_modifier = stone_path.vehicle_friction_modifier,
  -- Above base and Space Age floors (0-33, 60, 70 are taken), so roads laid over concrete or
  -- stone path draw on top of it.
  layer = 61,
  layer_group = "ground-artificial",
  decorative_removal_probability = 1,
  variants = {
    main = {
      { picture = art .. "slag1.png", count = 16, size = 1 },
      { picture = art .. "slag2.png", count = 4, size = 2, probability = 0.39 },
      { picture = art .. "slag4.png", count = 4, size = 4, probability = 1 },
    },
    transition = {
      overlay_layout = {
        inner_corner = { spritesheet = art .. "concrete-inner-corner.png", count = 8 },
        outer_corner = { spritesheet = art .. "concrete-outer-corner.png", count = 8 },
        side = { spritesheet = art .. "concrete-side.png", count = 8 },
        u_transition = { spritesheet = art .. "concrete-u.png", count = 8 },
        o_transition = { spritesheet = art .. "concrete-o.png", count = 1 },
      },
    },
  },
  walking_sound = stone_path.walking_sound,
  build_sound = stone_path.build_sound,
  map_color = { 90, 70, 50 },
  scorch_mark_color = stone_path.scorch_mark_color,
  trigger_effect = stone_path.trigger_effect,
}

-- The road a depot lays under its loading zone sign when built, so a road one tile away
-- connects (scripts/depot-road.lua). It looks and drives like road and blends into it, but has
-- no item: it can't be placed by hand, and mining it gives nothing (the script puts back the
-- ground it covered). It is a separate tile so that only road the depot laid is removed with the
-- depot; road a player lays there is theirs to keep.
local depot_road = table.deepcopy(road)
depot_road.name = constants.depot_road
depot_road.order = "d[road]-b[depot]"
depot_road.hidden = true
depot_road.minable = { mining_time = 0.1 }
depot_road.layer = 62
depot_road.transition_merges_with_tile = name

data:extend({
  { type = "collision-layer", name = constants.off_road_layer },
  { type = "collision-layer", name = constants.road_layer },
  road,
  depot_road,
  {
    type = "item",
    name = name,
    icon = "__jatz-distribution__/" .. constants.road_art .. "pslag_icon.png",
    icon_size = 32,
    subgroup = constants.subgroup,
    -- After the freighter ("c[freighter]"): last in our row.
    order = "d[road]",
    stack_size = 100,
    place_as_tile = {
      result = name,
      condition_size = 1,
      condition = { layers = { water_tile = true } },
    },
  },
  {
    -- Free while the mod is in development, unlocked by research (prototypes/technologies.lua);
    -- each craft makes ten tiles.
    type = "recipe",
    name = name,
    enabled = false,
    energy_required = 0.5,
    ingredients = {},
    results = { { type = "item", name = name, amount = 10 } },
  },
})
