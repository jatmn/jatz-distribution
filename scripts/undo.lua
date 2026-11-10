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
-- inventory say, leaves nothing waiting), tagged at the next on_tick, and an undo before then takes
-- the settings still waiting. An undo action is known only by what it holds, never by its place in
-- the history (items are pushed on top, and at the history's limit, 100 items, each new one drops
-- the oldest), so every action tagged here is marked as its entity's removal (MARK) and no other
-- removal takes it.
local logistics = require("scripts.logistics")
local legacy_depots = require("scripts.legacy-depots")

local undo = {}

-- The undo action tag holding an entity's settings tags.
local TAG = "jatz_settings"
-- The undo action tag marking whose removal an action is (its entity's unit number): set on every
-- action tagged here, so no other removal takes it, and found again by robots and platforms taking
-- a marked entity without reading undo items.
local MARK = "jatz_removal_of"
-- Settings waiting for their undo action are given up after this long (a removal that made none).
local GIVE_UP_TICKS = 60

local function action_state(marked)
  if not marked.phase then
    marked.phase = marked.action and "located" or (marked.unlocated and "unlocated" or "locating")
    marked.unlocated = nil
  end
  return marked.phase
end

local function located(marked, action)
  marked.phase, marked.action = "located", action
end

-- Configuration migration is idempotent; queue membership supplies old snapshots' phase.
function undo.migrate()
  for _, marked in pairs(storage.undo_marked or {}) do
    action_state(marked)
  end
  for _, mining in pairs(storage.undo_mining or {}) do
    mining.entry.phase = "captured"
  end
  for _, entries in pairs(storage.undo_pending or {}) do
    for _, entry in ipairs(entries) do
      entry.phase = entry.tagged and "tagged" or "pending"
      entry.tagged = nil
    end
  end
end

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

-- Whether this undo action may be `entry`'s: every action tagged here is marked with whose removal
-- it is (MARK, a unit number, never reused), and only that entity's may take it again. So a removal
-- never takes another's, at the same spot or earlier in the history, whatever was pushed or dropped.
local function may_take(action, entry)
  local mark = action.tags and action.tags[MARK]
  return mark == nil or mark == entry.unit_number
end

-- Put `entry`'s settings on this action, marked as its own (the action table too, so the rest of
-- the pass sees it taken).
local function put(stack, item, action_index, action, entry)
  stack.set_undo_tag(item, action_index, TAG, entry.tags)
  stack.set_undo_tag(item, action_index, MARK, entry.unit_number)
  action.tags = action.tags or {}
  action.tags[MARK] = entry.unit_number
end

