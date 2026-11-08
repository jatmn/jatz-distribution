-- SPDX-License-Identifier: LGPL-3.0-only
-- Freighter research (prototypes/technologies.lua, which loads this file in the data stage for the
-- names and numbers): how many levels of each upgrade a force has, and what they give. At runtime
-- also what a force's freighters carry and how fast they drive (split out of scripts/logistics.lua,
-- whose main chunk had reached Lua's limit of 200 locals, issue #69).
local paint = require("scripts.freighter-paint")

local research = {}

-- Unlocks the item depots, the fuel depot, the freighter and road.
research.system = "jatz-freight-system"
-- Expands it with the liquid depots.
research.liquid = "jatz-liquid-freight"
-- Unlocks the road network monitor, after the circuit network.
research.monitor = "jatz-road-network-monitor"
-- Unlocks road tunnels, after underground belts.
research.tunnels = "jatz-road-tunnels"
-- Every technology that unlocked recipes in saves from before research (on_configuration_changed
-- researches them for those). Road tunnels came after research, so no save had them unlocked.
research.unlocks = { research.system, research.liquid, research.monitor }
-- Upgrades are named <name>-<level>.
research.speed = "jatz-freighter-speed"
research.item_capacity = "jatz-freighter-item-capacity"
research.fluid_capacity = "jatz-freighter-fluid-capacity"
-- Transport Drones' speed research: +20% a level, four levels, then an infinite one.
research.speed_levels = 4
research.speed_bonus = 0.2
-- Item capacity: ten levels, one more stack a level, from 2 up to 12 (the owner's choice,
-- November 8, 2026).
-- Fluid capacity: ten levels, 375 a level, from 750 up to 4,500 (the owner's choice, November 8,
-- 2026). The two stay separate upgrades.
research.capacity_levels = 10
research.fluid_capacity_levels = 10
research.stacks_per_level = 1
research.fluid_per_level = 375
-- A freighter carries at most this many stacks, or this much fluid, before capacity research.
research.base_stacks = 2
research.base_fluid = 750

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

-- A force's research for freighters, kept (storage.research_levels[force index]): working it out
-- reads every level's technology and prototype, objects for Lua to collect, and freighters set off
-- many times a second. Forgotten when the force's research changes (logistics.on_research_changed),
-- when forces are reset, made or merged (a merged force's index can be given to a new one), on
-- configuration changes, and after a minute, in case a script changed a level without an event.
local RESEARCH_MEMORY_TICKS = 60 * 60
local function research_of(force)
  storage.research_levels = storage.research_levels or {}
  local index = force.index
  local known = storage.research_levels[index]
  if not (known and game.tick - known.tick < RESEARCH_MEMORY_TICKS) then
    known = {
      stacks = research.extra_stacks(force),
      fluid = research.extra_fluid(force),
      speed = research.speed_multiplier(force),
      tick = game.tick,
    }
    storage.research_levels[index] = known
  end
  return known
end

-- The freighter's own speed, read from its prototype once (prototypes don't change while the game
-- runs; reading one makes a new object every time).
local drone_speed

-- What a force's freighters carry and how fast they drive, with its research. A trip keeps the
-- cargo size it set off with; speed research also reaches freighters already on the road
-- (logistics.on_research_changed).
function research.cargo_stacks(force)
  return research.base_stacks + research_of(force).stacks
end

function research.fluid_capacity_of(force)
  return research.base_fluid + research_of(force).fluid
end

function research.freighter_speed(force)
  drone_speed = drone_speed or prototypes.entity[paint.empty].speed
  return drone_speed * research_of(force).speed
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
