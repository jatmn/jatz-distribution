-- SPDX-License-Identifier: LGPL-3.0-only
-- Undo for depots and road network monitors. When a player removes one (marks it for
-- deconstruction, cuts it, or mines it by hand), Factorio records the removal on their undo stack
-- from the entity alone, without the mod's settings, so undoing it brings back a bare ghost: no
-- request, no freighters, priority or circuit condition. So the settings, as a blueprint keeps them
-- (logistics.settings_tags), go on the removal's undo action as a tag, and when the player undoes
-- it they go on the ghost that comes back, whose build passes them to apply_tags and
-- road_monitor.add as a blueprint ghost's do (robots or the player building it): robots bring its
-- freighters back.
--
-- The settings are the ones it had when it went, read just before (on_robot_pre_mined,
-- on_pre_player_mined_item: its chest still holds its freighters there, which mining hands over
-- before on_*_mined_entity). Probed on 2.1.24 with a player (--test-scenario): marking for
-- deconstruction makes its undo action right after on_marked_for_deconstruction, and the action
-- keeps its tags through the robots' removal, so a robot removal tags the action of the player who
-- marked it at once; mining by hand makes its undo item only after on_player_mined_entity, so that
-- removal is tagged from the next tick, and an undo before then takes the settings still waiting.
local logistics = require("scripts.logistics")

local undo = {}

-- The undo action tag holding an entity's settings tags.
local TAG = "jatz_settings"
-- Settings waiting for their undo action are given up after this long (a removal that made none).
local GIVE_UP_TICKS = 60

local function key(surface_index, name, position)
  return surface_index .. " " .. name .. " " .. position.x .. " " .. position.y
end

local function undo_stack(player_index)
  local player = game.get_player(player_index)
  return player and player.valid and player.undo_redo_stack or nil
end

-- Waiting settings by key, each key's newest first, from a list in the order they were noted.
local function by_key(entries)
  local found = {}
  for index = #entries, 1, -1 do
    local entry = entries[index]
    local list = found[entry.key] or {}
    found[entry.key] = list
    list[#list + 1] = entry
  end
  return found
end

-- Tag the undo actions of these removals (`entries`, in the order they happened) on a player's
-- stack: each its own removal action, the newest removal the newest action, so several at the same
-- spot don't take each other's. Returns the entries whose action wasn't found.
local function tag(stack, entries)
  local wanted = by_key(entries)
  local left = #entries
  for item = 1, stack.get_undo_item_count() do
    if left == 0 then
      break
    end
    for action_index, action in ipairs(stack.get_undo_item(item)) do
      local target = action.type == "removed-entity" and action.surface_index and action.target
      local list = target and wanted[key(action.surface_index, target.name, target.position)]
      local entry = list and table.remove(list, 1)
      if entry then
        stack.set_undo_tag(item, action_index, TAG, entry.tags)
        entry.tagged, left = true, left - 1
      end
    end
  end
  local missing = {}
  for _, entry in ipairs(entries) do
    if not entry.tagged then
      missing[#missing + 1] = entry
    end
  end
  return missing
end

-- Settings waiting for a player's undo action, looked for from the next tick.
local function wait(player_index, entries)
  if #entries == 0 then
    return
  end
  storage.undo_pending = storage.undo_pending or {}
  local pending = storage.undo_pending[player_index] or {}
  storage.undo_pending[player_index] = pending
  for _, entry in ipairs(entries) do
    pending[#pending + 1] = entry
  end
end

-- `entity`'s settings as they are now, keyed by where it stands, or nil if it has none to keep.
local function note(entity)
  local tags = logistics.settings_tags(entity)
  return tags and { key = key(entity.surface_index, entity.name, entity.position), tags = tags, tick = game.tick }
end

-- A player marked a depot or monitor for deconstruction (or cut it): who, for when robots take it.
function undo.marked(entity, player_index)
  if player_index and entity.valid and entity.unit_number then
    storage.undo_marked = storage.undo_marked or {}
    storage.undo_marked[entity.unit_number] = player_index
  end
end

-- Its deconstruction cancelled, or it is gone: no removal of it to keep settings for.
function undo.forget(unit_number)
  if storage.undo_marked and unit_number then
    storage.undo_marked[unit_number] = nil
    if next(storage.undo_marked) == nil then
      storage.undo_marked = nil
    end
  end
end

-- Robots are about to take a depot or monitor a player marked: its settings go on that player's
-- undo action for it now.
function undo.robot_removing(entity)
  local player_index = storage.undo_marked and entity.valid and storage.undo_marked[entity.unit_number]
  if not player_index then
    return
  end
  undo.forget(entity.unit_number)
  local entry = note(entity)
  local stack = entry and undo_stack(player_index)
  if stack then
    wait(player_index, tag(stack, { entry }))
  end
end

-- A player is about to mine a depot or monitor by hand: its settings wait for the undo item the
-- mining makes. (Noted even if the mining doesn't remove it after all: no action turns up then.)
function undo.player_removing(entity, player_index)
  if not (player_index and entity.valid) then
    return
  end
  undo.forget(entity.unit_number)
  local entry = note(entity)
  if entry then
    wait(player_index, { entry })
  end
end

-- Tag the undo actions of the removals noted before this tick (control.lua's on_tick, only while
-- some are pending).
function undo.tag_pending(tick)
  for player_index, pending in pairs(storage.undo_pending) do
    local due, waiting = {}, {}
    for _, entry in ipairs(pending) do
      if entry.tick < tick then
        due[#due + 1] = entry
      else
        waiting[#waiting + 1] = entry
      end
    end
    local stack = undo_stack(player_index)
    local missing = stack and tag(stack, due) or due
    -- Not found yet: looked for again next tick, for a while.
    for _, entry in ipairs(missing) do
      if tick - entry.tick < GIVE_UP_TICKS then
        waiting[#waiting + 1] = entry
      end
    end
    storage.undo_pending[player_index] = #waiting > 0 and waiting or nil
  end
  if next(storage.undo_pending) == nil then
    storage.undo_pending = nil
  end
end

-- Settings still waiting for a player's undo action at `key`: the newest, taken off the list.
local function take_pending(player_index, wanted)
  local pending = storage.undo_pending and storage.undo_pending[player_index]
  for index = #(pending or {}), 1, -1 do
    if pending[index].key == wanted then
      return table.remove(pending, index).tags
    end
  end
end

-- A player undid something: removals of ours come back as ghosts, which get the settings their
-- undo action kept (or, undone before it was tagged, the settings waiting for it). One whose
-- removal hadn't happened yet (deconstruction cancelled) still has them, and no ghost.
function undo.on_undo_applied(event)
  for _, action in pairs(event.actions or {}) do
    local target = action.type == "removed-entity" and action.surface_index and action.target
    local spot = target and key(action.surface_index, target.name, target.position)
    local settings = spot and (action.tags and action.tags[TAG] or take_pending(event.player_index, spot))
    local surface = settings and game.surfaces[action.surface_index]
    if surface then
      for _, ghost in pairs(surface.find_entities_filtered({ ghost_name = target.name, position = target.position })) do
        if ghost.position.x == target.position.x and ghost.position.y == target.position.y then
          local tags = ghost.tags or {}
          for name, value in pairs(settings) do
            tags[name] = value
          end
          ghost.tags = tags
        end
      end
    end
  end
end

return undo
