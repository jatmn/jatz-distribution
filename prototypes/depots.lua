-- SPDX-License-Identifier: LGPL-3.0-only
-- The seven 3x3 depots. Cargo depots are rotatable containers; depots with pipe ports
-- (Fuel and the liquid depots) are storage tanks. Dispatch and transfer come later.
local util = require("util")
local constants = require("prototypes.constants")
local definitions = require("prototypes.depot-definitions")
local pictures = require("assets.depots.factorio.depot-pictures")
local pipe_pictures = require("assets.depots.factorio.depot-pipe-pictures")

local SIZE = 3
-- Sort order in the crafting menu: dry cargo first, then fuel, then fluids.
local ORDER = {
  "provider",
  "request",
  "buffer",
  "fuel",
  "liquid-provider",
  "liquid-request",
  "liquid-buffer",
}

local function tinted_icon(icon, color)
  return { { icon = icon, icon_size = 64, tint = { color[1], color[2], color[3], 1 } } }
end

for index, role in ipairs(ORDER) do
  local definition = definitions[role][SIZE]
  local name = "jatz-" .. role .. "-depot"
  local artwork = pictures(constants.mod_name, role, SIZE, nil, constants.depot_sheets)
  local entity, icon
  if #definition.ports == 0 then
    entity = table.deepcopy(data.raw.container["steel-chest"])
    entity.direction_count = 4
    entity.picture = artwork
    entity.inventory_size = 48
    icon = "__base__/graphics/icons/steel-chest.png"
  else
    entity = table.deepcopy(data.raw["storage-tank"]["storage-tank"])
    entity.two_direction_only = false
    entity.fluid_box = {
      volume = 25000,
      pipe_connections = table.deepcopy(definition.ports),
      pipe_covers = pipecoverspictures(),
      pipe_picture = pipe_pictures(constants.mod_name, constants.connector_sheets),
      -- North-side connectors draw behind the building.
      secondary_draw_orders = { north = -1 },
    }
    entity.pictures = {
      picture = artwork,
      fluid_background = util.empty_sprite(),
      window_background = util.empty_sprite(),
      flow_sprite = util.empty_sprite(),
      gas_flow = util.empty_sprite(),
    }
    entity.window_bounding_box = { { 0, 0 }, { 0, 0 } }
    entity.show_fluid_icon = true
    icon = "__base__/graphics/icons/storage-tank.png"
  end
  entity.name = name
  entity.icon = nil
  entity.icons = tinted_icon(icon, definition.palette.role)
  entity.minable = { mining_time = 0.3, result = name }
  entity.circuit_connector = nil
  entity.fast_replaceable_group = nil
  entity.tile_width = SIZE
  entity.tile_height = SIZE
  entity.selection_box = { { -SIZE / 2, -SIZE / 2 }, { SIZE / 2, SIZE / 2 } }
  entity.collision_box = { { -SIZE / 2 + 0.2, -SIZE / 2 + 0.2 }, { SIZE / 2 - 0.2, SIZE / 2 - 0.2 } }

  data:extend({
    entity,
    {
      type = "item",
      name = name,
      icons = tinted_icon(icon, definition.palette.role),
      subgroup = constants.subgroup,
      order = string.format("b[depot]-%d[%s]", index, role),
      place_result = name,
      stack_size = 10,
    },
    {
      -- Free while the mod is in development.
      type = "recipe",
      name = name,
      enabled = true,
      energy_required = 0.5,
      ingredients = {},
      results = { { type = "item", name = name, amount = 1 } },
    },
  })
end
