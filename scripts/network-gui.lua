-- SPDX-License-Identifier: LGPL-3.0-only
-- The freighter network window (the owner's request, November 15, 2026), opened and closed by the
-- shortcut bar's button (prototypes/shortcut.lua): for the player's force, how many freighters
-- there are (in request and buffer depots' slots and out on the road) and how many are out, how
-- many depots of each kind, and what provider and buffer depots hold, items and fluids, as the
-- logistic network window shows what its chests hold. All surfaces together, or one: with Space
-- Age, or whenever the force has depots on more than one surface, a drop-down picks a planet or a
-- space platform. Counted when it opens, when its player changes force, and again once a second
-- while it is open (control.lua's on_nth_tick calls `refresh`), and never while nobody has it
-- open. It is the player's opened GUI, so E and Esc close it too. scripts/request-gui.lua passes
-- the GUI events on to it (control.lua keeps one handler per event).
local logistics = require("scripts.logistics")

local network_gui = {}

local SHORTCUT = "jatz-network"
network_gui.shortcut = SHORTCUT
local FRAME = "jatz_network_frame"
local CLOSE = "jatz_network_close"
local SURFACE = "jatz_network_surface"
local ITEM_COLUMNS = 10
-- The depots in the crafting menu's order; any other (Mining Drones' mining depot) after them.
local KINDS = {
  "jatz-provider-depot",
  "jatz-request-depot",
  "jatz-buffer-depot",
  "jatz-liquid-provider-depot",
  "jatz-liquid-request-depot",
  "jatz-liquid-buffer-depot",
  "jatz-fuel-depot",
}
do
  local listed, others = {}, {}
  for _, name in ipairs(KINDS) do
    listed[name] = true
  end
  for name in pairs(logistics.depots) do
    if not listed[name] then
      others[#others + 1] = name
    end
  end
  table.sort(others)
  for _, name in ipairs(others) do
    KINDS[#KINDS + 1] = name
  end
end

local function new_counts()
  return { freighters = 0, active = 0, depots = {}, items = {} }
end

-- What a force's depots and freighters come to: `all` of them, and by surface index (`surfaces`,
-- only surfaces where it has depots). Each has `freighters` (in requesting depots' slots and out),
-- `active` (out), `depots` (counts by entity name) and `items` (what provider and buffer depots
-- hold, by "item/<name>/<quality>" or "fluid/<name>": { type, name, quality, count }).
function network_gui.count(force)
  local all = new_counts()
  local surfaces = {}
  for _, depot in pairs(storage.depots or {}) do
    local entity = depot.entity
    if entity.valid and entity.force == force then
      local surface = surfaces[entity.surface_index]
      if not surface then
        surface = new_counts()
        surfaces[entity.surface_index] = surface
      end
      local name = entity.name
      local home, out
      if logistics.requesting[name] then
        home, out = logistics.freighter_counts(entity)
      end
      home, out = home or 0, out or 0
      local held = {}
      if depot.role == "provider" or depot.role == "buffer" then
        if depot.fluid then
          for fluid, amount in pairs(entity.get_fluid_contents()) do
            held[#held + 1] = { type = "fluid", name = fluid, count = amount }
          end
        else
          for _, item in ipairs(logistics.inventory(entity).get_contents()) do
            held[#held + 1] = { type = "item", name = item.name, quality = item.quality, count = item.count }
          end
        end
      end
      for _, counts in ipairs({ all, surface }) do
        counts.depots[name] = (counts.depots[name] or 0) + 1
        counts.freighters = counts.freighters + home + out
        counts.active = counts.active + out
        for _, item in ipairs(held) do
          local key = item.type .. "/" .. item.name .. (item.quality and "/" .. item.quality or "")
          local total = counts.items[key]
          if not total then
            total = { type = item.type, name = item.name, quality = item.quality, count = 0 }
            counts.items[key] = total
          end
          total.count = total.count + item.count
        end
      end
    end
  end
  return { all = all, surfaces = surfaces }
end

-- A surface's name as players know it: its planet's, or its space platform's.
local function surface_caption(surface)
  local platform = surface.platform
  if platform then
    return platform.name
  end
  local planet = surface.planet
  if planet then
    return { "", "[planet=" .. planet.name .. "] ", planet.prototype.localised_name }
  end
  return surface.localised_name or surface.name
end

local function frame_of(player)
  return player.gui.screen[FRAME]
end

local function close(player)
  local frame = frame_of(player)
  if frame then
    frame.destroy()
  end
  if storage.network_gui then
    storage.network_gui[player.index] = nil
  end
  player.set_shortcut_toggled(SHORTCUT, false)
end

-- The window's numbers, from a force's `counts` (network_gui.count).
local function show(player, frame, counts)
  local state = storage.network_gui[player.index]
  local inner = frame.inner
  -- Surfaces in the drop-down: those where the force has depots, in the order they were made.
  local listed = {}
  for index in pairs(counts.surfaces) do
    local surface = game.surfaces[index]
    if surface and surface.valid then
      listed[#listed + 1] = index
    end
  end
  table.sort(listed)
  local selected
  local items = { { "jatz-network.all-surfaces" } }
  -- The surfaces and platform names listed, to tell when the drop-down's items change.
  local keys = {}
  for position, index in ipairs(listed) do
    local surface = game.surfaces[index]
    items[#items + 1] = surface_caption(surface)
    keys[position] = index .. ":" .. (surface.platform and surface.platform.name or "")
    if index == state.surface then
      selected = position + 1
    end
  end
  local key = table.concat(keys, ",")
  if not selected then
    state.surface = nil
  end
  local dropdown = inner[SURFACE]
  dropdown.visible = #listed > 1 or script.active_mods["space-age"] ~= nil
  -- Set again only when the surfaces change, so a list a player has open stays open.
  if state.key ~= key then
    dropdown.items = items
    state.key = key
  end
  state.listed = listed
  dropdown.selected_index = selected or 1
  local shown = state.surface and counts.surfaces[state.surface] or counts.all

  local freighters = inner.freighters
  freighters.total.caption = tostring(shown.freighters)
  freighters.active.caption = tostring(shown.active)
  for _, name in ipairs(KINDS) do
    local count = inner.depots[name]
    if count then
      count.caption = tostring(shown.depots[name] or 0)
    end
  end

  -- What provider and buffer depots hold, most first, one slot button each, reused as they are.
  -- Intentional: less than 1 (a fluid's leftover in a tank) isn't listed; it would read 0, as a
  -- tank's circuit output floors it, and no freighter loads it (logistics.least_fluid).
  local held = {}
  for _, item in pairs(shown.items) do
    if item.count >= 1 then
      held[#held + 1] = item
    end
  end
  table.sort(held, function(a, b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    if a.type ~= b.type then
      return a.type < b.type
    end
    if a.name ~= b.name then
      return a.name < b.name
    end
    return (a.quality or "") < (b.quality or "")
  end)
  local slots = inner.items_frame.items_pane.item_slots
  local buttons = slots.children
  for position, item in ipairs(held) do
    local button = buttons[position]
    if not button then
      button = slots.add({ type = "sprite-button", style = "slot_button" })
    end
    button.sprite = item.type .. "/" .. item.name
    button.number = math.floor(item.count)
    if item.type == "item" then
      button.quality = item.quality
      button.elem_tooltip = { type = "item-with-quality", name = item.name, quality = item.quality }
    else
      button.quality = nil
      button.elem_tooltip = { type = "fluid", name = item.name }
    end
  end
  for position = #buttons, #held + 1, -1 do
    buttons[position].destroy()
  end
  inner.no_items.visible = #held == 0
end

function network_gui.open(player)
  local old = frame_of(player)
  if old then
    old.destroy()
  end
  storage.network_gui = storage.network_gui or {}
  storage.network_gui[player.index] = {}
  local frame = player.gui.screen.add({ type = "frame", name = FRAME, direction = "vertical" })
  frame.auto_center = true
  local titlebar = frame.add({ type = "flow", direction = "horizontal" })
  titlebar.drag_target = frame
  titlebar.add({
    type = "label",
    caption = { "jatz-network.title" },
    style = "frame_title",
    ignored_by_interaction = true,
  })
  local handle =
    titlebar.add({ type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true })
  handle.style.height = 24
  handle.style.horizontally_stretchable = true
  titlebar.add({
    type = "sprite-button",
    name = CLOSE,
    style = "frame_action_button",
    sprite = "utility/close",
    tooltip = { "gui.close-instruction" },
  })
  local inner = frame.add({
    type = "frame",
    name = "inner",
    style = "inside_shallow_frame_with_padding",
    direction = "vertical",
  })
  inner.add({ type = "drop-down", name = SURFACE })
  local freighters = inner.add({ type = "table", name = "freighters", column_count = 2 })
  freighters.add({
    type = "label",
    caption = { "jatz-network.freighters" },
    tooltip = { "jatz-network.freighters-tooltip" },
  })
  freighters.add({ type = "label", name = "total" })
  freighters.add({ type = "label", caption = { "jatz-network.active" }, tooltip = { "jatz-network.active-tooltip" } })
  freighters.add({ type = "label", name = "active" })
  inner.add({ type = "label", caption = { "jatz-network.depots" }, style = "caption_label" })
  local depots = inner.add({ type = "table", name = "depots", column_count = 3 })
  for _, name in ipairs(KINDS) do
    local prototype = prototypes.entity[name]
    if prototype then
      depots.add({ type = "sprite", sprite = "entity/" .. name })
      depots.add({ type = "label", caption = prototype.localised_name })
      depots.add({ type = "label", name = name })
    end
  end
  inner.add({
    type = "label",
    caption = { "jatz-network.items" },
    tooltip = { "jatz-network.items-tooltip" },
    style = "caption_label",
  })
  inner.add({ type = "label", name = "no_items", caption = { "jatz-network.no-items" } })
  local pane = inner
    .add({ type = "frame", name = "items_frame", style = "inside_deep_frame" })
    .add({ type = "scroll-pane", name = "items_pane", style = "deep_slots_scroll_pane" })
  pane.style.maximal_height = 400
  pane.add({ type = "table", name = "item_slots", style = "slot_table", column_count = ITEM_COLUMNS })
  show(player, frame, network_gui.count(player.force))
  player.opened = frame
  player.set_shortcut_toggled(SHORTCUT, true)
end

-- The shortcut: opens the window, or closes it if open. Returns whether it was ours.
function network_gui.on_lua_shortcut(event)
  if event.prototype_name ~= SHORTCUT then
    return false
  end
  local player = game.get_player(event.player_index)
  if player then
    if frame_of(player) then
      close(player)
    else
      network_gui.open(player)
    end
  end
  return true
end

-- The window closed (E, Esc or opening something else). Returns whether it was ours.
function network_gui.on_gui_closed(event)
  local element = event.element
  if not (element and element.valid and element.name == FRAME) then
    return false
  end
  local player = game.get_player(event.player_index)
  if player then
    close(player)
  end
  return true
end

-- Its close button. Returns whether the click was ours.
function network_gui.on_gui_click(event)
  if event.element.name ~= CLOSE then
    return false
  end
  local player = game.get_player(event.player_index)
  if player then
    close(player)
  end
  return true
end

-- A surface chosen, or all of them. Returns whether the event was ours.
function network_gui.on_gui_selection_state_changed(event)
  local element = event.element
  if element.name ~= SURFACE then
    return false
  end
  local player = game.get_player(event.player_index)
  local state = storage.network_gui and storage.network_gui[event.player_index]
  local frame = player and frame_of(player)
  if state and frame then
    state.surface = state.listed and state.listed[element.selected_index - 1] or nil
    show(player, frame, network_gui.count(player.force))
  end
  return true
end

-- A player moved to another force (a script setting LuaPlayer.force, or game.merge_forces): their
-- open window shows that force's network at once, not the old one's until the next count.
function network_gui.on_player_changed_force(event)
  local player = game.get_player(event.player_index)
  local frame = player and frame_of(player)
  if frame and storage.network_gui and storage.network_gui[player.index] then
    show(player, frame, network_gui.count(player.force))
  end
end

-- Once a second: every open window of a player in the game shows the numbers as they are now,
-- counted once per force.
function network_gui.refresh()
  if not (storage.network_gui and next(storage.network_gui)) then
    return
  end
  local by_force = {}
  for index in pairs(storage.network_gui) do
    local player = game.get_player(index)
    local frame = player and player.valid and frame_of(player)
    if not frame then
      -- Gone without passing through `close` (another mod's script destroyed it, and an
      -- on_gui_closed for it, if any, has only an invalid element): closed now, button unlit too.
      if player and player.valid then
        close(player)
      else
        storage.network_gui[index] = nil
      end
    elseif player.connected then
      local force = player.force
      local counts = by_force[force.index]
      if not counts then
        counts = network_gui.count(force)
        by_force[force.index] = counts
      end
      show(player, frame, counts)
    end
    -- A player out of the game keeps theirs, shown again within a second of coming back.
  end
end

return network_gui
