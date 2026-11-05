-- SPDX-License-Identifier: LGPL-3.0-only
-- The request panel: attached to the right of a request depot's inventory window, it chooses
-- the item to keep in stock and how many, holds the depot's freighters, and shows what the depot is
-- doing as a status light (hover it for the status in words). Buffer depots have the same panel,
-- with a priority slider at the top; provider depots have a panel with only that slider. Liquid
-- depots have the same panels, for a fluid, beside their storage tank window (a pipe window in
-- Factorio 2.1). The Fuel depot's panel shows the liquid fuel in its hidden tank, which has no
-- window of its own, with a button to flush it. Changes apply as they are made. Factorio shows the
-- panel only with these depots' windows.
--
-- The freighter slot works like an inventory slot: click with freighters in hand to put them in
-- (right-click: one), click with an empty hand to take them all (right-click: half), and
-- shift-click to move them to your inventory. It holds 100, counting freighters out on trips.
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
local FROM_BUFFERS = "jatz_request_from_buffers"
local PRIORITY = "jatz_depot_priority"
local PRIORITY_VALUE = "jatz_depot_priority_value"
local FUEL_FLUID = "jatz_fuel_fluid"
local FUEL_AMOUNT = "jatz_fuel_amount"
local FLUSH = "jatz_fuel_flush"
-- The depots with a request, freighters and status: request and buffer depots, item and liquid.
local REQUESTING = logistics.requesting
-- Liquid depots: storage tanks, whose window is a storage tank window, requesting fluids.
local LIQUID = logistics.liquid
-- Every depot's role (provider, request, buffer or fuel): all have this panel, provider depots
-- with only the priority slider, the Fuel depot with its liquid fuel.
local ROLES = logistics.depots
local PANELLED_NAMES = {}
for name in pairs(ROLES) do
  PANELLED_NAMES[#PANELLED_NAMES + 1] = name
end
table.sort(PANELLED_NAMES)
-- What the chooser offers: no hidden items or fluids, and no blueprint parameters. Fluids have no
-- "is-parameter" filter (FluidPrototypeFilter); parameter fluids are in the "parameters" subgroup.
local ITEM_FILTERS = { { filter = "hidden", invert = true }, { filter = "is-parameter", invert = true, mode = "and" } }
local FLUID_FILTERS = {
  { filter = "hidden", invert = true },
  { filter = "subgroup", subgroup = "parameters", invert = true, mode = "and" },
}
-- A new fluid request starts at this amount, as a new item request starts at one stack.
local FLUID_START = 1000

local function frame_of(player)
  return player.gui.relative[FRAME]
end

local function status_caption(entity)
  return { "jatz-request-status." .. (logistics.get_status(entity) or "none") }
end

-- The status light beside the request: the game's own status indicators, answering "can I get
-- this item?". Hovering it shows the status in words.
-- * green: stocked, or on its way (a freighter out, or finding the depot to fetch from by road);
-- * yellow: the item is there, but something is in the way (no road route right now, no
--   freighters, loading zone not on road, the depot full or its tank holding another fluid, a
--   freighter couldn't be sent);
-- * red: no depot it fetches from has the item (no provider, nor any buffer for a request depot),
--   or its freighters need fuel and no Fuel depot is connected by road;
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
  ["other-fluid"] = "utility/status_yellow",
  ["no-fuel"] = "utility/status_yellow",
  ["no-provider"] = "utility/status_not_working",
  ["no-fuel-depot"] = "utility/status_not_working",
  none = "utility/status_inactive",
}
request_gui.lights = LIGHTS

local function show_status(light, entity)
  local status = logistics.get_status(entity) or "none"
  light.sprite = LIGHTS[status] or "utility/status_inactive"
  light.tooltip = status_caption(entity)
end

-- The line beside the freighter slot, whose own number is the freighters at home: how many are
-- out on the road, always, so home and out read at a glance, and a green "+N" while N more are
-- requested (from robots, or by a pasted depot). The chest's own requested-item ghosts don't
-- redraw while the depot's window is open (Factorio's container window only draws them when
-- opened), so this is where a request that changes meanwhile shows. Everything else (freighters
-- being taken away, the slot's limit) is in the tooltip.
function request_gui.freighter_caption(out, coming)
  local caption = { "", { "jatz-gui.freighters-out", out } }
  if coming and coming > 0 then
    caption[#caption + 1] = "  [color=green]+" .. coming .. "[/color]"
  end
  return caption
end

-- Show the slot's freighters: the count on the slot, what's happening beside it, and the full
-- breakdown when hovering either.
local function show_freighters(inner, entity)
  local in_slot, out, capacity = logistics.freighter_counts(entity)
  local row = inner.freighter_row
  if not (row and in_slot) then
    return
  end
  local coming, leaving = logistics.requested_freighters(entity)
  local breakdown = { "jatz-gui.freighters", in_slot, out, coming, leaving, capacity }
  row[SLOT].number = in_slot > 0 and in_slot or nil
  row[SLOT].tooltip = { "", breakdown, "\n\n", { "jatz-gui.freighter-slot-tooltip" } }
  row[SLOT_LABEL].caption = request_gui.freighter_caption(out, coming)
  row[SLOT_LABEL].tooltip = breakdown
end

-- Show a provider or buffer depot's priority on its slider and beside it.
local function show_priority(inner, entity)
  local row = inner.priority_row
  local priority = row and logistics.get_priority(entity)
  if priority then
    row[PRIORITY].slider_value = priority
    row[PRIORITY_VALUE].caption = tostring(priority)
  end
end

-- The priority slider of provider and buffer depots: 1 to 10, higher first.
local function add_priority(inner, entity)
  local range = logistics.priority
  local row = inner.add({ type = "flow", name = "priority_row", direction = "horizontal" })
  row.style.vertical_align = "center"
  local tooltip = { "jatz-gui.priority-tooltip-" .. logistics.depots[entity.name] }
  row.add({ type = "label", caption = { "jatz-gui.priority" }, tooltip = tooltip })
  row.add({
    type = "slider",
    name = PRIORITY,
    minimum_value = range.min,
    maximum_value = range.max,
    value = logistics.get_priority(entity) or range.default,
    value_step = 1,
    discrete_values = true,
    tooltip = tooltip,
  })
  local value = row.add({ type = "label", name = PRIORITY_VALUE, tooltip = tooltip })
  value.style.minimal_width = 20
  value.style.horizontal_align = "right"
  show_priority(inner, entity)
end

-- The Fuel depot's liquid fuel: the fluid in its tank and how much, a warning if it doesn't burn.
local function show_fuel(inner, entity)
  local row = inner.fuel_row
  local contents = row and logistics.fuel_contents(entity)
  if not contents then
    return
  end
  row[FUEL_FLUID].sprite = contents.fluid and ("fluid/" .. contents.fluid) or ""
  local amount = { "jatz-gui.fuel-amount", math.floor(contents.amount + 0.5), contents.capacity }
  if contents.fluid and not contents.burnable then
    amount = { "", amount, " [color=yellow]", { "jatz-gui.fuel-not-burnable" }, "[/color]" }
  end
  row[FUEL_AMOUNT].caption = amount
end

local function add_fuel(inner, entity)
  local row = inner.add({ type = "flow", name = "fuel_row", direction = "horizontal" })
  row.style.vertical_align = "center"
  row.add({ type = "label", caption = { "jatz-gui.fuel-liquid" }, tooltip = { "jatz-gui.fuel-tooltip" } })
  row.add({ type = "sprite", name = FUEL_FLUID, tooltip = { "jatz-gui.fuel-tooltip" } })
  row.add({ type = "label", name = FUEL_AMOUNT, tooltip = { "jatz-gui.fuel-tooltip" } })
  row.add({
    type = "sprite-button",
    name = FLUSH,
    style = "tool_button_red",
    sprite = "utility/trash",
    tooltip = { "jatz-gui.fuel-flush" },
  })
  show_fuel(inner, entity)
end

local function open(player, entity)
  local old = frame_of(player)
  if old then
    old.destroy()
  end
  local frame = player.gui.relative.add({
    type = "frame",
    name = FRAME,
    caption = { "jatz-gui." .. (LIQUID[entity.name] and "liquid-" or "") .. ROLES[entity.name] .. "-title" },
    direction = "vertical",
    anchor = {
      -- Factorio 2.1 dropped storage_tank_gui: storage tanks open the pipe window. A mining
      -- depot (Mining Drones) is an assembling machine.
      gui = LIQUID[entity.name] and defines.relative_gui_type.pipe_gui
        or entity.type == "assembling-machine" and defines.relative_gui_type.assembling_machine_gui
        or defines.relative_gui_type.container_gui,
      position = defines.relative_gui_position.right,
      names = PANELLED_NAMES,
    },
  })
  local inner = frame.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  storage.request_gui = storage.request_gui or {}
  storage.request_gui[player.index] = entity
  if ROLES[entity.name] == "fuel" then
    return add_fuel(inner, entity)
  end
  -- Provider and buffer depots: the priority slider first, above the request.
  if ROLES[entity.name] ~= "request" then
    add_priority(inner, entity)
  end
  if not REQUESTING[entity.name] then
    return
  end
  local request = logistics.get_request(entity) or {}
  local row = inner.add({ type = "flow", name = "request_row", direction = "horizontal" })
  row.style.vertical_align = "center"
  row.add({
    type = "choose-elem-button",
    name = ITEM,
    elem_type = LIQUID[entity.name] and "fluid" or "item",
    item = not LIQUID[entity.name] and request.item or nil,
    fluid = LIQUID[entity.name] and request.item or nil,
    elem_filters = LIQUID[entity.name] and FLUID_FILTERS or ITEM_FILTERS,
    tooltip = { LIQUID[entity.name] and "jatz-gui.request-fluid-tooltip" or "jatz-gui.request-item-tooltip" },
  })
  local count = row.add({
    type = "textfield",
    name = COUNT,
    text = request.count and tostring(request.count) or "",
    numeric = true,
    allow_decimal = false,
    allow_negative = false,
    lose_focus_on_confirm = true,
    tooltip = { LIQUID[entity.name] and "jatz-gui.request-amount-tooltip" or "jatz-gui.request-count-tooltip" },
  })
  count.style.width = 80
  show_status(row.add({ type = "sprite", name = STATUS, style = "status_image" }), entity)
  if ROLES[entity.name] == "request" then
    -- Like a requester chest's "request from buffer chests".
    inner.add({
      type = "checkbox",
      name = FROM_BUFFERS,
      state = logistics.get_from_buffers(entity),
      caption = { "jatz-gui.request-from-buffers" },
      tooltip = { "jatz-gui.request-from-buffers-tooltip" },
    })
  end
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
end

-- The depot whose panel a player has open: any, or (`requesting`) only a request or buffer depot.
local function opened_depot(player, requesting)
  local entity = storage.request_gui and storage.request_gui[player.index]
  return entity and entity.valid and (not requesting or REQUESTING[entity.name]) and entity or nil
end

-- Freighters a player carries: in their inventory and in their cursor. Moving them between the
-- two changes nothing; putting some into a depot (from either) makes it smaller.
local function carried(player)
  local pockets = player.get_main_inventory()
  local cursor = player.cursor_stack
  local held = cursor and cursor.valid_for_read and cursor.name == logistics.freighter and cursor.count or 0
  return (pockets and logistics.count_freighters(pockets) or 0) + held, pockets
end

-- Count a player's freighters before they can move any: when they open a request depot or point
-- at one.
local function count_pockets(player)
  if player then
    storage.pocket_freighters = storage.pocket_freighters or {}
    storage.pocket_freighters[player.index] = carried(player)
  end
end

local function on_gui_opened(event)
  local entity = event.entity
  if entity and entity.valid and (ROLES[entity.name] == "provider" or ROLES[entity.name] == "fuel") then
    open(game.get_player(event.player_index), entity)
  elseif entity and entity.valid and REQUESTING[entity.name] then
    local player = game.get_player(event.player_index)
    -- Before the player can put any freighters in by hand: note what the depot's freighter
    -- requests are for, so a request Factorio drops when partly filled is asked again.
    logistics.trim_freighter_requests(entity)
    open(player, entity)
    count_pockets(player)
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
  -- A newly chosen item starts at one stack (a fluid at FLUID_START), so the request does
  -- something straight away.
  if item and amount == 0 then
    amount = LIQUID[entity.name] and FLUID_START or prototypes.item[item].stack_size
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
  if event.element.name == FLUSH then
    local entity = opened_depot(game.get_player(event.player_index))
    if entity and logistics.flush_fuel(entity) then
      show_fuel(event.element.parent.parent, entity)
    end
    return
  end
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

-- Freighters a player moves into a request depot (ctrl+click moves all of them, shift+click a
-- stack, in the depot's window; ctrl+click on the depot itself in the world; placed from the
-- cursor) go straight into its freighter slot, filling it; the rest go back to the player. How many
-- they moved is how many fewer freighters they carry (inventory and cursor) than last counted. The depot is
-- the one whose window is open, or the one the player points at (ctrl+click in the world).
-- Registered in control.lua.
function request_gui.on_selected_entity_changed(event)
  local player = game.get_player(event.player_index)
  local selected = player and player.selected
  if selected and selected.valid and REQUESTING[selected.name] then
    count_pockets(player)
  end
end

function request_gui.on_player_main_inventory_changed(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  storage.pocket_freighters = storage.pocket_freighters or {}
  local now, pockets = carried(player)
  local before = storage.pocket_freighters[event.player_index]
  storage.pocket_freighters[event.player_index] = now
  if not before or now >= before then
    return
  end
  local selected = player.selected
  local entity = opened_depot(player, true) or (selected and selected.valid and REQUESTING[selected.name] and selected)
  if entity then
    local taken = logistics.take_in_freighters(entity, pockets, before - now)
    local frame = taken > 0 and opened_depot(player, true) == entity and frame_of(player)
    if frame then
      show_freighters(frame.children[1], entity)
    end
  end
  -- Freighters given back changed the inventory again; count from here.
  storage.pocket_freighters[event.player_index] = carried(player)
end

-- A freighter placed from the cursor into a request depot's chest (onto the ghost of a requested
-- freighter, say) goes to its freighter slot at once too, so the chest slot shows the rest of the
-- request again straight away rather than at the next dispatch.
request_gui.on_player_cursor_stack_changed = request_gui.on_player_main_inventory_changed

local function on_gui_checked_state_changed(event)
  if event.element.name ~= FROM_BUFFERS then
    return
  end
  local entity = opened_depot(game.get_player(event.player_index))
  if entity then
    logistics.set_from_buffers(entity, event.element.state)
  end
end

local function on_gui_value_changed(event)
  if event.element.name ~= PRIORITY then
    return
  end
  local entity = opened_depot(game.get_player(event.player_index))
  if entity then
    logistics.set_priority(entity, event.element.slider_value)
    show_priority(event.element.parent.parent, entity)
  end
end

-- Keep the status line and priority current while the window is open.
local function refresh()
  if not storage.request_gui then
    return
  end
  for index, entity in pairs(storage.request_gui) do
    local player = game.get_player(index)
    local frame = player and player.valid and frame_of(player)
    if frame and entity.valid then
      local inner = frame.children[1]
      local requesting = REQUESTING[entity.name]
      if ROLES[entity.name] == "fuel" then
        if not inner.fuel_row then
          open(player, entity)
          inner = frame_of(player).children[1]
        end
        show_fuel(inner, entity)
      elseif
        not (inner.priority_row or ROLES[entity.name] == "request")
        or (requesting and not (inner.request_row and inner.request_row[STATUS]))
      then
        -- A panel opened before an update that changed its layout: build it again.
        open(player, entity)
        inner = frame_of(player).children[1]
      end
      if requesting then
        show_status(inner.request_row[STATUS], entity)
        show_freighters(inner, entity)
      end
      show_priority(inner, entity)
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
  script.on_event(defines.events.on_gui_checked_state_changed, on_gui_checked_state_changed)
  script.on_event(defines.events.on_gui_value_changed, on_gui_value_changed)
  script.on_event(defines.events.on_gui_hover, on_gui_hover)
  script.on_event(defines.events.on_gui_leave, on_gui_leave)
  script.on_event("jatz-pipette", on_pipette)
  script.on_nth_tick(30, refresh)
end

return request_gui
