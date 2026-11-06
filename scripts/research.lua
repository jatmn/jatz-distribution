-- SPDX-License-Identifier: LGPL-3.0-only
-- Freighter research (prototypes/technologies.lua, which loads this file in the data stage for the
-- names and numbers): how many levels of each upgrade a force has, and what they give.
local research = {}

-- Unlocks the item depots, the fuel depot, the freighter and road.
research.system = "jatz-freight-system"
-- Expands it with the liquid depots.
research.liquid = "jatz-liquid-freight"
-- Unlocks the road network monitor, after the circuit network.
research.monitor = "jatz-road-network-monitor"
-- Every technology that unlocks recipes.
research.unlocks = { research.system, research.liquid, research.monitor }
-- Upgrades are named <name>-<level>.
research.speed = "jatz-freighter-speed"
research.item_capacity = "jatz-freighter-item-capacity"
research.fluid_capacity = "jatz-freighter-fluid-capacity"
-- Transport Drones' speed research: +20% a level, four levels, then an infinite one.
research.speed_levels = 4
research.speed_bonus = 0.2
-- Five levels each of item capacity, one more stack a level, and fluid capacity, a tenth of the
-- base 500 a level (Transport Drones has five capacity levels; the owner's choice, November 5,
-- 2026, as two separate upgrades).
research.capacity_levels = 5
research.stacks_per_level = 1
research.fluid_per_level = 50

-- The levels of `name` the force has researched: `name-1`, `name-2`, ... in turn, up to the first
-- not researched. An infinite level's `level` is the next one to research, so one less is done.
function research.levels(force, name)
  local technologies = force.technologies
  local done = 0
  local level = 1
  while prototypes.technology[name .. "-" .. level] do
    local technology = technologies[name .. "-" .. level]
    if not technology.researched then
      return math.max(done, technology.level - 1)
    end
    done = technology.level
    level = level + 1
  end
  return done
end

-- What a force's freighters get from research.
function research.speed_multiplier(force)
  return 1 + research.speed_bonus * research.levels(force, research.speed)
end

function research.extra_stacks(force)
  return research.stacks_per_level * research.levels(force, research.item_capacity)
end

function research.extra_fluid(force)
  return research.fluid_per_level * research.levels(force, research.fluid_capacity)
end

-- A new game, or a save the mod is added to, gets its recipes by research.
function research.init()
  storage.recipes_by_research = true
end

-- A save from before research had every recipe from the start. When the technology unlocks
-- change, Factorio resets every force's technology effects on load (2.1's changelog: "Reset
-- technology effects is automatically run when technology unlocks change"), so all those recipes
-- start locked again, with nothing researched. Once, then, for such a save: every force gets the
-- unlocking research, so it keeps its recipes, and future effect resets keep them too.
function research.on_configuration_changed()
  if storage.recipes_by_research then
    return
  end
  for _, force in pairs(game.forces) do
    for _, name in ipairs(research.unlocks) do
      force.technologies[name].researched = true
    end
  end
  storage.recipes_by_research = true
end

-- Whether a finished or reversed research changes freighter speed.
function research.is_speed(technology)
  return technology.name:sub(1, #research.speed + 1) == research.speed .. "-"
end

return research
