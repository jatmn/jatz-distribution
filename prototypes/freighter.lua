-- SPDX-License-Identifier: LGPL-3.0-only
-- The Quinityn freighter: the base car's driving behavior with the freighter artwork.
local constants = require("prototypes.constants")
local art = require("prototypes.freighter-art")

local name = "jatz-quinityn-freighter"

local freighter = table.deepcopy(data.raw.car.car)
freighter.name = name
freighter.icon = constants.freighter_icon
freighter.icon_size = constants.icon_size
freighter.minable = { mining_time = 0.5, result = name }
freighter.animation = art.animation()
-- No gun turret, and the car's lamp sprite doesn't fit this body.
freighter.turret_animation = nil
freighter.light_animation = nil
freighter.guns = nil
-- Measured from the rendered sprites at the artwork's scale (about 4.6 tiles long and 1.5 wide,
-- centred on the pivot), then scaled with the sprites: about 3.4 by 1.1 tiles in game.
freighter.collision_box = art.box(0.75, 2.25)
freighter.selection_box = art.box(0.8, 2.3)

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
    -- Freighters stack to 10; a request depot's freighter slot holds 100 (scripts/logistics.lua).
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
