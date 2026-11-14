-- SPDX-License-Identifier: LGPL-3.0-only
-- Item request and buffer depots replace each other in place, as Factorio's chests do (the owner's
-- request, November 14, 2026): they share a fast replaceable group (prototypes/depots.lua), so a
-- player can place one over the other by hand, and robots replace one marked for upgrade (a ghost
-- or a blueprint placed over it). The game moves the chest's contents and wires to the new depot,
-- which gets a new unit number; everything the mod kept by the old one (its request and settings,
-- freighters in its slot and out on trips, promises, its depot road, the road network monitors'
-- counts) goes to the new one, as a legacy depot's does (scripts/legacy-depots.lua), and it takes
-- the new one's role (logistics.replaced).
--
-- Probed on 2.1.24 (a player's build_from_cursor, and robots): a player's replacement raises
-- on_pre_build (the old depot still holding its contents), on_pre_player_mined_item and
-- on_player_mined_entity (its contents already moved), then on_built_entity for the new one, all
-- in one tick; robots raise on_robot_mined_entity for the old one, still marked for upgrade to the
-- new one, then on_robot_built_entity in the same tick. on_object_destroyed for the old one comes
-- at the end of that tick. Its mining would hand its freighters to the miner, so `replacing` tells
-- control.lua not to, and remembers it for the build that follows (`built`).
local logistics = require("scripts.logistics")
local depot_road = require("scripts.depot-road")
local robot_access = require("scripts.robot-access")
local road_monitor = require("scripts.road-monitor")

local swap = {}

-- What each depot is replaced with.
local PARTNER = { ["jatz-request-depot"] = "jatz-buffer-depot", ["jatz-buffer-depot"] = "jatz-request-depot" }

-- A player about to place a request or buffer depot from their hand over the other one: noted
-- (storage.depot_swap_hands[player_index]) for its mining, which comes next in the same tick.
function swap.on_pre_build(event)
  local player = game.get_player(event.player_index)
  local stack = player and player.cursor_stack
  local placed = stack and stack.valid_for_read and stack.prototype.place_result
  local replaced = placed and PARTNER[placed.name]
  if not replaced then
    return
  end
  local found = player.surface.find_entities_filtered({ name = replaced, position = event.position })[1]
  if found then
    storage.depot_swap_hands = storage.depot_swap_hands or {}
    storage.depot_swap_hands[event.player_index] = { unit_number = found.unit_number, tick = game.tick }
  end
end

-- Whether a request or buffer depot being mined (on_*_mined_entity, by the player `player_index`
-- or by a robot or platform without one) is being replaced by the other kind: the player placed it
-- over this one, or a robot is upgrading this one to it. If so, it is remembered for the build that
-- follows (storage.depot_swaps, kept for this tick only).
function swap.replacing(entity, player_index)
  local partner = PARTNER[entity.name]
  if not partner then
    return false
  end
  local replacing
  if player_index then
    local hands = storage.depot_swap_hands
    local noted = hands and hands[player_index]
    if noted then
      hands[player_index] = nil
      if next(hands) == nil then
        storage.depot_swap_hands = nil
      end
    end
    replacing = noted and noted.unit_number == entity.unit_number and noted.tick == game.tick
  else
    local target = entity.to_be_upgraded() and entity.get_upgrade_target()
    replacing = target and target.name == partner
  end
  if not replacing then
    return false
  end
  local swaps = storage.depot_swaps or {}
  storage.depot_swaps = swaps
  swaps[#swaps + 1] = {
    unit_number = entity.unit_number,
    name = partner,
    surface_index = entity.surface_index,
    position = entity.position,
    tick = game.tick,
  }
  return true
end

-- A request or buffer depot just built: if it replaces the other kind at its spot this tick, it
-- takes over everything the mod kept for that one. Older replacements that never came are dropped
-- (their depot's on_object_destroyed hands its freighters out as for any depot destroyed).
function swap.built(entity)
  local swaps = storage.depot_swaps
  if not swaps then
    return
  end
  local here, kept, found = entity.position, {}, nil
  for _, pending in ipairs(swaps) do
    if
      not found
      and pending.tick == game.tick
      and pending.name == entity.name
      and pending.surface_index == entity.surface_index
      and pending.position.x == here.x
      and pending.position.y == here.y
    then
      found = pending
    elseif pending.tick == game.tick then
      kept[#kept + 1] = pending
    end
  end
  storage.depot_swaps = #kept > 0 and kept or nil
  if not found then
    return
  end
  local old_id = found.unit_number
  logistics.replaced(old_id, entity)
  depot_road.replaced(old_id, entity)
  road_monitor.replaced(old_id, entity.unit_number)
  -- Robots stay out of a buffer depot until it lets them, as of every new depot.
  robot_access.set(entity, false)
end

return swap
