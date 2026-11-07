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
-- marked it at once (again, if an attempt left it standing: it stays marked until it is gone or
-- cancelled). Mining by hand makes its undo item only after on_player_mined_entity, so the
-- settings read before it are held until that event says it was removed (a failed attempt, a full
-- inventory say, leaves nothing waiting), tagged from the next tick, and an undo before then takes
-- the settings still waiting.
local logistics = require("scripts.logistics")

local undo = {}

-- The undo action tag holding an entity's settings tags.
local TAG = "jatz_settings"
-- The undo action tag marking which entity a marked removal is for (its unit number), so robots
-- and platforms taking it find its action without reading undo items again.
local MARK = "jatz_removal_of"
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

-- The removal (of `list`, a spot's newest first) that may take this undo action: the newest, unless
-- the action is marked as another entity's removal (its marking located it, MARK), which only that
-- entity's may take, so a removal never takes a later one's at the same spot. Taken off the list.
local function owner(list, action)
  local mark = action.tags and action.tags[MARK]
  for index, entry in ipairs(list or {}) do
    if not mark or entry.unit_number == mark then
      return table.remove(list, index)
    end
  end
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
      local entry = target and owner(wanted[key(action.surface_index, target.name, target.position)], action)
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

-- `entity`'s settings as they are now, keyed by where it stands: empty when it has none to keep,
-- which is a snapshot too (it replaces settings an earlier attempt saved, and keeps removals at one
-- spot in order).
local function note(entity)
  return {
    unit_number = entity.unit_number,
    key = key(entity.surface_index, entity.name, entity.position),
    tags = logistics.settings_tags(entity) or {},
    tick = game.tick,
  }
end

-- A player marked a depot or monitor for deconstruction (or cut it): who, for when robots or the
-- platform take it, and its undo action to find (control.lua's on_tick, from the next tick: the
-- action is made just after this event).
function undo.marked(entity, player_index)
  if player_index and entity.valid and entity.unit_number then
    storage.undo_marked = storage.undo_marked or {}
    storage.undo_marked[entity.unit_number] = {
      player_index = player_index,
      key = key(entity.surface_index, entity.name, entity.position),
      tick = game.tick,
    }
    storage.undo_locating = true
  end
end

-- Find the undo actions of the removals marked before this tick, a player's all in one look
-- through their undo items (a cut of many depots is one item: read once, not once per depot), and
-- mark each with its entity, remembering where it is counted from the bottom of the stack, which
-- new undo items pushed on top don't change.
local function locate(tick)
  local wanted, later = {}, nil
  for unit_number, marked in pairs(storage.undo_marked or {}) do
    if not marked.bottom and not marked.unlocated and marked.tick >= tick then
      later = true
    elseif not marked.bottom and not marked.unlocated then
      local by_player = wanted[marked.player_index] or {}
      wanted[marked.player_index] = by_player
      local list = by_player[marked.key] or {}
      by_player[marked.key] = list
      list[#list + 1] = unit_number
      -- Looked for once: if not found now, a removal looks for it itself.
      marked.unlocated = true
    end
  end
  -- Marked this tick: located on the next.
  storage.undo_locating = later
  for player_index, spots in pairs(wanted) do
    local stack = undo_stack(player_index)
    local count = stack and stack.get_undo_item_count() or 0
    local left = 0
    for _, list in pairs(spots) do
      left = left + #list
    end
    for item = 1, count do
      if left == 0 then
        break
      end
      for action_index, action in ipairs(stack.get_undo_item(item)) do
        local target = action.type == "removed-entity" and action.surface_index and action.target
        local list = target and spots[key(action.surface_index, target.name, target.position)]
        local unit_number = list and table.remove(list, 1)
        if unit_number then
          stack.set_undo_tag(item, action_index, MARK, unit_number)
          local marked = storage.undo_marked[unit_number]
          marked.bottom, marked.action, marked.unlocated = count - item + 1, action_index, nil
          left = left - 1
        end
      end
    end
  end
end

-- Its deconstruction cancelled, or it is gone (on_object_destroyed): no removal of it to keep
-- settings for. Only then: a mining attempt (by robots or by hand) can fail and leave it standing,
-- still marked (a player's full inventory, say), and robots taking it later must still find who
-- marked it.
function undo.forget(unit_number)
  if storage.undo_marked and unit_number then
    storage.undo_marked[unit_number] = nil
    if next(storage.undo_marked) == nil then
      storage.undo_marked = nil
    end
  end
end

-- Robots or a space platform are about to take a depot or monitor a player marked: its settings
-- go on that player's undo action for it now (again, newest, if an earlier attempt left it
-- standing). Straight to the action located for it, checked by its mark; only if the stack moved
-- under it (undone, or trimmed at its oldest), or it is taken before it was located (a platform
-- takes it within the tick), are the player's undo items read to find it.
function undo.removing_marked(entity)
  local marked = storage.undo_marked and entity.valid and storage.undo_marked[entity.unit_number]
  local stack = marked and undo_stack(marked.player_index)
  if not stack then
    return
  end
  local entry = note(entity)
  if marked.bottom then
    local item = stack.get_undo_item_count() - marked.bottom + 1
    -- The item there may now have fewer actions: reading past them is an error, not a nil.
    local ok, mark = false, nil
    if item >= 1 then
      ok, mark = pcall(stack.get_undo_tag, item, marked.action, MARK)
    end
    if ok and mark == entity.unit_number then
      stack.set_undo_tag(item, marked.action, TAG, entry.tags)
      return
    end
  end
  -- Not found: no undo action of it is left to keep the settings on.
  tag(stack, { entry })
end

-- A player is about to mine a depot or monitor by hand: its settings now, held until the mining
-- removes it (one at a time per player: the latest attempt replaces an earlier one).
function undo.player_removing(entity, player_index)
  if not (player_index and entity.valid) then
    return
  end
  local entry = note(entity)
  storage.undo_mining = storage.undo_mining or {}
  storage.undo_mining[player_index] = entry and { unit_number = entity.unit_number, entry = entry } or nil
  if next(storage.undo_mining) == nil then
    storage.undo_mining = nil
  end
end

-- The player's mining removed it: those settings wait for the undo item the mining makes. A
-- mining attempt that fails (a full inventory, say) leaves it standing and gets here never, so
-- nothing waits that a later removal at the same spot could take.
function undo.player_removed(entity, player_index)
  local mining = storage.undo_mining and storage.undo_mining[player_index]
  if not mining then
    return
  end
  storage.undo_mining[player_index] = nil
  if next(storage.undo_mining) == nil then
    storage.undo_mining = nil
  end
  if entity.valid and mining.unit_number == entity.unit_number then
    -- Its undo item is the next one pushed on this player's stack (probed on 2.1.24: just after
    -- this event), so it is this far from the bottom whatever comes on top before it is tagged (a
    -- replacement at the same spot marked meanwhile, say).
    local stack = undo_stack(player_index)
    mining.entry.bottom = stack and stack.get_undo_item_count() + 1
    wait(player_index, { mining.entry })
  end
end

-- Tag each removal that knows its undo item (`entry.bottom`) on that item, if its action is there.
-- Returns the rest, for `tag` to look for.
local function tag_own_items(stack, entries)
  local rest = {}
  local count = stack.get_undo_item_count()
  for _, entry in ipairs(entries) do
    local item = entry.bottom and count - entry.bottom + 1
    if item and item >= 1 and item <= count then
      for action_index, action in ipairs(stack.get_undo_item(item)) do
        local target = action.type == "removed-entity" and action.surface_index and action.target
        if
          not entry.tagged
          and target
          and key(action.surface_index, target.name, target.position) == entry.key
          and owner({ entry }, action)
        then
          stack.set_undo_tag(item, action_index, TAG, entry.tags)
          entry.tagged = true
        end
      end
    end
    if not entry.tagged then
      rest[#rest + 1] = entry
    end
  end
  return rest
end

-- Tag the undo actions of the removals noted before this tick, and locate those marked before it
-- (control.lua's on_tick, only while there are some: storage.undo_pending or undo_locating).
function undo.tag_pending(tick)
  if storage.undo_locating then
    locate(tick)
  end
  for player_index, pending in pairs(storage.undo_pending or {}) do
    -- Noted this tick: from the next. Older than GIVE_UP_TICKS: given up, never tagged late.
    local due, waiting = {}, {}
    for _, entry in ipairs(pending) do
      if entry.tick >= tick then
        waiting[#waiting + 1] = entry
      elseif tick - entry.tick < GIVE_UP_TICKS then
        due[#due + 1] = entry
      end
    end
    local stack = undo_stack(player_index)
    -- Not found yet: looked for again next tick, until given up.
    for _, entry in ipairs(stack and tag(stack, tag_own_items(stack, due)) or due) do
      waiting[#waiting + 1] = entry
    end
    storage.undo_pending[player_index] = #waiting > 0 and waiting or nil
  end
  if storage.undo_pending and next(storage.undo_pending) == nil then
    storage.undo_pending = nil
  end
end

-- Settings still waiting for a player's undo action at `key`: the index of the newest in their list,
-- or nil.
local function pending_at(player_index, wanted)
  local pending = storage.undo_pending and storage.undo_pending[player_index]
  for index = #(pending or {}), 1, -1 do
    if pending[index].key == wanted then
      return index
    end
  end
end

-- A player undid something: removals of ours come back as ghosts, which get the settings their
-- undo action kept (or, undone before it was tagged and a ghost came back, the settings waiting for
-- it: a cancelled deconstruction brings none back, and leaves those for their own action). One whose
-- removal hadn't happened yet (deconstruction cancelled) still has them, and no ghost.
function undo.on_undo_applied(event)
  for _, action in pairs(event.actions or {}) do
    local target = action.type == "removed-entity" and action.surface_index and action.target
    local kept = target and action.tags and action.tags[TAG]
    local waiting = target
      and not kept
      and pending_at(event.player_index, key(action.surface_index, target.name, target.position))
    -- Only ours with something to keep (not a monitor or depot as every new one is, nor anything
    -- else undone) is looked for.
    local surface = (kept and next(kept) ~= nil or waiting) and game.surfaces[action.surface_index]
    local ghost
    for _, found in
      pairs(surface and surface.find_entities_filtered({ ghost_name = target.name, position = target.position }) or {})
    do
      if found.position.x == target.position.x and found.position.y == target.position.y then
        ghost = found
      end
    end
    local settings = ghost and (kept or table.remove(storage.undo_pending[event.player_index], waiting).tags)
    if settings and next(settings) ~= nil then
      local tags = ghost.tags or {}
      for name, value in pairs(settings) do
        tags[name] = value
      end
      ghost.tags = tags
    end
  end
end

return undo
