-- SPDX-License-Identifier: LGPL-3.0-only
-- The request panel: attached to the right of a request depot's inventory window, it chooses
-- the item to keep in stock and how many, and shows what the depot is doing. Changes apply as
-- they are made. Factorio shows the panel only with request depots' windows.
local logistics = require("scripts.logistics")

local request_gui = {}

local FRAME = "jatz_request_frame"
local ITEM = "jatz_request_item"
local COUNT = "jatz_request_count"
local STATUS = "jatz_request_status"
local REQUEST = "jatz-request-depot"

local function frame_of(player)
  return player.gui.relative[FRAME]
end

local function status_caption(entity)
  return { "jatz-request-status." .. (logistics.get_status(entity) or "none") }
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
  local row = inner.add({ type = "flow", direction = "horizontal" })
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
  inner.add({ type = "label", name = STATUS, caption = status_caption(entity) })
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

-- Keep the status line current while the window is open.
local function refresh()
  if not storage.request_gui then
    return
  end
  for index, entity in pairs(storage.request_gui) do
    local player = game.get_player(index)
    local frame = player and player.valid and frame_of(player)
    if frame and entity.valid then
      local status = frame.children[1][STATUS]
      if status then
        status.caption = status_caption(entity)
      end
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
  script.on_nth_tick(30, refresh)
end

return request_gui
