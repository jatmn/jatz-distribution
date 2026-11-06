-- SPDX-License-Identifier: LGPL-3.0-only
-- The Quinityn freighter: the base car's driving behavior with the freighter artwork.
-- The item is what request depots send out as delivering freighters. Players can place it as a
-- car only with the "jatz-freighter-drivable" startup setting (off by default); otherwise the car
-- stays defined but hidden, so cars already placed in a save keep driving and mine back to items.
local constants = require("prototypes.constants")
local art = require("prototypes.freighter-art")

local name = "jatz-quinityn-freighter"
local drivable = settings.startup["jatz-freighter-drivable"].value

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
-- centred on the pivot), then scaled with the sprites: about 2.7 by 0.9 tiles in game.
freighter.collision_box = art.box(0.75, 2.25)
freighter.selection_box = art.box(0.8, 2.3)
freighter.hidden = not drivable

data:extend({
  freighter,
  {
    type = "item-with-entity-data",
    name = name,
    -- Named after the car even when it can't place it (an item with no place_result would
    -- otherwise look for its own item-name).
    localised_name = { "entity-name." .. name },
    localised_description = { "entity-description." .. name },
    icon = constants.freighter_icon,
    icon_size = constants.icon_size,
    subgroup = constants.subgroup,
    -- After the seven depots ("b[depot]-..."): last in our row.
    order = "c[freighter]",
    place_result = drivable and name or nil,
    -- Freighters stack to 10; a request depot's freighter slot holds 100 (scripts/logistics.lua).
    stack_size = 10,
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
