-- SPDX-License-Identifier: LGPL-3.0-only
-- Research, laid out after Transport Drones' tech tree (its data/technologies/, values only): the
-- freight system unlocks the item depots, the fuel depot, the freighter and road; liquid freight
-- expands it with the liquid depots; the road network monitor research, after it and the circuit
-- network, unlocks the monitor (Transport Drones' depot circuits research); road tunnels, after it
-- and underground belts (logistics), unlock the tunnel portals. Upgrades: freighter
-- speed (four levels and an infinite one),
-- item capacity (ten levels) and, after liquid freight, fluid capacity (ten levels).
-- scripts/research.lua applies the levels at runtime.
local constants = require("prototypes.constants")
local research = require("scripts.research")

local RED = { "automation-science-pack", 1 }
local GREEN = { "logistic-science-pack", 1 }
local BLUE = { "chemical-science-pack", 1 }
local PURPLE = { "production-science-pack", 1 }
local YELLOW = { "utility-science-pack", 1 }
local WHITE = { "space-science-pack", 1 }
-- The science packs of each upgrade level. A level past the last rung keeps that rung's packs;
-- the pack count is still the level times 200. Item and fluid capacity have ten levels, so 6
-- through 10 take the same packs as level 5.
local LADDER = {
  { RED, GREEN },
  { RED, GREEN, BLUE },
  { RED, GREEN, BLUE, PURPLE },
  { RED, GREEN, BLUE, PURPLE, YELLOW },
  { RED, GREEN, BLUE, PURPLE, YELLOW },
}

-- In our crafting row's order (prototypes/placement.lua).
local SYSTEM_RECIPES = {
  "jatz-provider-depot",
  "jatz-request-depot",
  "jatz-buffer-depot",
  "jatz-fuel-depot",
  "jatz-quinityn-freighter",
  constants.road,
}
-- With Space Age, the freighter fuelled with carbon (prototypes/freighter.lua).
if data.raw.recipe[constants.freighter_carbon_recipe] then
  table.insert(SYSTEM_RECIPES, 6, constants.freighter_carbon_recipe)
end
local LIQUID_RECIPES = {
  "jatz-liquid-provider-depot",
  "jatz-liquid-request-depot",
  "jatz-liquid-buffer-depot",
}
local MONITOR_RECIPES = { constants.road_monitor }
local TUNNEL_RECIPES = { constants.road_tunnel }

-- A 256 px technology icon (tools/make_icons.py), with the game's "constant" badge for upgrades
-- and, for fluid capacity, the game's water icon in the top left corner, so it reads as the
-- freighter carrying fluid rather than a liquid depot holding more.
local FREIGHTER = constants.freighter_technology_icon
local LIQUID = constants.liquid_technology_icon
local MONITOR = constants.monitor_technology_icon
local TUNNEL = constants.tunnel_technology_icon
local FLUID_BADGE = "__base__/graphics/icons/fluid/water.png"
local function icons(icon, overlay, badge)
  local layers = { { icon = icon, icon_size = constants.technology_icon_size } }
  if badge then
    layers[#layers + 1] = { icon = badge, icon_size = 64, scale = 0.75, shift = { -40, -40 }, draw_background = true }
  end
  if overlay then
    layers[#layers + 1] = {
      icon = "__core__/graphics/icons/technology/constants/" .. overlay .. ".png",
      icon_size = 128,
      scale = 0.5,
      shift = { 50, 50 },
      floating = true,
    }
  end
  return layers
end

-- A scripted effect: the technology GUI shows its description beside the item icon.
local function nothing(icon, description)
  return { type = "nothing", effect_description = description, icon = icon, icon_size = constants.icon_size }
end

local function unlocks(recipes)
  local effects = {}
  for _, recipe in ipairs(recipes) do
    effects[#effects + 1] = { type = "unlock-recipe", recipe = recipe }
  end
  return effects
end

local technologies = {
  {
    type = "technology",
    name = research.system,
    icons = icons(FREIGHTER),
    effects = unlocks(SYSTEM_RECIPES),
    prerequisites = { "engine" },
    unit = { count = 200, ingredients = LADDER[1], time = 30 },
    order = "j[jatz]-a",
  },
  {
    -- Expands the freight system to fluids. Fluid handling unlocks storage tanks, which liquid
    -- depots are.
    type = "technology",
    name = research.liquid,
    icons = icons(LIQUID),
    effects = unlocks(LIQUID_RECIPES),
    prerequisites = { research.system, "fluid-handling" },
    unit = { count = 200, ingredients = LADDER[1], time = 30 },
    order = "j[jatz]-b",
  },
  {
    -- Reads the road network onto the circuit network, so it comes after the circuit network, at
    -- Transport Drones' depot circuits cost.
    type = "technology",
    name = research.monitor,
    icons = icons(MONITOR),
    effects = unlocks(MONITOR_RECIPES),
    prerequisites = { research.system, "circuit-network" },
    unit = { count = 500, ingredients = LADDER[1], time = 30 },
    order = "j[jatz]-c",
  },
  {
    -- Freighters go under the factory between road networks, as items do on underground belts, so
    -- it comes after them (logistics).
    type = "technology",
    name = research.tunnels,
    icons = icons(TUNNEL),
    effects = unlocks(TUNNEL_RECIPES),
    prerequisites = { research.system, "logistics" },
    unit = { count = 300, ingredients = LADDER[1], time = 30 },
    order = "j[jatz]-d",
  },
}

-- `levels` finite levels of an upgrade, each after the one before, the first after `first`.
local function upgrades(name, levels, first, layers, effect)
  for level = 1, levels do
    technologies[#technologies + 1] = {
      type = "technology",
      name = name .. "-" .. level,
      icons = table.deepcopy(layers),
      upgrade = true,
      effects = { effect },
      prerequisites = { level > 1 and name .. "-" .. (level - 1) or first },
      unit = { count = level * 200, ingredients = LADDER[math.min(level, #LADDER)], time = 30 },
      order = "j[jatz]-" .. name,
    }
  end
end

local percent = tostring(math.floor(research.speed_bonus * 100 + 0.5))
local speed_effect = nothing(constants.freighter_icon, { "modifier-description.jatz-freighter-speed", percent })
upgrades(
  research.speed,
  research.speed_levels,
  research.system,
  icons(FREIGHTER, "constant-movement-speed"),
  speed_effect
)
-- Then one level after another for ever, each costing twice the last.
local infinite_level = research.speed_levels + 1
technologies[#technologies + 1] = {
  type = "technology",
  name = research.speed .. "-" .. infinite_level,
  icons = icons(FREIGHTER, "constant-movement-speed"),
  upgrade = true,
  effects = { speed_effect },
  prerequisites = { research.speed .. "-" .. research.speed_levels },
  max_level = "infinite",
  unit = {
    count_formula = string.format("2^(L-%d)*500", infinite_level),
    ingredients = { RED, GREEN, BLUE, PURPLE, YELLOW, WHITE },
    time = 60,
  },
  order = "j[jatz]-" .. research.speed,
}

local item_effect = nothing(
  constants.freighter_icon,
  { "modifier-description.jatz-freighter-item-capacity", tostring(research.stacks_per_level) }
)
upgrades(
  research.item_capacity,
  research.capacity_levels,
  research.system,
  icons(FREIGHTER, "constant-capacity"),
  item_effect
)
local fluid_effect = nothing(
  constants.freighter_icon,
  { "modifier-description.jatz-freighter-fluid-capacity", tostring(research.fluid_per_level) }
)
upgrades(
  research.fluid_capacity,
  research.fluid_capacity_levels,
  research.liquid,
  icons(FREIGHTER, "constant-capacity", FLUID_BADGE),
  fluid_effect
)

data:extend(technologies)