-- Tag the undo actions of these removals (`entries`, in the order they happened) on a player's
-- stack: each its own removal action, the newest removal the newest action it may take, so several
-- at the same spot don't take each other's. Returns the entries whose action wasn't found.
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
      for index, entry in ipairs(list or {}) do
        if may_take(action, entry) then
          put(stack, item, action_index, action, table.remove(list, index))
          entry.phase, left = "tagged", left - 1
          break
        end
      end
    end
  end
  local missing = {}
  for _, entry in ipairs(entries) do
    if entry.phase ~= "tagged" then
      missing[#missing + 1] = entry
    end
  end
  return missing
end

-- Settings waiting for a player's undo action, tagged at control.lua's next on_tick.
local function wait(player_index, entries)
  if #entries == 0 then
    return
  end
  storage.undo_pending = storage.undo_pending or {}
  local pending = storage.undo_pending[player_index] or {}
  storage.undo_pending[player_index] = pending
  for _, entry in ipairs(entries) do
    entry.phase = "pending"
    pending[#pending + 1] = entry
  end
end

-- `entity`'s settings as they are now, keyed by where it stands: empty when it has none to keep,
-- which is a snapshot too (it replaces settings an earlier attempt saved, and keeps removals at one
-- spot in order).
local function note(entity)
  return {
    phase = "captured",
    unit_number = entity.unit_number,
    key = key(entity.surface_index, entity.name, entity.position),
    tags = logistics.settings_tags(entity) or {},
    tick = game.tick,
  }
end

-- A player marked a depot or monitor for deconstruction (or cut it): who, for when robots or the
-- platform take it, and its undo action to find (control.lua's on_tick: the action is made just
-- after this event, probed on 2.1.24, so by then it is there).
function undo.marked(entity, player_index)
  if player_index and entity.valid and entity.unit_number then
    storage.undo_marked = storage.undo_marked or {}
    storage.undo_marked[entity.unit_number] = {
      phase = "locating",
      player_index = player_index,
      key = key(entity.surface_index, entity.name, entity.position),
      tick = game.tick,
    }
    storage.undo_locating = true
  end
end

-- Find the undo actions of the removals marked so far, a player's all in one look through their
-- undo items (a cut of many depots is one item: read once, not once per depot), and mark each as
-- its entity's, remembering its index within its item (which never changes; the item's place in
-- the history does, as items are pushed on top and the oldest dropped at the history's limit).
local function locate(tick)
  local wanted = {}
  for unit_number, marked in pairs(storage.undo_marked or {}) do
    if action_state(marked) == "locating" then
      local by_player = wanted[marked.player_index] or {}
      wanted[marked.player_index] = by_player
      local list = by_player[marked.key] or {}
      by_player[marked.key] = list
      list[#list + 1] = unit_number
    end
  end
  storage.undo_locating = nil
  for player_index, spots in pairs(wanted) do
    local stack = undo_stack(player_index)
    local left = 0
    for _, list in pairs(spots) do
      left = left + #list
    end
    for item = 1, stack and stack.get_undo_item_count() or 0 do
      if left == 0 then
        break
      end
      for action_index, action in ipairs(stack.get_undo_item(item)) do
        local target = action.type == "removed-entity" and action.surface_index and action.target
        local list = target and spots[key(action.surface_index, target.name, target.position)]
        for index, unit_number in ipairs(list or {}) do
          if may_take(action, { unit_number = unit_number }) then
            table.remove(list, index)
            stack.set_undo_tag(item, action_index, MARK, unit_number)
            action.tags = action.tags or {}
            action.tags[MARK] = unit_number
            located(storage.undo_marked[unit_number], action_index)
            left = left - 1
            break
          end
        end
      end
    end
    -- Not found: marked later this tick (by a script after this), looked for again next tick;
    -- otherwise a removal looks for it itself.
    for _, list in pairs(spots) do
      for _, unit_number in ipairs(list) do
        local marked = storage.undo_marked[unit_number]
        if marked.tick >= tick then
          storage.undo_locating = true
        else
          marked.phase = "unlocated"
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
-- standing). Its action is the one marked as its own, at the index it was located at, in whichever
-- item of the history it is now: found by reading that one tag of each item, never the items
-- themselves. Only if it wasn't located (a platform takes it within the tick) are the player's undo
-- items read to find it.
function undo.removing_marked(entity)
  local marked = storage.undo_marked and entity.valid and storage.undo_marked[entity.unit_number]
  local stack = marked and undo_stack(marked.player_index)
  if not stack then
    return
  end
  local entry = note(entity)
  if action_state(marked) == "located" then
    for item = 1, stack.get_undo_item_count() do
      -- An item may have fewer actions: reading past them is an error, not a nil (probed).
      local ok, mark = pcall(stack.get_undo_tag, item, marked.action, MARK)
      if ok and mark == entity.unit_number then
        stack.set_undo_tag(item, marked.action, TAG, entry.tags)
        return
      end
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
    wait(player_index, { mining.entry })
  end
end

-- Locate the marked removals, then tag the undo actions of every removal waiting (control.lua's
-- on_tick, only while there are some: storage.undo_pending or undo_locating). Locating first marks
-- the actions of entities marked for deconstruction as theirs, so a removal by hand at the same spot
-- never takes one. Every removal waiting is matched at once, this tick's too: one waits only from
-- on_player_mined_entity, just after which its undo item is pushed (probed on 2.1.24), so its action
-- is there by now, and leaving it out would let an older removal at its spot take its (newer)
-- action, newest to newest.
function undo.tag_pending(tick)
  if storage.undo_locating then
    locate(tick)
  end
  for player_index, pending in pairs(storage.undo_pending or {}) do
    -- Older than GIVE_UP_TICKS: given up, never tagged late.
    local due = {}
    for _, entry in ipairs(pending) do
      if tick - entry.tick < GIVE_UP_TICKS then
        due[#due + 1] = entry
      else
        entry.phase = "expired"
      end
    end
    local stack = undo_stack(player_index)
    -- Not found: looked for again next tick, until given up.
    local waiting = {}
    for _, entry in ipairs(stack and tag(stack, due) or due) do
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
    -- A removal from before item provider and buffer depots were logistic containers names the
    -- legacy depot, whose ghost may already have been replaced by the depot's (scripts/legacy-depots.lua).
    local replaced = target and legacy_depots.replacement[target.name]
    local names = replaced and { target.name, replaced } or (target and target.name)
    for _, found in
      pairs(surface and surface.find_entities_filtered({ ghost_name = names, position = target.position }) or {})
    do
      if found.position.x == target.position.x and found.position.y == target.position.y then
        ghost = found
      end
    end
    local settings = ghost and kept
    if ghost and not kept and waiting then
      local entry = table.remove(storage.undo_pending[event.player_index], waiting)
      entry.phase = "consumed"
      settings = entry.tags
    end
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
