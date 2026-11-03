-- SPDX-License-Identifier: LGPL-3.0-only
-- The seven 3x3 depots. Cargo depots are rotatable containers; depots with pipe ports
-- (Fuel and the liquid depots) are storage tanks. Dispatch and transfer come later.
local util = require("util")
local constants = require("prototypes.constants")
local definitions = require("prototypes.depot-definitions")
local pictures = require("assets.depots.factorio.depot-pictures")
local pipe_pictures = require("assets.depots.factorio.depot-pipe-pictures")

local SIZE = 3
-- Order within our row in the crafting menu and Factoriopedia: dry cargo, then fluids, then
-- fuel. The freighter comes last (prototypes/freighter.lua).
local ORDER = {
  "provider",
  "request",
  "buffer",
  "liquid-provider",
  "liquid-request",
  "liquid-buffer",
  "fuel",
}

for index, role in ipairs(ORDER) do
  local definition = definitions[role][SIZE]
  local name = "jatz-" .. role .. "-depot"
  local artwork = pictures(constants.mod_name, role, SIZE, nil, constants.depot_sheets)
  local icon = string.format(constants.depot_icon, role)
  local entity
  if #definition.ports == 0 then
    entity = table.deepcopy(data.raw.container["steel-chest"])
    entity.direction_count = 4
    entity.picture = artwork
    entity.inventory_size = 48
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
  end
  entity.name = name
  entity.icons = nil
  entity.icon = icon
  entity.icon_size = constants.icon_size
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
      icon = icon,
      icon_size = constants.icon_size,
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
