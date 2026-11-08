-- SPDX-License-Identifier: LGPL-3.0-only
-- The seven 3x3 depots. Cargo depots are rotatable containers; liquid depots are storage tanks.
-- The Fuel depot is both: a container for fuel items, with a hidden storage tank under it for
-- liquid fuel (FUEL_TANK below), since no entity type has an item inventory and a fluid box
-- of its own. Each draws its loading zone marking on the ground beside it, south when placed
-- unrotated (prototypes/orientation.lua). Deliveries and refuelling are in scripts/logistics.lua;
-- liquid request and buffer depots get an invisible truck chest for their freighters
-- (prototypes/truck-chest.lua).
local util = require("util")
local constants = require("prototypes.constants")
local definitions = require("prototypes.depot-definitions")
local orientation = require("prototypes.orientation")
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
-- What each depot is made of, in 5 seconds: item depots from a steel chest (their 48 slots) and the
-- belt their artwork shows (each belt in place of a gear), liquid depots from a storage tank, the
-- ones fetching fluid with pumps; the Fuel depot from a steel chest, a belt and an engine unit, not
-- a pump: pumps come with Fluid handling, which the Freight system doesn't need. Everything here is
-- craftable once the depot is researched (prototypes/technologies.lua).
local INGREDIENTS = {
  provider = {
    { "steel-chest", 1 },
    { "transport-belt", 1 },
    { "iron-gear-wheel", 6 },
    { "iron-plate", 10 },
    { "stone-brick", 4 },
  },
  request = {
    { "steel-chest", 1 },
    { "transport-belt", 1 },
    { "iron-gear-wheel", 6 },
    { "electronic-circuit", 4 },
    { "stone-brick", 4 },
  },
  buffer = {
    { "steel-chest", 1 },
    { "transport-belt", 2 },
    { "iron-gear-wheel", 6 },
    { "electronic-circuit", 4 },
    { "stone-brick", 4 },
  },
  ["liquid-provider"] = { { "storage-tank", 1 }, { "pipe", 1 }, { "iron-gear-wheel", 6 }, { "stone-brick", 4 } },
  ["liquid-request"] = {
    { "storage-tank", 1 },
    { "pipe", 1 },
    { "pump", 1 },
    { "electronic-circuit", 4 },
    { "stone-brick", 4 },
  },
  ["liquid-buffer"] = {
    { "storage-tank", 1 },
    { "pipe", 4 },
    { "pump", 2 },
    { "electronic-circuit", 8 },
    { "stone-brick", 4 },
  },
  fuel = {
    { "steel-chest", 1 },
    { "transport-belt", 1 },
    { "engine-unit", 1 },
    { "pipe", 1 },
    { "iron-gear-wheel", 5 },
    { "stone-brick", 4 },
  },
}
local function items(list)
  local ingredients = {}
  for index, entry in ipairs(list) do
    ingredients[index] = { type = "item", name = entry[1], amount = entry[2] }
  end
  return ingredients
end

-- Every depot takes red and green circuit wires, whichever way it faces (containers with four
-- directions need one connector per direction; the steel chest's single one can't be used). Item
-- depots read their contents and tanks their fluid as usual; delivery depots also have an
-- enable/disable condition in their panel, which scripts/logistics.lua applies
-- (scripts/depot-circuit.lua).
-- Liquid depots have it where a 3x3 assembling machine does, on the skid's front corner. Item
-- depots (and the Fuel depot) would have it on the edge of their loading opening there, so theirs
-- sits higher and further out, on the right-hand pillar below its painted band, which every one of
-- their four views has in the same place (checked on the sprite sheets). Lowering the depots
-- (assets/depots/README.md) brought the band 6 frame pixels down, so the connector moved 3 pixels
-- down with it, keeping the gap it had below the band; it stays on solid pillar in every view.
local CIRCUIT_CONNECTOR = {
  variation = 18,
  main_offset = util.by_pixel(24, 25),
  shadow_offset = util.by_pixel(35, 31),
  show_shadow = true,
}
local PILLAR_CONNECTOR = {
  variation = 18,
  main_offset = util.by_pixel(37, 31),
  shadow_offset = util.by_pixel(48, 37),
  show_shadow = true,
}
-- Tank sizes players can set (settings.lua); every other depot with ports holds 25,000.
local CAPACITY_SETTINGS = {
  ["liquid-provider"] = "jatz-liquid-provider-depot-capacity",
  ["liquid-buffer"] = "jatz-liquid-buffer-depot-capacity",
}

