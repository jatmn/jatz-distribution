-- SPDX-License-Identifier: LGPL-3.0-only
-- What a destroyed depot or freighter leaves behind: its own wreck, as the game's machines leave
-- theirs, removed after 15 minutes like the base game's (assets/depots/remnants/, wrecked from
-- the depots' and the freighter's own models by assets/depots/tools/build_remnants.py; the
-- freighter's is in assets/quinityn-freighter/remnants/).
--
-- Five wrecks serve the seven depots: the Provider and Request depots share the cargo depot's,
-- the Liquid Provider and Liquid Request depots the liquid depot's. Each depot still gets its own
-- corpse, drawing the shared wreck in its own paint, so a red Provider leaves a red wreck and a
-- blue Request a blue one, as the game's remnants keep a vehicle's or turret's colour.
-- The sheets are one row of frames in the order the game turns an entity (north, then
-- clockwise): a corpse takes the direction of what died, and a depot shown half a turn from its
-- artwork (prototypes/orientation.lua) has its wreck's sheet turned the same way when packaged.
local constants = require("prototypes.constants")
local definitions = require("prototypes.depot-definitions")
local freighter_art = require("prototypes.freighter-art")

local remnants = {}

-- Which wreck each depot leaves.
local WRECKS = {
  { "provider", "cargo" },
  { "request", "cargo" },
  { "buffer", "buffer" },
  { "liquid-provider", "liquid" },
  { "liquid-request", "liquid" },
  { "liquid-buffer", "liquid-buffer" },
  { "fuel", "fuel" },
}

-- The wreck's layers: shadow, the untinted base, then the three paint masks in `palette`
-- ({ role, clamps, housing }), in the depots' drawing order.
-- `sheets` is the folder, relative to the mod root; `count` its frames, one per direction.
local function animation(sheets, count, scale, palette, projection)
  local prefix = "__" .. constants.mod_name .. "__/" .. sheets
  local function layer(name, tint, shadow)
    return {
      filename = prefix .. name .. ".png",
      width = 512,
      height = 512,
      line_length = count,
      direction_count = count,
      scale = scale,
      shift = { 0, 0 },
      tint = tint,
      draw_as_shadow = shadow or false,
      -- The freighter's frames are equal turns of the model under a fixed camera, as its own.
      apply_projection = projection,
    }
  end
  return {
    layers = {
      layer("shadow", nil, true),
      layer("base"),
      layer("mask-cab", palette.role),
      layer("mask-trim", palette.clamps),
      layer("mask-cargo", palette.housing),
    },
  }
end

local function corpse(name, icon, size, subgroup, art)
  return {
    type = "corpse",
    name = name,
    icon = icon,
    icon_size = constants.icon_size,
    hidden_in_factoriopedia = true,
    flags = { "placeable-neutral", "building-direction-8-way", "not-on-map" },
    subgroup = subgroup,
    selection_box = { { -size / 2, -size / 2 }, { size / 2, size / 2 } },
    tile_width = size,
    tile_height = size,
    selectable_in_game = false,
    time_before_removed = 60 * 60 * 15,
    expires = false,
    final_render_layer = "remnants",
    remove_on_tile_placement = false,
    animation = art,
  }
end

-- The corpse a depot of `role` leaves.
function remnants.depot(role)
  return "jatz-" .. role .. "-depot-remnants"
end

-- The corpse the freighter leaves, driving itself or driven.
remnants.freighter = "jatz-freighter-remnants"

local prototypes = {}
for _, entry in ipairs(WRECKS) do
  local role, wreck = entry[1], entry[2]
  local definition = definitions[role][3]
  prototypes[#prototypes + 1] = corpse(
    remnants.depot(role),
    string.format(constants.depot_icon, role),
    definition.size,
    "storage-remnants",
    animation(string.format(constants.depot_remnant_sheets, wreck), 4, definition.scale, definition.palette, true)
  )
end
-- The wreck is drawn at the freighter's size, in the drivable freighter's paint (the artwork's
-- own colours), from the same helper as the freighter itself: its layers are shadow, base, then
-- the cab, trim and cargo masks.
local drawn = freighter_art.animation().layers
prototypes[#prototypes + 1] = corpse(
  remnants.freighter,
  constants.freighter_icon,
  3,
  "transport-remnants",
  animation(
    constants.freighter_remnant_sheets,
    8,
    drawn[1].scale,
    { role = drawn[3].tint, clamps = drawn[4].tint, housing = drawn[5].tint },
    false
  )
)
data:extend(prototypes)

return remnants
