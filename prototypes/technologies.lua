-- SPDX-License-Identifier: LGPL-3.0-only
-- Research, laid out as Transport Drones does (its data/technologies/, values only): one
-- technology unlocks every recipe, then freighter speed (four levels and an infinite one) and
-- freighter capacity (five levels). scripts/research.lua applies the levels at runtime.
local constants = require("prototypes.constants")
local research = require("scripts.research")

local RED = { "automation-science-pack", 1 }
local GREEN = { "logistic-science-pack", 1 }
local BLUE = { "chemical-science-pack", 1 }
local PURPLE = { "production-science-pack", 1 }
local YELLOW = { "utility-science-pack", 1 }
local WHITE = { "space-science-pack", 1 }
-- The science packs of each upgrade level.
local LADDER = {
  { RED, GREEN },
  { RED, GREEN, BLUE },
  { RED, GREEN, BLUE, PURPLE },
  { RED, GREEN, BLUE, PURPLE, YELLOW },
  { RED, GREEN, BLUE, PURPLE, YELLOW },
}

-- Item order in our crafting row (prototypes/placement.lua): the depots, the freighter, road.
local RECIPES = {
  "jatz-provider-depot",
  "jatz-request-depot",
  "jatz-buffer-depot",
  "jatz-liquid-provider-depot",
  "jatz-liquid-request-depot",
  "jatz-liquid-buffer-depot",
  "jatz-fuel-depot",
  "jatz-quinityn-freighter",
  constants.road,
}

local function icons(overlay)
  local layers = { { icon = constants.freighter_icon, icon_size = constants.icon_size, scale = 2 } }
  if overlay then
    layers[2] = {
      icon = "__core__/graphics/icons/technology/constants/" .. overlay .. ".png",
      icon_size = 128,
      scale = 0.5,
      shift = { 50, 50 },
      floating = true,
    }
  end
  return layers
end

-- A scripted effect: the technology GUI shows its description under the freighter's icon.
local function nothing(description)
  return {
    type = "nothing",
    effect_description = description,
    icon = constants.freighter_icon,
    icon_size = constants.icon_size,
  }
end

local unlocks = {}
for _, recipe in ipairs(RECIPES) do
  unlocks[#unlocks + 1] = { type = "unlock-recipe", recipe = recipe }
end

local technologies = {
  {
    type = "technology",
    name = research.system,
    icons = icons(nil),
    effects = unlocks,
    prerequisites = { "engine" },
    unit = { count = 200, ingredients = LADDER[1], time = 30 },
    order = "j[jatz]-a",
  },
}

local function upgrade(name, level, effect, overlay)
  return {
    type = "technology",
    name = name .. "-" .. level,
    icons = icons(overlay),
    upgrade = true,
    effects = { effect },
    prerequisites = { level > 1 and name .. "-" .. (level - 1) or research.system },
    order = "j[jatz]-" .. name,
  }
end

local speed_effect =
  nothing({ "modifier-description.jatz-freighter-speed", tostring(math.floor(research.speed_bonus * 100 + 0.5)) })
for level = 1, research.speed_levels do
  local technology = upgrade(research.speed, level, speed_effect, "constant-movement-speed")
  technology.unit = { count = level * 200, ingredients = LADDER[level], time = 30 }
  technologies[#technologies + 1] = technology
end
-- Then one level after another for ever, each costing twice the last.
local infinite_level = research.speed_levels + 1
local infinite = upgrade(research.speed, infinite_level, speed_effect, "constant-movement-speed")
infinite.max_level = "infinite"
infinite.unit = {
  count_formula = string.format("2^(L-%d)*500", infinite_level),
  ingredients = { RED, GREEN, BLUE, PURPLE, YELLOW, WHITE },
  time = 60,
}
technologies[#technologies + 1] = infinite

local capacity_effect = nothing({
  "modifier-description.jatz-freighter-capacity",
  tostring(research.stacks_per_level),
  tostring(research.fluid_per_level),
})
for level = 1, research.capacity_levels do
  local technology = upgrade(research.capacity, level, capacity_effect, "constant-capacity")
  technology.unit = { count = level * 200, ingredients = LADDER[level], time = 30 }
  technologies[#technologies + 1] = technology
end

data:extend(technologies)
