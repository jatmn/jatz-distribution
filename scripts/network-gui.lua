-- SPDX-License-Identifier: LGPL-3.0-only
-- A sampled command center, shared by connected viewers. Inventory work is spread across ticks;
-- only one bounded page is rendered per tick. No snapshots survive the last connected viewer.
local logistics = require("scripts.logistics")
local ledger = require("scripts.promises")
local quality = require("scripts.quality")
local network_gui = {}
local SHORTCUT, FRAME = "jatz-network", "jatz_network_frame"
local CLOSE, SURFACE = "jatz_network_close", "jatz_network_surface"
local TABS, FILTER = "jatz_network_tabs", "jatz_network_filter"
local PREVIOUS, NEXT = "jatz_network_previous", "jatz_network_next"
local INTERVAL, PER_TICK, PAGE_SIZE = 300, 8, 8
local ROLES = { "provider", "request", "buffer" }
local CONTENT_WIDTH, ROW_WIDTH, SLOT_SIZE, ROLE_WIDTH, NEED_WIDTH = 760, 744, 48, 176, 120
-- Each role spans a stock column and a depot-count column; every number has its own fixed,
-- right-aligned column so values line up from row to row whatever their width.
local RESOURCE_SIZE, HEADER_DEPOT_SIZE, STOCK_WIDTH, COUNT_WIDTH, GAP = 40, 32, 104, 64, 8
-- Bumped whenever the window's element tree changes, so a window saved by an older build rebuilds.
local LAYOUT = 6
network_gui.shortcut = SHORTCUT
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

local function role_counts()
  return { held = 0, depots = 0, offered = 0, offers = 0, requested = 0, target = 0, missing = 0, grades = {} }
end

-- Read each depot once. Stored fluid in parked freighters is held, but cannot be offered to
-- another depot. Configured requests count even when paused; missing counts active demand only.
local function count_depot(counts, depot)
  local entity, role = depot.entity, depot.role
  local surface = counts.surfaces[entity.surface_index]
  if not surface then
    surface = new_counts()
    counts.surfaces[entity.surface_index] = surface
  end
  local home, out = 0, 0
  if logistics.requesting[entity.name] then
    home, out = logistics.freighter_counts(entity)
  end
  local resources = {}
  local function resource(name)
    if not resources[name] then
      resources[name] = role_counts()
    end
    return resources[name]
  end
  if role == "provider" or role == "request" or role == "buffer" then
    local on = not entity.to_be_deconstructed() and logistics.enabled(depot)
    local offers = role ~= "request" and on and logistics.enabled(depot, true)
    if depot.fluid then
      for name, amount in pairs(entity.get_fluid_contents()) do
        local r = resource(name)
        r.held = r.held + amount
        if offers then
          r.offered = math.max(0, ledger.available(depot, name))
        end
      end
      local reserve = depot.reserve
      if reserve and reserve.amount > 0 then
        local r = resource(reserve.name)
        r.held = r.held + reserve.amount
      end
    else
      for _, item in ipairs(logistics.inventory(entity).get_contents()) do
        local r, grade = resource(item.name), item.quality or "normal"
        r.held = r.held + item.count
        r.grades[grade] = (r.grades[grade] or 0) + item.count
        if offers then
          r.offered = r.offered + math.max(0, ledger.available(depot, quality.key(item.name, grade)))
        end
      end
    end
    local request = depot.request
    if role ~= "provider" and request and request.count > 0 then
      local r = resource(request.item)
      r.requested, r.target = 1, request.count
      r.missing = on and logistics.missing(depot) or 0
    end
  end
  for _, total in ipairs({ counts.all, surface }) do
    total.depots[entity.name] = (total.depots[entity.name] or 0) + 1
    total.freighters, total.active = total.freighters + home + out, total.active + out
    for name, r in pairs(resources) do
      local kind = depot.fluid and "fluid" or "item"
      local key = kind .. "/" .. name
      local item = total.items[key]
      if not item then
        item = { type = kind, name = name, provider = role_counts(), request = role_counts(), buffer = role_counts() }
        total.items[key] = item
      end
      local target = item[role]
      for _, field in ipairs({ "held", "offered", "requested", "target", "missing" }) do
        target[field] = target[field] + r[field]
      end
      if r.held > 0 then
        target.depots = target.depots + 1
      end
      if r.offered >= 1 then
        target.offers = target.offers + 1
      end
      for grade, amount in pairs(r.grades) do
        target.grades[grade] = (target.grades[grade] or 0) + amount
      end
    end
  end
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
  if not (storage.network_gui and next(storage.network_gui)) then
    storage.network_scan, storage.network_data, storage.network_next, storage.network_viewer = nil, nil, nil, nil
  end
