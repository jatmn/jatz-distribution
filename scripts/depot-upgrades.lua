-- SPDX-License-Identifier: LGPL-3.0-only
-- A depot replaced by itself at another quality (the Quality mod: scripts/quality.lua): by robots
-- or a space platform carrying out an upgrade order (the upgrade planner, or a blueprint of the
-- depot at another quality pasted over it), or by a player placing the depot at another quality
-- over it (a fast replace). The game removes the old entity and builds a new one, with a new unit
-- number, in the same tick: probed on 2.1.24, robots raise on_robot_mined_entity for the old one
-- (still marked for upgrade to the same depot; no on_robot_pre_mined) and then on_robot_built_entity
-- for the new; a player raises on_pre_build, on_pre_player_mined_item, on_player_mined_entity for
-- the old one (their cursor still holding the depot) and then on_built_entity for the new. The game
-- moves the chest's contents (or the tank's fluid), wires, circuit settings and a buffer depot's
-- logistic requests itself, but not what the mod keeps by unit number, and it turns the logistic
-- points back on. So the old one's removal is not a removal: its freighters aren't handed to the
-- miner, and no undo settings wait for it, and once the new one is built everything the mod kept
-- for the old one moves to it (logistics.replaced, depot_road.replaced, road_monitor.replaced, as for
-- the depots from before they were logistic containers, scripts/legacy-depots.lua), with whether
-- logistic robots may use it. Its request, freighters (in its slot and out on trips), the trips'
-- promises and everything else carry on.
local logistics = require("scripts.logistics")
local depot_road = require("scripts.depot-road")
local road_monitor = require("scripts.road-monitor")
local robot_access = require("scripts.robot-access")

local upgrades = {}

-- Where a depot stands, and what it is: the new one is built just there, as the same depot.
local function spot(entity)
  local position = entity.position
  return entity.surface_index .. " " .. position.x .. " " .. position.y .. " " .. entity.name
end

-- A player's build: noted (`storage.depot_builds[player index]`, this tick only), for telling a
-- fast replace from a player mining a depot with one in their cursor.
function upgrades.pre_build(event)
  storage.depot_builds = storage.depot_builds or {}
  storage.depot_builds[event.player_index] = { tick = event.tick, position = event.position }
end

-- Whether `position` lies on `entity`'s ground (its selection box: where a click picks it).
local function on(entity, position)
  local box = entity.selection_box
  return position.x >= box.left_top.x
    and position.x <= box.right_bottom.x
    and position.y >= box.left_top.y
    and position.y <= box.right_bottom.y
end

-- Whether a depot being mined is being replaced by itself at another quality: by robots or a
-- platform (no player) when it is marked for an upgrade to the same depot, or by a player building
-- that depot over it this tick from their cursor. A player mining by hand a depot marked for an
-- upgrade is removing it (Claude's review: taken for an upgrade, its freighters were left on the
-- ground instead of handed to the player).
local function replacing(entity, player_index)
  if not player_index then
    if not entity.to_be_upgraded() then
      return false
    end
    local target = entity.get_upgrade_target()
    return target ~= nil and target.name == entity.name
  end
  local build = storage.depot_builds and storage.depot_builds[player_index]
  if not (build and build.tick == game.tick and on(entity, build.position)) then
    return false
  end
  local player = game.get_player(player_index)
  local cursor = player and player.cursor_stack
  local placed = cursor and cursor.valid_for_read and cursor.prototype.place_result
  return placed ~= nil and placed.name == entity.name
end

-- A delivery or Fuel depot mined: if it is being replaced by itself at another quality, note it
-- (`storage.depot_upgrades`, by its spot, for this tick) and return true: the caller then leaves its
-- freighters and settings be. Otherwise false.
function upgrades.mined(entity, player_index)
  if not (entity and entity.valid and logistics.depots[entity.name] and entity.unit_number) then
    return false
  end
  if not replacing(entity, player_index) then
    return false
  end
  local noted = storage.depot_upgrades or {}
  for key, upgrade in pairs(noted) do
    if upgrade.tick ~= game.tick then
      noted[key] = nil
    end
  end
  noted[spot(entity)] = { id = entity.unit_number, tick = game.tick, robot_access = robot_access.get(entity) }
  storage.depot_upgrades = noted
  return true
end

-- A depot built: if it replaces itself at another quality (noted by upgrades.mined this tick), it
-- takes over everything the mod kept for the old one. Call before anything else looks at it.
function upgrades.built(entity)
  local noted = storage.depot_upgrades
  if not (noted and entity.unit_number) then
    return
  end
  local key = spot(entity)
  local upgrade = noted[key]
  noted[key] = nil
  if next(noted) == nil then
    storage.depot_upgrades = nil
  end
  if not (upgrade and upgrade.tick == game.tick and upgrade.id ~= entity.unit_number) then
    return
  end
  logistics.replaced(upgrade.id, entity)
  depot_road.replaced(upgrade.id, entity)
  road_monitor.replaced(upgrade.id, entity.unit_number)
  if upgrade.robot_access ~= nil then
    robot_access.set(entity, upgrade.robot_access)
  end
end

return upgrades
