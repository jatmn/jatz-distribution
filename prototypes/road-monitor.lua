-- SPDX-License-Identifier: LGPL-3.0-only
-- The road network monitor: a constant combinator, built beside road, that puts on its red
-- and green wires what the provider and buffer depots on that road network hold, like a roboport
-- reading its logistic network's contents. scripts/road-monitor.lua sets its signals once a
-- second; players can't edit them.
-- Its art is our own: a 1x1 model in the liquid depots' grey and bronze finish
-- (assets/depots/road-monitor/1/, built and rendered with the depots), drawn with its default
-- colours (the packaged preview layer) and its ground shadow. Its wires meet its two terminal
-- posts, and the activity light (the base game's glow sprite) sits on its status lens, at the
-- points the model gives (prototypes/road-monitor-points.lua). Its icon is the model too, with
-- the road icon in the corner.
local util = require("util")
local constants = require("prototypes.constants")
local points = require("prototypes.road-monitor-points")

local name = constants.road_monitor
local sheets = "__" .. constants.mod_name .. "__/" .. string.format(constants.depot_sheets, "road-monitor", 1)
-- The rendered frames: 512 px covering 2.5 tiles (assets/depots/road-monitor/1/asset.json).
local SCALE = 0.15625
local DIRECTIONS = { "north", "east", "south", "west" }
local icons = {
  {
    icon = "__" .. constants.mod_name .. "__/assets/depots/icons/road-monitor.png",
    icon_size = constants.icon_size,
  },
  {
    icon = "__" .. constants.mod_name .. "__/" .. constants.road_art .. "pslag_icon.png",
    icon_size = 32,
    scale = 0.5,
    shift = { 8, 8 },
  },
}

local function pixels(point)
  return { point[1] * 32, point[2] * 32 }
end

local sprites, leds, led_offsets, wire_points = {}, {}, {}, {}
for index, direction in ipairs(DIRECTIONS) do
  local function layer(sheet, shadow)
    return {
      filename = sheets .. sheet .. ".png",
      width = 512,
      height = 512,
      x = (index - 1) * 512,
      y = 0,
      scale = SCALE,
      draw_as_shadow = shadow,
    }
  end
  sprites[direction] = { layers = { layer("shadow", true), layer("preview", false) } }
  -- The base game's activity light glow for this direction, on our lens.
  local led = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"].activity_led_sprites[direction])
  for _, sprite in ipairs(led.layers or { led }) do
    sprite.shift = util.by_pixel(table.unpack(pixels(points.lens[index])))
  end
  leds[direction] = led
  led_offsets[index] = points.lens[index]
  wire_points[index] = {
    wire = { red = points.wire[index].red, green = points.wire[index].green },
    shadow = { red = points.wire_shadow[index].red, green = points.wire_shadow[index].green },
  }
end

local entity = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
entity.name = name
entity.icon = nil
entity.icons = icons
entity.minable = { mining_time = 0.1, result = name }
entity.sprites = sprites
entity.activity_led_sprites = leds
entity.activity_led_light_offsets = led_offsets
entity.circuit_wire_connection_points = wire_points
-- Not swapped for a constant combinator by building over it, nor upgraded into one.
entity.fast_replaceable_group = nil
entity.next_upgrade = nil

data:extend({
  entity,
  {
    type = "item",
    name = name,
    icons = icons,
    subgroup = constants.subgroup,
    -- After the road ("d[road]"): last in our row.
    order = "e[road-monitor]",
    place_result = name,
    stack_size = 50,
  },
  {
    -- Free while the mod is in development; unlocked by research (prototypes/technologies.lua).
    type = "recipe",
    name = name,
    enabled = false,
    energy_required = 0.5,
    ingredients = {},
    results = { { type = "item", name = name, amount = 1 } },
  },
})
