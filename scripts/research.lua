-- SPDX-License-Identifier: LGPL-3.0-only
-- Freighter research (prototypes/technologies.lua, which loads this file in the data stage for the
-- names and numbers): how many levels of each upgrade a force has, and what they give.
local research = {}

-- Unlocks every recipe.
research.system = "jatz-freight-system"
-- Upgrades are named <name>-<level>.
research.speed = "jatz-freighter-speed"
research.capacity = "jatz-freighter-capacity"
-- Transport Drones' speed research: +20% a level, four levels, then an infinite one.
research.speed_levels = 4
research.speed_bonus = 0.2
-- Five capacity levels (Transport Drones has five too), each one more stack of items, or a tenth
-- of the base 500 of fluid (the owner's choice, November 5, 2026).
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
  return research.stacks_per_level * research.levels(force, research.capacity)
end

function research.extra_fluid(force)
  return research.fluid_per_level * research.levels(force, research.capacity)
end

-- Whether a finished or reversed research changes freighter speed.
function research.is_speed(technology)
  return technology.name:sub(1, #research.speed + 1) == research.speed .. "-"
end

return research
