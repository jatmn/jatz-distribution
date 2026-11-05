-- SPDX-License-Identifier: LGPL-3.0-only
-- The freighter as it drives itself between depots: a unit, so the engine's pathfinder steers
-- it. Its only collision layer is "jatz_off_road", which every tile but the road has
-- (prototypes/off-road.lua), so every path it finds stays on roads. It ignores buildings,
-- players and other freighters, and runs without fuel for now. scripts/logistics.lua creates
-- one per delivery and removes it when the delivery is done.
local constants = require("prototypes.constants")
local art = require("prototypes.freighter-art")

local animation = art.animation()

data:extend({
  {
    type = "unit",
    name = constants.freighter_drone,
    icon = constants.freighter_icon,
    icon_size = constants.icon_size,
    hidden = true,
    flags = { "placeable-player", "placeable-off-grid", "not-repairable", "not-blueprintable", "not-deconstructable" },
    max_health = 500,
    -- Narrow enough for a one-tile road; the art is longer, but the unit turns on the spot.
    collision_box = { { -0.4, -0.4 }, { 0.4, 0.4 } },
    collision_mask = {
      layers = { [constants.off_road_layer] = true },
      colliding_with_tiles_only = true,
    },
    -- The middle of the body, so it is easy to point at while it turns.
    selection_box = art.box(0.8, 0.8),
    selection_priority = 60,
    run_animation = animation,
    -- Tiles per tick: 0.1 is 6 tiles a second (21.6 km/h), half the 0.2 it started at.
    movement_speed = 0.1,
    distance_per_frame = 1,
    rotation_speed = 0.05,
    vision_distance = 0,
    distraction_cooldown = 0,
    has_belt_immunity = true,
    ai_settings = {
      destroy_when_commands_fail = false,
      allow_try_return_to_spawner = false,
      do_separation = false,
      -- Keep the default path resolution: at a finer one (path_resolution_modifier 1) the
      -- engine finds no path at all for this 0.8-tile box on a one-tile road.
    },
    -- Units must be able to attack; this one never does (it is never distracted).
    attack_parameters = {
      type = "projectile",
      range = 0.5,
      cooldown = 60,
      ammo_category = "melee",
      ammo_type = {
        target_type = "entity",
        action = {
          type = "direct",
          action_delivery = {
            type = "instant",
            target_effects = { type = "damage", damage = { amount = 0, type = "physical" } },
          },
        },
      },
      animation = animation,
    },
  },
})
