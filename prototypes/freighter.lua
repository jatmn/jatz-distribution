-- SPDX-License-Identifier: LGPL-3.0-only
-- The Quinityn freighter: the base car's driving behavior with the freighter artwork.
-- The item is what request depots send out as delivering freighters. Players can place it as a
-- car only with the "jatz-freighter-drivable" startup setting (off by default); otherwise the car
-- stays defined but hidden, so cars already placed in a save keep driving and mine back to items.
local constants = require("prototypes.constants")
local art = require("prototypes.freighter-art")
local remnants = require("prototypes.remnants")

local name = "jatz-quinityn-freighter"
local drivable = settings.startup["jatz-freighter-drivable"].value

local freighter = table.deepcopy(data.raw.car.car)
freighter.name = name
freighter.icon = constants.freighter_icon
freighter.icon_size = constants.icon_size
freighter.minable = { mining_time = 0.5, result = name }
freighter.animation = art.animation()
-- Destroyed, it leaves its own wreck rather than the car's (prototypes/remnants.lua).
freighter.corpse = remnants.freighter
-- No gun turret, and the car's lamp sprite doesn't fit this body.
freighter.turret_animation = nil
freighter.light_animation = nil
freighter.guns = nil
-- Measured from the rendered sprites at the artwork's scale (about 4.6 tiles long and 1.5 wide,
-- centred on the pivot), then scaled with the sprites: about 2.7 by 0.9 tiles in game.
freighter.collision_box = art.box(0.75, 2.25)
freighter.selection_box = art.box(0.8, 2.3)
freighter.hidden = not drivable

-- The freighter's parts and the fuel its full tank is filled with.
local function freighter_ingredients(fuel, amount)
  return {
    { type = "item", name = "engine-unit", amount = 2 },
    { type = "item", name = "steel-plate", amount = 5 },
    { type = "item", name = "iron-gear-wheel", amount = 5 },
    { type = "item", name = "electronic-circuit", amount = 2 },
    { type = "item", name = fuel, amount = amount },
  }
end

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
    -- Unlocked by research (prototypes/technologies.lua). New freighters come with a full tank
    -- (scripts/logistics.lua), so the recipe takes its fuel: 5 coal, the default 20 MJ tank.
    type = "recipe",
    name = name,
    enabled = false,
    energy_required = 4,
    ingredients = freighter_ingredients("coal", 5),
    results = { { type = "item", name = name, amount = 1 } },
  },
})

-- With Space Age, the same freighter fuelled with 10 carbon (2 MJ each) instead, for planets
-- without coal. Recycling a freighter gives back the coal recipe's ingredients: the recycler names
-- its recipe after the product, so only one of the two may make it.
if mods["space-age"] and data.raw.item.carbon then
  data:extend({
    {
      type = "recipe",
      name = constants.freighter_carbon_recipe,
      localised_name = { "recipe-name." .. constants.freighter_carbon_recipe },
      icons = {
        { icon = constants.freighter_icon, icon_size = constants.icon_size },
        { icon = "__space-age__/graphics/icons/carbon.png", icon_size = 64, scale = 0.25, shift = { -8, -8 } },
      },
      subgroup = constants.subgroup,
      order = "c[freighter]-b[carbon]",
      enabled = false,
      auto_recycle = false,
      energy_required = 4,
      ingredients = freighter_ingredients("carbon", 10),
      results = { { type = "item", name = name, amount = 1 } },
    },
  })
end
