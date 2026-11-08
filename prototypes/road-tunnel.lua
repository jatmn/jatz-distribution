-- SPDX-License-Identifier: LGPL-3.0-only
-- Road tunnel portals: freighters go under whatever stands between two of them, as items go under
-- buildings on underground belts (scripts/tunnels.lua, scripts/logistics.lua). A portal stands at
-- the end of a road, its mouth to the road: the tile in front of it is where freighters drive in
-- and come out, and must be road.
--
-- It is a pipe-to-ground whose one connection is an underground one in its own connection category
-- (`jatz-road-tunnel`): the game pairs two portals facing each other within reach, shows the reach
-- while placing, and connects no pipe, nor any other mod's, to them. Nothing ever flows through. It
-- collides with road like every other building (pipes-to-ground are otherwise allowed on road,
-- prototypes/off-road.lua), so it can't stand on road, nor road be laid under it.
-- Its art is our own: a 1x1 model in the liquid depots' grey and bronze finish
-- (assets/depots/road-tunnel/1/, built and rendered with the depots), drawn with its default
-- colours (the packaged preview layer) and its ground shadow.
local collision_mask_util = require("collision-mask-util")
local constants = require("prototypes.constants")
local sounds = require("__base__.prototypes.entity.sounds")

local name = constants.road_tunnel
local sheets = "__" .. constants.mod_name .. "__/" .. string.format(constants.depot_sheets, "road-tunnel", 1)
-- The rendered frames: 512 px covering 2.5 tiles (assets/depots/road-tunnel/1/asset.json).
local SCALE = 0.15625
local DIRECTIONS = { "north", "east", "south", "west" }
local icon = "__" .. constants.mod_name .. "__/assets/depots/icons/road-tunnel.png"

local pictures = {}
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
  pictures[direction] = { layers = { layer("shadow", true), layer("preview", false) } }
end

local collision_mask = collision_mask_util.get_default_mask("pipe-to-ground")
collision_mask.layers[constants.road_layer] = true

data:extend({
  {
    type = "pipe-to-ground",
    name = name,
    icon = icon,
    icon_size = constants.icon_size,
    flags = { "placeable-neutral", "player-creation" },
    minable = { mining_time = 0.5, result = name },
    max_health = 400,
    corpse = "pipe-to-ground-remnants",
    dying_explosion = "pipe-to-ground-explosion",
    resistances = { { type = "fire", percent = 80 }, { type = "impact", percent = 60 } },
    collision_box = { { -0.35, -0.35 }, { 0.35, 0.35 } },
    selection_box = { { -0.5, -0.5 }, { 0.5, 0.5 } },
    collision_mask = collision_mask,
    fluid_box = {
      volume = 1,
      hide_connection_info = true,
      pipe_connections = {
        {
          -- The tunnel runs back from the mouth (north while unrotated: its mouth faces north).
          connection_type = "underground",
          direction = defines.direction.south,
          position = { 0, 0 },
          max_underground_distance = constants.tunnel_reach,
          connection_category = name,
          hide_connection_info = true,
        },
      },
    },
    -- It holds no fluid, so there is nothing to show while holding pipes.
    show_fluid_visualization_when_in_cursor = false,
    impact_category = "metal",
    open_sound = sounds.metal_small_open,
    close_sound = sounds.metal_small_close,
    pictures = pictures,
  },
  {
    type = "item",
    name = name,
    icon = icon,
    icon_size = constants.icon_size,
    subgroup = constants.subgroup,
    -- After the road ("d[road]"), before the road network monitor ("e[road-monitor]").
    order = "d[road]-b[tunnel]",
    place_result = name,
    stack_size = 50,
  },
  {
    -- Two portals, one for each end, as underground belts come in pairs; unlocked by research
    -- (prototypes/technologies.lua).
    type = "recipe",
    name = name,
    enabled = false,
    energy_required = 10,
    ingredients = {
      { type = "item", name = "stone-brick", amount = 20 },
      { type = "item", name = "steel-plate", amount = 10 },
      { type = "item", name = "iron-gear-wheel", amount = 10 },
    },
    results = { { type = "item", name = name, amount = 2 } },
  },
})
