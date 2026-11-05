-- SPDX-License-Identifier: LGPL-3.0-only
-- The freighter as it drives itself between depots: a unit, so the engine's pathfinder steers
-- it. Its only collision layer is "jatz_off_road", which every tile but the road has
-- (prototypes/off-road.lua), so every path it finds stays on roads. It collides with no
-- buildings, players or other freighters, and runs without fuel for now. Enemies can attack and
-- destroy it; it never fights back. scripts/logistics.lua creates one per delivery and removes it
-- when the delivery is done, and makes it run over enemy units it drives through and pollute a
-- little while out.
--
-- Its cargo paint shows what it carries (scripts/freighter-paint.lua): this is defined once per
-- paint, light grey for the empty freighter, and logistics swaps a freighter for the one painted
-- for its load when it loads. Every paint draws the same sprite sheets, only tinted.
local constants = require("prototypes.constants")
local art = require("prototypes.freighter-art")
local paint = require("scripts.freighter-paint")

-- The freighter drone `name`, its cargo painted `cargo` (nil: the artwork's own slate blue).
local function drone(name, cargo)
  local animation = art.animation(cargo and { cargo = cargo } or nil)
  return {
    type = "unit",
    name = name,
    -- Every paint is the same freighter to the player.
    localised_name = { "entity-name." .. constants.freighter_drone },
    localised_description = { "entity-description." .. constants.freighter_drone },
    icon = constants.freighter_icon,
    icon_size = constants.icon_size,
    hidden = true,
    flags = { "placeable-player", "placeable-off-grid", "not-repairable", "not-blueprintable", "not-deconstructable" },
    max_health = 500,
    -- A target enemies go for, as they do the player's other vehicles and units (a unit's
    -- default, said here because deliveries rely on it).
    is_military_target = true,
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
    -- Tiles per tick: Transport Drones' default (0.066, before speed research), about 4 tiles a
    -- second (14.3 km/h). It was 0.2.
    movement_speed = 0.066,
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
    -- Units must be able to attack; this one never does: every command it gets is
    -- `distraction = none`, so it neither fights back nor turns aside when attacked.
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
  }
end

local drones = {
  drone(paint.empty, paint.empty_color),
  drone(paint.unknown, nil),
}
for _, entry in ipairs(paint.palette()) do
  drones[#drones + 1] = drone(entry.name, entry.color)
end
data:extend(drones)