end

local function amount(number)
  return tostring(math.floor(number))
end

-- Short like the game's own slot counts (63.8k, 190k, 1.2M); the exact amount is in the tooltip.
-- Zero is a dash, so the numbers that matter stand out.
local function short(number)
  number = math.floor(number)
  if number == 0 then
    return "–"
  elseif number < 10000 then
    return tostring(number)
  end
  for _, unit in ipairs({ { 1e9, "G" }, { 1e6, "M" }, { 1e3, "k" } }) do
    if number >= unit[1] then
      local value = number / unit[1]
      if value < 100 then
        value = math.floor(value * 10) / 10
        return (value % 1 == 0 and string.format("%d", value) or string.format("%.1f", value)) .. unit[2]
      end
      return string.format("%d", math.floor(value)) .. unit[2]
    end
  end
end

local function held_tooltip(r)
  local tip = { "", { "jatz-network.held-tooltip", amount(r.held), r.depots } }
  local grades = {}
  for grade in pairs(r.grades) do
    grades[#grades + 1] = grade
  end
  table.sort(grades)
  for _, grade in ipairs(grades) do
    -- Nest instead of exceeding LocalisedString's parameter limit with modded qualities.
    tip = { "", tip, "\n", quality.icon(grade), " ", amount(r.grades[grade]) }
  end
  return tip
end

local function show(player, frame, counts)
  -- A window saved by an earlier build of the same version can still have another hierarchy.
  if frame.tags.layout ~= LAYOUT then
    network_gui.open(player)
    return
  end
  local state, inner = storage.network_gui[player.index], frame.inner
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
  local dropdown = inner.controls[SURFACE]
  dropdown.visible = #listed > 1 or script.active_mods["space-age"] ~= nil
  -- Set again only when the surfaces change, so a list a player has open stays open.
  if state.key ~= key then
    dropdown.items = items
    state.key = key
  end
  state.listed = listed
  dropdown.selected_index = selected or 1
  local shown = state.surface and counts.surfaces[state.surface] or counts.all

  local overview = inner.overview
  local freighters = overview.freighters
  local fleet = freighters.fleet
  fleet.total.caption = tostring(shown.freighters)
  freighters.on_road.count.caption = tostring(shown.active)
  local depots = overview.depot_summary.depots
  local support = overview.support.depots
  for index, name in ipairs(KINDS) do
    local summary = (index >= 7 and support or depots)[name]
    if summary then
      local total = shown.depots[name] or 0
      local count, caption = summary.count, tostring(total)
      if count.caption ~= caption then
        local tooltip = { "jatz-network.depot-tooltip", prototypes.entity[name].localised_name, total }
        count.caption, count.tooltip = caption, tooltip
        summary.tooltip, summary.icon.tooltip = tooltip, tooltip
      end
    end
  end

  local paging, tabs = inner.paging, inner[TABS]
  paging.snapshot.caption = { "jatz-network.snapshot", math.floor((game.tick - counts.tick) / 60) }
  local kind = tabs.selected_tab_index == 2 and "fluid" or "item"
  local content = tabs[kind .. "_content"]
  local rows = {}
  local totals = { item = 0, fluid = 0 }
  for _, item in pairs(shown.items) do
    local held = item.provider.held + item.request.held + item.buffer.held
    local requests = item.request.requested + item.buffer.requested
    local missing = item.request.missing + item.buffer.missing
    if held >= 1 or requests > 0 then
      totals[item.type] = totals[item.type] + 1
      if
        item.type == kind
        and (not state[kind] or item.name == state[kind])
        and (
          state.filter == 1
          or (state.filter == 2 and missing >= 1)
          or (state.filter == 3 and requests == 0 and held >= 1)
        )
      then
        rows[#rows + 1] = item
      end
    end
  end
  for _, t in ipairs({ "item", "fluid" }) do
    tabs[t .. "_tab"].badge_text = tostring(totals[t])
  end
  table.sort(rows, function(a, b)
    local ma, mb = a.request.missing + a.buffer.missing, b.request.missing + b.buffer.missing
    if ma ~= mb then
      return ma > mb
    end
    return a.name < b.name
  end)
  local pages = math.max(1, math.ceil(#rows / PAGE_SIZE))
  state.page = math.min(state.page or 1, pages)
  paging.page_label.caption = { "jatz-network.page", state.page, pages }
  paging[PREVIOUS].enabled, paging[NEXT].enabled = state.page > 1, state.page < pages
  content.no_items.visible = #rows == 0
  local resource_rows = content.resource_rows
  for index = 1, PAGE_SIZE do
    local group = resource_rows["row_" .. index]
    local item = rows[(state.page - 1) * PAGE_SIZE + index]
    group.visible = item ~= nil
    if item then
      local row = group.cells
      local prototype = prototypes[item.type][item.name]
      local resource = row.resource_icon
      resource.sprite = item.type .. "/" .. item.name
      resource.tooltip = { "", prototype.localised_name, "\n", { "jatz-network.resource-tooltip" } }
      for _, role in ipairs(ROLES) do
        local r = item[role]
        local stock = row[role .. "_stock"]
        stock.caption = short(r.held)
        stock.tooltip = held_tooltip(r)
        -- Providers: depots holding it. Requesters and buffers: depots requesting it.
        local count = row[role .. "_count"]
        if role == "provider" then
          count.caption = short(r.depots)
          count.tooltip = { "jatz-network.offering-tooltip", r.depots, r.offers, amount(r.offered) }
        else
          count.caption = short(r.requested)
          local tip = { "jatz-network.requesting-tooltip", r.requested, amount(r.target), amount(r.missing), r.depots }
          tip = role == "buffer" and { "jatz-network.buffer-requesting-tooltip", tip, r.offers, amount(r.offered) }
            or tip
          count.tooltip = tip
        end
      end
      local missing = item.request.missing + item.buffer.missing
      local needed = row.needed
      needed.caption = short(missing)
      needed.style.font_color = missing >= 1 and { 1, 0.75, 0.3 } or { 0.7, 0.7, 0.7 }
      needed.tooltip = { "jatz-network.needed-tooltip", amount(item.request.missing), amount(item.buffer.missing) }
    end
  end
  state.shown = counts.tick
  state.age = math.floor((game.tick - counts.tick) / 60)
end

local function show_cached(player)
  local counts = storage.network_data and storage.network_data[player.force.index]
  local frame = frame_of(player)
  if counts and frame then
    show(player, frame, counts)
  end
end

local function label(parent, caption, width)
  local e = parent.add({ type = "label", caption = caption })
  e.style.width = width
  return e
end

-- Headers and rows share exactly the same columns, insets and spacing. Reserve the remaining
-- 16 px of the content width for the scrollbar instead of letting it shift the numbers.
local function resource_grid(parent, name, column_count)
  local grid = parent.add({ type = "table", name = name, column_count = column_count })
  grid.style.width, grid.style.padding = ROW_WIDTH, { 4, 8 }
  grid.style.horizontal_spacing, grid.style.vertical_spacing = GAP, 0
  return grid
end

-- A fixed-width, right-aligned number column: values line up whatever their width.
local function number(parent, name, width, font)
  local e = parent.add({ type = "label", name = name })
  e.style.width, e.style.horizontal_align = width, "right"
  e.style.font = font
  return e
end

function network_gui.open(player)
  local old = frame_of(player)
  if old then
    old.destroy()
  end
  storage.network_gui = storage.network_gui or {}
  storage.network_gui[player.index] = { filter = 1, page = 1, force = player.force.index }
  local frame =
    player.gui.screen.add({ type = "frame", name = FRAME, direction = "vertical", tags = { layout = LAYOUT } })
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

  local controls = inner.add({ type = "flow", name = "controls", direction = "horizontal" })
  controls.style.width = CONTENT_WIDTH
  controls.style.bottom_margin = 8
  controls.add({ type = "drop-down", name = SURFACE }).style.width = 220
  controls.add({
    type = "drop-down",
    name = FILTER,
    items = {
      { "jatz-network.filter-all" },
      { "jatz-network.filter-needs" },
      { "jatz-network.filter-idle" },
    },
    selected_index = 1,
  }).style.width = CONTENT_WIDTH
    - 224
  local overview = inner.add({
    type = "frame",
    name = "overview",
    style = "inside_shallow_frame_with_padding",
    direction = "horizontal",
  })
  overview.style.width = CONTENT_WIDTH
  overview.style.vertical_align = "top"
  local freighters = overview.add({
    type = "flow",
    name = "freighters",
    direction = "vertical",
  })
  freighters.style.width, freighters.style.right_margin = 136, 12
  freighters.style.vertical_spacing = 4
  label(freighters, { "jatz-network.freighters" }, 136).style.font = "default-semibold"
  local fleet = freighters.add({ type = "flow", name = "fleet", direction = "horizontal" })
  fleet.style.height = SLOT_SIZE
  fleet.style.vertical_align = "center"
  fleet.add({
    type = "sprite",
    name = "freighter_icon",
    sprite = "item/jatz-quinityn-freighter",
    resize_to_sprite = false,
    tooltip = { "jatz-network.freighters-tooltip" },
  }).style.size =
    SLOT_SIZE
  fleet.add({ type = "label", name = "total", caption = "…", tooltip = { "jatz-network.freighters-tooltip" } }).style.font =
    "default-large-semibold"
  local active = freighters.add({ type = "flow", name = "on_road", direction = "horizontal" })
  active.style.height = SLOT_SIZE
  active.style.vertical_align = "center"
  local marker = active.add({ type = "flow", name = "marker", direction = "horizontal" })
  marker.style.size = SLOT_SIZE
  marker.style.horizontal_align, marker.style.vertical_align = "center", "center"
  marker.add({
    type = "sprite",
    sprite = "utility/status_working",
    resize_to_sprite = false,
    tooltip = { "jatz-network.active-tooltip" },
  }).style.size =
    10
  active.add({ type = "label", name = "count", caption = "…", tooltip = { "jatz-network.active-tooltip" } })
  active.add({ type = "label", caption = { "jatz-network.active" } })
  local depot_summary = overview.add({
    type = "flow",
    name = "depot_summary",
    direction = "vertical",
  })
  depot_summary.style.width, depot_summary.style.right_margin = 372, 12
  local depots = depot_summary.add({ type = "table", name = "depots", column_count = 4 })
  depots.style.horizontal_spacing, depots.style.vertical_spacing = 12, 8
  depots.add({ type = "empty-widget" })
  -- Headings start where their icons start, in fixed-width columns.
  for index, role in ipairs(ROLES) do
    label(depots, { "jatz-network." .. role }, 96).style.font = "default-semibold"
    depots.style.column_alignments[index + 1] = "middle-left"
  end
  depots.style.column_alignments[1] = "middle-left"
  -- Support depots have their own group, so Mining Drones does not add a mostly empty third row.
  local support = overview.add({ type = "flow", name = "support", direction = "vertical" })
  support.style.width = 196
  -- The same heading-to-icon spacing as the depot matrix, so both headings sit on one line.
  support.style.vertical_spacing = 8
  label(support, { "jatz-network.support" }, 196).style.font = "default-semibold"
  local support_depots = support.add({ type = "table", name = "depots", column_count = 2 })
  support_depots.style.horizontal_spacing, support_depots.style.vertical_spacing = 4, 8
  local function depot_slot(parent, name)
    local prototype = prototypes.entity[name]
    if prototype then
      local summary = parent.add({
        type = "flow",
        name = name,
        direction = "horizontal",
        tooltip = prototype.localised_name,
      })
      summary.style.width, summary.style.height = 96, SLOT_SIZE
      summary.style.vertical_align = "center"
      summary.add({
        type = "sprite",
        name = "icon",
        resize_to_sprite = false,
        sprite = "entity/" .. name,
        tooltip = prototype.localised_name,
      }).style.size =
        SLOT_SIZE
      local count = summary.add({ type = "label", name = "count", caption = "…", tooltip = prototype.localised_name })
      count.style.width, count.style.font = 40, "default-semibold"
    else
      parent.add({ type = "empty-widget" })
    end
  end
  label(depots, { "jatz-network.items" }, 48)
  for index = 1, 3 do
    depot_slot(depots, KINDS[index])
  end
  label(depots, { "jatz-network.fluids" }, 48)
  for index = 4, 6 do
    depot_slot(depots, KINDS[index])
  end
  for index = 7, #KINDS do
    depot_slot(support_depots, KINDS[index])
  end
  local tabs = inner.add({ type = "tabbed-pane", name = TABS, style = "tabbed_pane_with_no_side_padding" })
  tabs.style.top_margin = 12
  for _, kind in ipairs({ "item", "fluid" }) do
    local tab = tabs.add({ type = "tab", name = kind .. "_tab", caption = { "jatz-network." .. kind .. "s" } })
    local content = tabs.add({ type = "flow", name = kind .. "_content", direction = "vertical" })
    content.style.width = CONTENT_WIDTH
    -- Two header lines: each role's depot icon and name over its pair of columns, then what each
    -- column counts. Rows below hold numbers only, in exactly these columns.
    local picker = resource_grid(content, "headers", 5)
    local chooser = picker.add({
      type = "choose-elem-button",
      name = "jatz_network_" .. kind,
      elem_type = kind,
      tooltip = { "jatz-network.find-resource-tooltip" },
    })
    chooser.style.size, chooser.style.right_margin = RESOURCE_SIZE, SLOT_SIZE - RESOURCE_SIZE
    for _, role in ipairs(ROLES) do
      local heading = picker.add({ type = "flow", name = role, direction = "horizontal" })
      heading.style.width, heading.style.horizontal_align = ROLE_WIDTH, "center"
      heading.style.vertical_align, heading.style.horizontal_spacing = "center", 4
      heading.add({
        type = "sprite",
        resize_to_sprite = false,
        sprite = "entity/jatz-" .. (kind == "fluid" and "liquid-" or "") .. role .. "-depot",
        tooltip = { "jatz-network." .. role },
      }).style.size =
        HEADER_DEPOT_SIZE
      heading.add({ type = "label", caption = { "jatz-network." .. role } }).style.font = "default-semibold"
    end
    picker.add({ type = "empty-widget" }).style.width = NEED_WIDTH
    local columns = resource_grid(content, "columns", 8)
    columns.style.top_padding = 0
    columns.add({ type = "empty-widget" }).style.width = SLOT_SIZE
    for _, role in ipairs(ROLES) do
      local stock = number(columns, role .. "_stock", STOCK_WIDTH, "default-semibold")
      stock.caption, stock.tooltip = { "jatz-network.stock" }, { "jatz-network.stock-tooltip" }
      local count = number(columns, role .. "_count", COUNT_WIDTH, "default-semibold")
      local caption = role == "provider" and "depots" or "requests"
      count.caption, count.tooltip = { "jatz-network." .. caption }, { "jatz-network." .. caption .. "-tooltip" }
    end
    local needed_heading = number(columns, "needed", NEED_WIDTH, "default-semibold")
    needed_heading.caption, needed_heading.tooltip =
      { "jatz-network.needed" }, { "jatz-network.needed-heading-tooltip" }
    content.add({ type = "line", direction = "horizontal" }).style.width = ROW_WIDTH
    content.add({ type = "label", name = "no_items", caption = { "jatz-network.no-items" } })
    local pane = content.add({ type = "scroll-pane", name = "resource_rows", style = "naked_scroll_pane" })
    pane.style.width, pane.style.padding = CONTENT_WIDTH, 0
    -- A whole page of single-line rows without scrolling at the default UI scale.
    pane.style.maximal_height = 440
    for index = 1, PAGE_SIZE do
      local group = pane.add({ type = "flow", name = "row_" .. index, direction = "vertical", visible = false })
      group.style.vertical_spacing = 0
      local row = resource_grid(group, "cells", 8)
      row.style.column_alignments[1] = "middle-left"
      for column = 2, 8 do
        row.style.column_alignments[column] = "middle-right"
      end
      local resource = row.add({ type = "sprite", name = "resource_icon", resize_to_sprite = false })
      resource.style.size, resource.style.right_margin = RESOURCE_SIZE, SLOT_SIZE - RESOURCE_SIZE
      for _, role in ipairs(ROLES) do
        number(row, role .. "_stock", STOCK_WIDTH, "default-semibold")
        number(row, role .. "_count", COUNT_WIDTH, "default")
      end
      number(row, "needed", NEED_WIDTH, "default-semibold")
      local separator = group.add({ type = "line", name = "separator", direction = "horizontal" })
      separator.style.width = ROW_WIDTH
      separator.style.top_margin, separator.style.bottom_margin = 2, 2
    end
    tabs.add_tab(tab, content)
  end
  tabs.selected_tab_index = 1
  local paging = inner.add({ type = "flow", name = "paging", direction = "horizontal" })
  paging.style.width, paging.style.horizontal_spacing = CONTENT_WIDTH, 8
  paging.style.vertical_align = "center"
  paging.style.top_margin = 12
  paging.add({
    type = "sprite-button",
    name = PREVIOUS,
    style = "tool_button",
    sprite = "utility/backward_arrow",
    tooltip = { "jatz-network.previous" },
    enabled = false,
  }).style.size =
    28
  paging.add({ type = "label", name = "page_label", caption = { "jatz-network.page", 1, 1 } })
  paging.add({
    type = "sprite-button",
    name = NEXT,
    style = "tool_button",
    sprite = "utility/forward_arrow",
    tooltip = { "jatz-network.next" },
    enabled = false,
  }).style.size =
    28
  paging.add({
    type = "label",
    name = "snapshot",
    caption = { "jatz-network.loading" },
    tooltip = { "jatz-network.snapshot-tooltip" },
  })
  show_cached(player)
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

function network_gui.on_gui_click(event)
  local name = event.element.name
  if name ~= CLOSE and name ~= PREVIOUS and name ~= NEXT then
    return false
  end
  local player = game.get_player(event.player_index)
  if player then
    if name == CLOSE then
      close(player)
    else
      local state = storage.network_gui and storage.network_gui[player.index]
      if state then
        state.page = math.max(1, state.page + (name == NEXT and 1 or -1))
        show_cached(player)
      end
    end
  end
  return true
end

function network_gui.on_gui_selection_state_changed(event)
  local element = event.element
  if element.name ~= SURFACE and element.name ~= FILTER and element.name ~= TABS then
    return false
  end
  local player = game.get_player(event.player_index)
  local state = storage.network_gui and storage.network_gui[event.player_index]
  if player and state then
    state.page = 1
    if element.name == SURFACE then
      state.surface = state.listed and state.listed[element.selected_index - 1]
    elseif element.name == FILTER then
      state.filter = element.selected_index
    end
    show_cached(player)
  end
  return true
end

function network_gui.on_gui_elem_changed(event)
  local name = event.element.name
  local kind = name == "jatz_network_item" and "item" or name == "jatz_network_fluid" and "fluid"
  if not kind then
    return false
  end
  local player = game.get_player(event.player_index)
  local state = storage.network_gui and storage.network_gui[event.player_index]
  if player and state then
    state[kind], state.page = event.element.elem_value, 1
    show_cached(player)
  end
  return true
end

function network_gui.on_player_changed_force(event)
  local player = game.get_player(event.player_index)
  if player and frame_of(player) then
    network_gui.open(player)
  end
end

function network_gui.on_configuration_changed()
  storage.network_scan, storage.network_data, storage.network_next, storage.network_viewer = nil, nil, nil, nil
  for index in pairs(storage.network_gui or {}) do
    local player = game.get_player(index)
    if player and player.valid and frame_of(player) then
      network_gui.open(player)
    end
  end
end

-- A snapshot ID list is cheap Lua work; expensive inventory/condition/demand reads are capped
-- across ALL forces, not per player. IDs tolerate deletion/replacement during collection. The
-- stored cursor and partial sums survive save/load and multiplayer joins deterministically.
function network_gui.refresh(tick)
  if not (storage.network_gui and next(storage.network_gui)) then
    return
  end
  tick = tick or game.tick
  local forces, viewers = {}, {}
  for index, state in pairs(storage.network_gui) do
    local player = game.get_player(index)
    if not (player and player.valid) then
      storage.network_gui[index] = nil
    elseif not frame_of(player) then
      close(player)
    elseif player.connected then
      forces[player.force.index] = true
      viewers[#viewers + 1] = player
      if state.force ~= player.force.index then
        network_gui.open(player)
      end
    end
  end
  if #viewers == 0 then
    storage.network_scan, storage.network_data, storage.network_next, storage.network_viewer = nil, nil, nil, nil
    return
  end
  local data = storage.network_data or {}
  storage.network_data = data
  local missing = false
  for force in pairs(forces) do
    if not data[force] then
      missing = true
    end
  end
  for force in pairs(data) do
    if not forces[force] then
      data[force] = nil
    end
  end
  local scan = storage.network_scan
  if not scan and (missing or tick >= (storage.network_next or 0)) then
    scan = { ids = {}, at = 1, counts = {} }
    for id in pairs(storage.depots or {}) do
      scan.ids[#scan.ids + 1] = id
    end
    table.sort(scan.ids)
    for force in pairs(forces) do
      scan.counts[force] = { all = new_counts(), surfaces = {} }
    end
    storage.network_scan = scan
  end
  if scan then
    for _ = 1, PER_TICK do
      local id = scan.ids[scan.at]
      if not id then
        for force, counts in pairs(scan.counts) do
          if forces[force] then
            counts.tick = tick
            data[force] = counts
          end
        end
        storage.network_scan, storage.network_next = nil, tick + INTERVAL
        break
      end
      scan.at = scan.at + 1
      local depot = storage.depots[id]
      if depot and depot.entity.valid then
        local force = depot.entity.force.index
        if forces[force] and scan.counts[force] then
          count_depot(scan.counts[force], depot)
        end
      end
    end
  end
  -- Stagger GUI writes too: many viewers share counts but have separate engine GUI elements.
  table.sort(viewers, function(a, b)
    return a.index < b.index
  end)
  local start = 1
  for index, player in ipairs(viewers) do
    if player.index > (storage.network_viewer or 0) then
      start = index
      break
    end
  end
  for offset = 0, #viewers - 1 do
    local player = viewers[(start + offset - 1) % #viewers + 1]
    local counts = data[player.force.index]
    if counts and storage.network_gui[player.index].shown ~= counts.tick then
      show(player, frame_of(player), counts)
      storage.network_viewer = player.index
      break
    elseif counts then
      local age = math.floor((tick - counts.tick) / 60)
      local state = storage.network_gui[player.index]
      if state.age ~= age then
        frame_of(player).inner.paging.snapshot.caption = { "jatz-network.snapshot", age }
        state.age = age
        storage.network_viewer = player.index
        break
      end
    end
  end
end

return network_gui
