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
-- new one, then on_robot_built_entity in the same tick; a script's LuaEntity.apply_upgrade (Blueprint
-- Sandboxes carries out upgrade orders that way in its labs) raises script_raised_destroy for the
-- old one, still marked for upgrade to the new one, then script_raised_built in the same tick.
-- on_object_destroyed for the old one comes at the end of that tick. Its mining would hand its
-- freighters to the miner, and its scripted destruction leave them on the ground, so `replacing`
-- tells control.lua not to, and remembers it for the build that follows (`built`). A script can
-- as well destroy a marked depot outright, with no build to follow, and its chest goes with it, so
-- `destroying` keeps the freighters in its chest aside until the build or the end of the tick.
local logistics = require("scripts.logistics")
local depot_road = require("scripts.depot-road")
local robot_access = require("scripts.robot-access")
local road_monitor = require("scripts.road-monitor")

local swap = {}

local FREIGHTER = "jatz-quinityn-freighter"

-- What each depot is replaced with.
local PARTNER = { ["jatz-request-depot"] = "jatz-buffer-depot", ["jatz-buffer-depot"] = "jatz-request-depot" }
swap.names = { "jatz-buffer-depot", "jatz-request-depot" }

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
-- or by a robot or platform without one), or destroyed by a script's apply_upgrade
-- (script_raised_destroy, without one), is being replaced by the other kind: the player placed it
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

-- The freighters a replacement kept aside (`destroying`), put into `chest` as far as it has room
-- (nil: none), the rest left on the ground at `position`, as logistics.on_depot_destroyed leaves a
-- destroyed depot's.
local function hand_back(held, surface, position, chest)
  for index = 1, #held do
    local stack = held[index]
    if stack.valid_for_read and chest then
      local inserted = chest.insert(stack)
      if inserted >= stack.count then
        stack.clear()
      else
        stack.count = stack.count - inserted
      end
    end
    if stack.valid_for_read and surface then
      surface.spill_item_stack({ position = position, stack = stack, enable_looted = true, allow_belts = false })
    end
    stack.clear()
  end
  held.destroy()
end

-- A request or buffer depot a script is about to destroy (script_raised_destroy): whether it is
-- being replaced by the other kind (`replacing`: marked for that upgrade, which a script's
-- apply_upgrade carries out at once). If so, the freighters still in its chest are taken out and
-- kept with that note (`held`) rather than spilled: the new depot gets them back in its chest
-- (`built`), wherever the game moved the rest of the chest, and if none is built they are left
-- where it stood when it is gone (`gone`), as for any depot destroyed (logistics.on_depot_destroyed).
-- Freighter items carry their entity's data, so the stacks themselves are kept.
function swap.destroying(entity)
  if not swap.replacing(entity) then
    return false
  end
  local chest = logistics.inventory(entity)
  local held
  for index = 1, #chest do
    local stack = chest[index]
    if stack.valid_for_read and stack.name == FREIGHTER then
      held = held or game.create_inventory(#chest)
      held[index].transfer_stack(stack)
    end
  end
  local swaps = storage.depot_swaps
  swaps[#swaps].held = held
  return true
end

-- A request or buffer depot just built: if it replaces the other kind at its spot this tick, it
-- takes over everything the mod kept for that one. Older replacements that never came are dropped,
-- the freighters they kept aside left where their depot stood (`gone` does so for a depot gone
-- before this; its on_object_destroyed hands out the rest as for any depot destroyed).
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
    elseif pending.held then
      hand_back(pending.held, game.surfaces[pending.surface_index], pending.position)
    end
  end
  storage.depot_swaps = #kept > 0 and kept or nil
  if not found then
    return
  end
  if found.held then
    hand_back(found.held, entity.surface, here, logistics.inventory(entity))
  end
  local old_id = found.unit_number
  logistics.replaced(old_id, entity)
  depot_road.replaced(old_id, entity)
  road_monitor.replaced(old_id, entity.unit_number)
  -- Robots stay out of a buffer depot until it lets them, as of every new depot.
  robot_access.set(entity, false)
end

-- An entity gone (on_object_destroyed, its unit number `id`): a depot whose replacement never came
-- this tick (a script destroyed it while it was marked for upgrade) is forgotten, the freighters
-- kept aside from its chest left where it stood. One replaced is no longer noted here.
function swap.gone(id)
  local swaps = storage.depot_swaps
  if not swaps then
    return
  end
  for index, pending in ipairs(swaps) do
    if pending.unit_number == id then
      table.remove(swaps, index)
      if #swaps == 0 then
        storage.depot_swaps = nil
      end
      if pending.held then
        hand_back(pending.held, game.surfaces[pending.surface_index], pending.position)
      end
      return
    end
  end
end

-- Undo and redo. Robots' replacements are recorded as upgrades ("upgraded-entity", with the
-- original name), which undo and redo as upgrade orders, so robots swap the depot back in place as
-- above. A player's replacement by hand is recorded as the old depot removed and the new one built
-- in one undo item (probed on 2.1.24), and undoing that marks the new depot for deconstruction and
-- puts a ghost of the old one over it: robots would empty it and take it, freighters and all, and
-- build a bare depot from the ghost (the removal's undo action keeps its settings, scripts/undo.lua,
-- but not its chest). So, once the game has applied the undo or redo, a depot of the pair standing
-- marked for deconstruction under a ghost of the other, where that item removed one and built the
-- other, is marked for upgrade to it instead, for robots to swap in place (probed: they do, with
-- its request, freighters and chest). It is upgraded to the ghost's quality and facing, the depot
-- the undo or redo brings back, which need not be the standing one's: an upgrade keeps the
-- standing depot's facing (order_upgrade takes none), so it is turned to the ghost's first, as a
-- player turning it (`turned`, control.lua's: its road, loading zone and trips follow). Without
-- `player`, which would add the order to the player's undo queue.
local function swap_back(surface, position, turned)
  for _, depot in pairs(surface.find_entities_filtered({ name = swap.names, position = position })) do
    local partner = PARTNER[depot.name]
    local ghosts = depot.to_be_deconstructed()
      and surface.find_entities_filtered({ ghost_name = partner, position = position })
    if ghosts and #ghosts > 0 and depot.position.x == position.x and depot.position.y == position.y then
      local quality, direction = ghosts[1].quality, ghosts[1].direction
      depot.cancel_deconstruction(depot.force)
      for _, ghost in pairs(ghosts) do
        ghost.destroy()
      end
      if turned and depot.direction ~= direction then
        depot.direction = direction
        turned(depot)
      end
      depot.order_upgrade({ target = { name = partner, quality = quality }, force = depot.force })
    end
  end
end

-- on_undo_applied and on_redo_applied (after scripts/undo.lua's): the actions applied. `turned`
-- is called with a depot turned to its ghost's facing.
function swap.on_undo_applied(event, turned)
  local removed, built = {}, {}
  for _, action in pairs(event.actions or {}) do
    local target = action.target
    if target and PARTNER[target.name] and action.surface_index then
      if action.type == "removed-entity" then
        removed[#removed + 1] = action
      elseif action.type == "built-entity" then
        built[#built + 1] = action
      end
    end
  end
  for _, gone in ipairs(removed) do
    for _, made in ipairs(built) do
      local from, to = gone.target, made.target
      local surface = game.surfaces[gone.surface_index]
      if
        surface
        and gone.surface_index == made.surface_index
        and PARTNER[from.name] == to.name
        and from.position.x == to.position.x
        and from.position.y == to.position.y
      then
        swap_back(surface, from.position, turned)
      end
    end
  end
end

return swap
