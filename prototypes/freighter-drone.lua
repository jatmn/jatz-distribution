-- SPDX-License-Identifier: LGPL-3.0-only
-- The freighter as it drives itself between depots: a unit, so the engine's pathfinder steers
-- it. Its only collision layer is "jatz_off_road", which every tile but the road has
-- (prototypes/off-road.lua), so every path it finds stays on roads. It collides with no
-- buildings, players or other freighters. It has no burner: scripts/logistics.lua keeps its fuel,
-- burns it by the tile and refuels it at Fuel depots. Enemies can attack and destroy it; it never
-- fights back, and construction robots repair it. Destroyed, it explodes and leaves a wreck, as
-- the drivable freighter does.
-- scripts/logistics.lua creates one per delivery and removes it when the delivery is done, and
-- makes it run over enemy units it drives through and pollute a little while out.
--
-- Its cargo paint shows what it carries (scripts/freighter-paint.lua): this is defined once per
-- paint, light grey for the empty freighter, and logistics swaps a freighter for the one painted
-- for its load when it loads. Every paint draws the same sprite sheets, only tinted.
local constants = require("prototypes.constants")
local art = require("prototypes.freighter-art")
local paint = require("scripts.freighter-paint")
local remnants = require("prototypes.remnants")

-- Headlights at night: the car's light cones (the drivable freighter keeps them as they are),
-- scaled to the small freighter. The car's cones are centred 14 tiles ahead and, on many
-- freighters, lit the whole road network around a busy depot (the owner's screenshot,
-- November 7, 2026). Each cone's reach, width and distance ahead scale together, as the base
-- spidertron's cones do, so it still starts at the freighter; the two beams sit closer
-- together and shine less brightly.
local HEADLIGHT_REACH = 0.7 -- of the car's cone length and width
local HEADLIGHT_SPREAD = 0.5 -- of the car's distance between its two beams
local HEADLIGHT_INTENSITY = 0.75 -- of the car's brightness

local function headlights()
  local lights = table.deepcopy(data.raw.car.car.light)
  if not lights then
    return nil
  end
  -- A LightDefinition is one light or an array of them.
  if lights.type or lights.picture or lights.intensity then
    lights = { lights }
  end
  for _, light in ipairs(lights) do
    if light.size then
      light.size = light.size * HEADLIGHT_REACH
    end
    if light.intensity then
      light.intensity = light.intensity * HEADLIGHT_INTENSITY
    end
    local shift = light.shift
    if shift then
      light.shift = {
        (shift.x or shift[1] or 0) * HEADLIGHT_SPREAD,
        (shift.y or shift[2] or 0) * HEADLIGHT_REACH,
      }
    end
  end
  return lights
end
local HEADLIGHTS = headlights()

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
    flags = { "placeable-player", "placeable-off-grid", "not-blueprintable", "not-deconstructable" },
    max_health = 500,
    -- Dies like the drivable freighter (prototypes/freighter.lua): it explodes as the base car
    -- does and leaves the freighter's own wreck (prototypes/remnants.lua), which the game
    -- removes after 15 minutes.
    dying_explosion = data.raw.car.car.dying_explosion,
    corpse = remnants.freighter,
    -- Headlights at night (HEADLIGHTS above). Transport Drones' trucks (Factorio 1.1) lit the
    -- road ahead the same way.
    light = HEADLIGHTS,
    -- A target enemies go for, as they do the player's other vehicles and units (a unit's
    -- default, said here because deliveries rely on it).
    is_military_target = true,
    -- 0.4 tiles, well inside a one-tile road; the art is longer, but the unit turns on the spot.
    -- The engine's units overshoot a right-angle turn (about 0.3 tiles at the base speed, more
    -- when faster). With the 0.8-tile box it had, that pinned the freighter against the off-road
    -- corner across the junction, where it slid sideways before driving back at an angle (the
    -- owner's video, November 6, 2026); with this one it swerves and settles. Run-over reach
    -- doesn't follow it (IMPACT_REACH in scripts/logistics.lua).
    collision_box = { { -0.2, -0.2 }, { 0.2, 0.2 } },
    collision_mask = {
      layers = { [constants.off_road_layer] = true },
      colliding_with_tiles_only = true,
    },
    -- The middle of the body, so it is easy to point at while it turns.
    selection_box = art.box(0.8, 0.8),
    selection_priority = 60,
    -- Its dot on the map and minimap: a lighter shade of the artwork's default violet cab paint
    -- (mask-cab in assets/quinityn-freighter/factorio/freighter-animation.lua, 0.48, 0.26, 0.58,
    -- too dark on the map) rather than the game's blue for friendly entities (the owner's choice,
    -- November 13, 2026).
    friendly_map_color = { 170, 110, 210 },
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
      -- engine found no path at all for the earlier 0.8-tile box on a one-tile road.
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

-- The freighter going through a road tunnel (scripts/logistics.lua: into_tunnel): the same unit,
-- but drawn as nothing, lit by nothing and not selectable, as it stands unseen at the tunnel's mouth
-- until it comes out at the other end. (Every unit is a military target in 2.1: the game refuses
-- `is_military_target = false` for one, so enemies at the mouth can still hurt it.)
local NOTHING = {
  filename = "__core__/graphics/empty.png",
  priority = "extra-high",
  width = 1,
  height = 1,
  direction_count = 1,
  frame_count = 1,
}
local underground = drone(paint.underground, nil)
underground.flags = {
  "placeable-player",
  "placeable-off-grid",
  "not-blueprintable",
  "not-deconstructable",
  "not-on-map",
  "not-selectable-in-game",
}
underground.selection_box = nil
underground.light = nil
underground.run_animation = NOTHING
underground.attack_parameters.animation = NOTHING
drones[#drones + 1] = underground
data:extend(drones)
