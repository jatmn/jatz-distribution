-- SPDX-License-Identifier: LGPL-3.0-only
-- The request panel: attached to the right of a request depot's inventory window, it chooses
-- the item to keep in stock and how many, holds the depot's freighters, and shows what the depot is
-- doing as a status light (hover it for the status in words). Changes apply as they are made. Factorio shows the panel only with request depots'
-- windows.
--
-- The freighter slot works like an inventory slot: click with freighters in hand to put them in
-- (right-click: one), click with an empty hand to take them all (right-click: half), and
-- shift-click to move them to your inventory. It holds one stack, counting freighters out on trips.
-- With a freighter ghost in the cursor (remote view, or no freighters in hand), clicking asks
-- construction robots to bring freighters instead (right-click: one more). In remote view, where
-- items can't be moved by hand, a click with an empty cursor cancels those requests, and a
-- right-click has robots take the slot's freighters away (again: cancel that). Pipette (Q) over
-- the slot picks up a freighter, or its ghost, as over any inventory slot.
local logistics = require("scripts.logistics")

local request_gui = {}

local FRAME = "jatz_request_frame"
local ITEM = "jatz_request_item"
local COUNT = "jatz_request_count"
local STATUS = "jatz_request_status"
local SLOT = "jatz_request_freighters"
local SLOT_LABEL = "jatz_request_freighters_label"
local REQUEST = "jatz-request-depot"

local function frame_of(player)
  return player.gui.relative[FRAME]
end

local function status_caption(entity)
  return { "jatz-request-status." .. (logistics.get_status(entity) or "none") }
end

