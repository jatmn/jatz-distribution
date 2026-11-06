-- SPDX-License-Identifier: LGPL-3.0-only
-- Undo for depots and road network monitors. When a player removes one (marks it for
-- deconstruction, cuts it, or mines it by hand), Factorio records the removal on their undo stack
-- from the entity alone, without the mod's settings, so undoing it brings back a bare ghost: no
-- request, no freighters, priority or circuit condition. So the settings, as a blueprint keeps them
-- (logistics.settings_tags), go on the removal's undo action as a tag, and when the player undoes
-- it they go on the ghost that comes back, whose build passes them to apply_tags and
-- road_monitor.add as a blueprint ghost's do: robots bring its freighters back.
local logistics = require("scripts.logistics")

local undo = {}

-- The undo action tag holding an entity's settings tags.
local TAG = "jatz_settings"
-- The undo item may not exist yet during the removal's event, so its action is tagged from the next
-- tick on, looking through this many of the player's latest undo items, and given up after this
-- long (a removal that made no undo item).
local LOOKBACK = 3
local GIVE_UP_TICKS = 60

local function key(surface_index, name, position)
  return surface_index .. " " .. name .. " " .. position.x .. " " .. position.y
end

-- A player removed `entity` (a depot or a road network monitor): note its settings for its undo
-- action. Before anything else handles the removal, while its freighters are still counted.
function undo.removed(entity, player_index)
  if not (player_index and entity and entity.valid) then
    return
  end
  local tags = logistics.settings_tags(entity)
  if not tags then
    return
  end
  storage.undo_pending = storage.undo_pending or {}
  local pending = storage.undo_pending[player_index] or {}
  storage.undo_pending[player_index] = pending
  pending[#pending + 1] =
    { key = key(entity.surface_index, entity.name, entity.position), tags = tags, tick = game.tick }
end

-- Tag the undo actions of the removals noted before this tick (control.lua's on_tick, only while
-- some are pending).
function undo.tag_pending(tick)
  for player_index, pending in pairs(storage.undo_pending) do
    local wanted, waiting = {}, {}
    for _, entry in ipairs(pending) do
      if entry.tick < tick then
        wanted[entry.key] = entry
      else
        waiting[#waiting + 1] = entry
      end
    end
    local player = game.get_player(player_index)
    local stack = player and player.valid and player.undo_redo_stack
    if stack and next(wanted) then
      for item = 1, math.min(LOOKBACK, stack.get_undo_item_count()) do
        for action_index, action in ipairs(stack.get_undo_item(item)) do
          local target = action.type == "removed-entity" and action.surface_index and action.target
          local entry = target and wanted[key(action.surface_index, target.name, target.position)]
          if entry then
            stack.set_undo_tag(item, action_index, TAG, entry.tags)
            wanted[entry.key] = nil
          end
        end
      end
    end
    -- Not found yet: looked for again next tick, for a while.
    for _, entry in pairs(wanted) do
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

-- A player undid something: removals of ours come back as ghosts, which get the settings their
-- undo action kept. One whose removal hadn't happened yet (deconstruction cancelled) still has
-- them, and no ghost.
function undo.on_undo_applied(event)
  for _, action in pairs(event.actions or {}) do
    local settings = action.type == "removed-entity" and action.tags and action.tags[TAG]
    local surface = settings and action.surface_index and game.surfaces[action.surface_index]
    if surface then
      local target = action.target
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