-- A depot's storage tank: its ports, drawing their connectors, and the given artwork.
local function tank(role, definition, artwork)
  local entity = table.deepcopy(data.raw["storage-tank"]["storage-tank"])
  entity.two_direction_only = false
  entity.fluid_box = {
    volume = CAPACITY_SETTINGS[role] and settings.startup[CAPACITY_SETTINGS[role]].value or 25000,
    pipe_connections = orientation.ports(role, definition.ports),
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
  return entity
end

-- Every depot's 3x3 footprint, and no circuit connections or fast replacing.
local function footprint(entity)
  entity.circuit_connector = nil
  entity.fast_replaceable_group = nil
  entity.tile_width = SIZE
  entity.tile_height = SIZE
  entity.selection_box = { { -SIZE / 2, -SIZE / 2 }, { SIZE / 2, SIZE / 2 } }
  entity.collision_box = { { -SIZE / 2 + 0.2, -SIZE / 2 + 0.2 }, { SIZE / 2 - 0.2, SIZE / 2 - 0.2 } }
end

for index, role in ipairs(ORDER) do
  local definition = definitions[role][SIZE]
  local name = "jatz-" .. role .. "-depot"
  local artwork = orientation.pictures(role, pictures(constants.mod_name, role, SIZE, nil, constants.depot_sheets))
  local icon = string.format(constants.depot_icon, role)
  local entity
  if #definition.ports == 0 or role == "fuel" then
    entity = table.deepcopy(data.raw.container["steel-chest"])
    entity.direction_count = 4
    entity.picture = artwork
    entity.inventory_size = 48
  else
    entity = tank(role, definition, artwork)
  end
  entity.name = name
  entity.icons = nil
  entity.icon = icon
  entity.icon_size = constants.icon_size
  entity.minable = { mining_time = 0.3, result = name }
  footprint(entity)
  -- The depots take wires (footprint() leaves the hidden fuel tank under a Fuel depot without).
  local connector = orientation.half_turn[role] and PILLAR_CONNECTOR or CIRCUIT_CONNECTOR
  entity.circuit_connector = circuit_connector_definitions.create_vector(
    universal_connector_template,
    { connector, connector, connector, connector }
  )
  entity.circuit_wire_max_distance = default_circuit_wire_max_distance
  -- Ground marking on the loading side; it rotates, ghosts and disappears with the depot.
  entity.integration_patch = orientation.loading_zone({ filename = constants.loading_zone, size = 64, scale = 0.5 })
  entity.integration_patch_render_layer = orientation.loading_zone_render_layer

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
      -- Unlocked by research (prototypes/technologies.lua).
      type = "recipe",
      name = name,
      enabled = false,
      energy_required = 5,
      ingredients = items(INGREDIENTS[role]),
      results = { { type = "item", name = name, amount = 1 } },
    },
  })
end

-- The Fuel depot's liquid fuel: a storage tank with its pipe port and connectors, drawing nothing
-- else, under the depot (which draws the building). scripts/logistics.lua makes one at each Fuel
-- depot, turns it with the depot and removes it with the depot. It can't be seen, selected,
-- mined, built or blueprinted, and collides with nothing; pipes connect to it as to the depot.
local fuel_tank = tank("fuel", definitions.fuel[SIZE], util.empty_sprite())
footprint(fuel_tank)
fuel_tank.name = constants.fuel_tank
fuel_tank.icons = nil
fuel_tank.icon = string.format(constants.depot_icon, "fuel")
fuel_tank.icon_size = constants.icon_size
fuel_tank.hidden = true
fuel_tank.flags = {
  "player-creation",
  "not-on-map",
  "not-blueprintable",
  "not-deconstructable",
  "not-repairable",
  "not-flammable",
  "hide-alt-info",
  "no-copy-paste",
}
fuel_tank.selectable_in_game = false
fuel_tank.allow_copy_paste = false
fuel_tank.minable = nil
fuel_tank.collision_mask = { layers = {} }
fuel_tank.water_reflection = nil
fuel_tank.corpse = nil
fuel_tank.dying_explosion = nil
fuel_tank.next_upgrade = nil
data:extend({ fuel_tank })