-- The status light beside the request: the game's own status indicators, answering "can I get
-- this item?". Hovering it shows the status in words.
-- * green: stocked, or on its way (a freighter out, or finding the provider nearest by road);
-- * yellow: the item is there, but something is in the way (no road route right now, no
--   freighters, loading zone not on road, the depot full, a freighter couldn't be sent);
-- * red: no provider depot has the item;
-- * grey: nothing requested.
local LIGHTS = {
  satisfied = "utility/status_working",
  delivering = "utility/status_working",
  searching = "utility/status_working",
  unreachable = "utility/status_yellow",
  ["no-trucks"] = "utility/status_yellow",
  ["no-road"] = "utility/status_yellow",
  full = "utility/status_yellow",
  ["no-freighter"] = "utility/status_yellow",
  ["no-provider"] = "utility/status_not_working",
  none = "utility/status_inactive",
}
request_gui.lights = LIGHTS

local function show_status(light, entity)
  local status = logistics.get_status(entity) or "none"
  light.sprite = LIGHTS[status] or "utility/status_inactive"
  light.tooltip = status_caption(entity)
end

-- Show the slot's freighters and how many are out.
local function show_freighters(inner, entity)
  local in_slot, out, capacity = logistics.freighter_counts(entity)
  local row = inner.freighter_row
  if not (row and in_slot) then
    return
  end
  row[SLOT].number = in_slot > 0 and in_slot or nil
  local requested, removing = logistics.requested_freighters(entity)
  row[SLOT_LABEL].caption = { "jatz-gui.freighters", in_slot, out, requested, removing, capacity }
end

local function open(player, entity)
  local old = frame_of(player)
  if old then
    old.destroy()
  end
  local request = logistics.get_request(entity) or {}
  local frame = player.gui.relative.add({
    type = "frame",
    name = FRAME,
    caption = { "jatz-gui.request-title" },
    direction = "vertical",
    anchor = {
      gui = defines.relative_gui_type.container_gui,
      position = defines.relative_gui_position.right,
      names = { REQUEST },
    },
  })
  local inner = frame.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  local row = inner.add({ type = "flow", name = "request_row", direction = "horizontal" })
  row.style.vertical_align = "center"
  row.add({
    type = "choose-elem-button",
    name = ITEM,
    elem_type = "item",
    item = request.item,
    elem_filters = { { filter = "hidden", invert = true }, { filter = "is-parameter", invert = true, mode = "and" } },
    tooltip = { "jatz-gui.request-item-tooltip" },
  })
  local count = row.add({
    type = "textfield",
    name = COUNT,
    text = request.count and tostring(request.count) or "",
    numeric = true,
    allow_decimal = false,
    allow_negative = false,
    lose_focus_on_confirm = true,
    tooltip = { "jatz-gui.request-count-tooltip" },
  })
  count.style.width = 80
  show_status(row.add({ type = "sprite", name = STATUS, style = "status_image" }), entity)
  local freighters = inner.add({ type = "flow", name = "freighter_row", direction = "horizontal" })
  freighters.style.vertical_align = "center"
  freighters.add({
    type = "sprite-button",
    name = SLOT,
    style = "inventory_slot",
    sprite = "item/" .. logistics.freighter,
    tooltip = { "jatz-gui.freighter-slot-tooltip" },
    -- The freighter's own tooltip, and hover events so pipette works over the slot.
    elem_tooltip = { type = "item", name = logistics.freighter },
    raise_hover_events = true,
  })
  freighters.add({ type = "label", name = SLOT_LABEL })
  show_freighters(inner, entity)
  storage.request_gui = storage.request_gui or {}
  storage.request_gui[player.index] = entity
end

local function opened_depot(player)
  local entity = storage.request_gui and storage.request_gui[player.index]
  return entity and entity.valid and entity or nil
end

local function on_gui_opened(event)
  local entity = event.entity
  if entity and entity.valid and entity.name == REQUEST then
    open(game.get_player(event.player_index), entity)
  end
end

local function on_gui_closed(event)
  if event.entity and storage.request_gui then
    storage.request_gui[event.player_index] = nil
  end
  if storage.slot_hovered then
    storage.slot_hovered[event.player_index] = nil
  end
end

local function on_gui_elem_changed(event)
  if event.element.name ~= ITEM then
    return
  end
  local player = game.get_player(event.player_index)
  local entity = opened_depot(player)
  if not entity then
    return
  end
  local item = event.element.elem_value
  local field = event.element.parent[COUNT]
  local amount = tonumber(field.text) or 0
  -- A newly chosen item starts at one stack, so the request does something straight away.
  if item and amount == 0 then
    amount = prototypes.item[item].stack_size
    field.text = tostring(amount)
  end
  logistics.set_request(entity, item, amount)
end

local function on_gui_text_changed(event)
  if event.element.name ~= COUNT then
    return
  end
  local player = game.get_player(event.player_index)
  local entity = opened_depot(player)
  local request = entity and logistics.get_request(entity)
  if request then
    logistics.set_request(entity, request.item, tonumber(event.text) or 0)
  end
end

-- The freighter slot clicked: put freighters in from the cursor, or take them out.
local function on_gui_click(event)
  if event.element.name ~= SLOT then
    return
  end
  local player = game.get_player(event.player_index)
  local entity = opened_depot(player)
  local cursor = player.cursor_stack
  if not (entity and cursor) then
    return
  end
  local right = event.button == defines.mouse_button_type.right
  local ghost = player.cursor_ghost
  local ghost_name = ghost and (type(ghost.name) == "string" and ghost.name or ghost.name.name)
  if ghost_name == logistics.freighter then
    -- A freighter ghost in the cursor: robots bring them.
    logistics.request_freighters(entity, right and 1 or nil)
  elseif player.controller_type == defines.controllers.remote then
    -- Remote view: no items move by hand from afar. Robots do it: right-click has them take the
    -- slot's freighters away (or cancels that), a click cancels freighters requested.
    if cursor.valid_for_read then
      return
    elseif right then
      local _, removing = logistics.requested_freighters(entity)
      if removing > 0 then
        logistics.cancel_freighter_removal(entity)
      else
        logistics.remove_freighters(entity)
      end
    else
      logistics.cancel_freighter_requests(entity)
    end
  elseif event.shift then
    logistics.take_freighters(entity, nil, nil, player.get_main_inventory())
  elseif cursor.valid_for_read then
    logistics.put_freighters(entity, cursor, right and 1 or nil)
  else
    local in_slot = logistics.freighter_counts(entity)
    logistics.take_freighters(entity, cursor, right and math.ceil(in_slot / 2) or nil)
  end
  show_freighters(event.element.parent.parent, entity)
end

-- Which players have the pointer over the freighter slot, for pipette.
local function on_gui_hover(event)
  if event.element.name == SLOT then
    storage.slot_hovered = storage.slot_hovered or {}
    storage.slot_hovered[event.player_index] = true
  end
end

local function on_gui_leave(event)
  if event.element.name == SLOT and storage.slot_hovered then
    storage.slot_hovered[event.player_index] = nil
  end
end

-- Pipette over the freighter slot: a freighter from the inventory, or its ghost if there is none
-- (as in remote view), like pipette over any inventory slot.
local function on_pipette(event)
  local player = game.get_player(event.player_index)
  if storage.slot_hovered and storage.slot_hovered[event.player_index] and opened_depot(player) then
    player.pipette(prototypes.item[logistics.freighter], nil, true)
  end
end

-- Keep the status line current while the window is open.
local function refresh()
  if not storage.request_gui then
    return
  end
  for index, entity in pairs(storage.request_gui) do
    local player = game.get_player(index)
    local frame = player and player.valid and frame_of(player)
    if frame and entity.valid then
      local row = frame.children[1].request_row
      if row and row[STATUS] then
        show_status(row[STATUS], entity)
      end
      show_freighters(frame.children[1], entity)
    else
      storage.request_gui[index] = nil
    end
  end
end

function request_gui.register()
  script.on_event(defines.events.on_gui_opened, on_gui_opened)
  script.on_event(defines.events.on_gui_closed, on_gui_closed)
  script.on_event(defines.events.on_gui_elem_changed, on_gui_elem_changed)
  script.on_event(defines.events.on_gui_text_changed, on_gui_text_changed)
  script.on_event(defines.events.on_gui_click, on_gui_click)
  script.on_event(defines.events.on_gui_hover, on_gui_hover)
  script.on_event(defines.events.on_gui_leave, on_gui_leave)
  script.on_event("jatz-pipette", on_pipette)
  script.on_nth_tick(30, refresh)
end

return request_gui
