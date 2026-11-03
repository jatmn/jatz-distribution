-- SPDX-License-Identifier: LGPL-3.0-only
-- The Quinityn freighter: the base car's driving behavior with the freighter artwork.
local constants = require("prototypes.constants")
local make_animation = require("assets.quinityn-freighter.factorio.freighter-animation")

local name = "jatz-quinityn-freighter"

local freighter = table.deepcopy(data.raw.car.car)
freighter.name = name
freighter.icon = constants.freighter_icon
freighter.icon_size = constants.icon_size
freighter.minable = { mining_time = 0.5, result = name }
freighter.animation = make_animation(constants.mod_name, nil, constants.freighter_sheets)
-- No gun turret, and the car's lamp sprite doesn't fit this body.
freighter.turret_animation = nil
freighter.light_animation = nil
freighter.guns = nil
-- Measured from the rendered sprites: about 4.6 tiles long and 1.5 wide, centered on the pivot.
freighter.collision_box = { { -0.75, -2.25 }, { 0.75, 2.25 } }
freighter.selection_box = { { -0.8, -2.3 }, { 0.8, 2.3 } }

data:extend({
  freighter,
  {
    type = "item-with-entity-data",
    name = name,
    icon = constants.freighter_icon,
    icon_size = constants.icon_size,
    subgroup = constants.subgroup,
    -- After the seven depots ("b[depot]-..."): last in our row.
    order = "c[freighter]",
    place_result = name,
    stack_size = 1,
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
