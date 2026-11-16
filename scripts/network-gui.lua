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

  inner.snapshot.caption = { "jatz-network.snapshot", math.floor((game.tick - counts.tick) / 60) }
  local kind = inner[TABS].selected_tab_index == 2 and "fluid" or "item"
  local content = inner[TABS][kind .. "_content"]
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
    inner[TABS][t .. "_tab"].badge_text = tostring(totals[t])
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
  inner.paging.page_label.caption = { "jatz-network.page", state.page, pages }
  inner.paging[PREVIOUS].enabled, inner.paging[NEXT].enabled = state.page > 1, state.page < pages
  content.no_items.visible = #rows == 0
  for index = 1, PAGE_SIZE do
    local row = content.resource_rows["row_" .. index]
    local item = rows[(state.page - 1) * PAGE_SIZE + index]
    row.visible = item ~= nil
    if item then
      local prototype = prototypes[item.type][item.name]
      row.resource_label.caption = { "", "[" .. item.type .. "=" .. item.name .. "] ", prototype.localised_name }
      row.resource_label.tooltip = { "jatz-network.resource-tooltip" }
      for _, role in ipairs(ROLES) do
        local r, cell = item[role], row[role .. "_cell"]
        cell.stock.caption = amount(r.held)
        cell.stock.tooltip = held_tooltip(r)
        cell.depot_count.caption = { "jatz-network.holding", r.depots }
        if role == "provider" then
          cell.activity.caption = { "jatz-network.offering", r.offers }
          cell.activity.tooltip = { "jatz-network.offering-tooltip", amount(r.offered) }
        else
          cell.activity.caption = { "jatz-network.requesting", r.requested }
          local tip = { "jatz-network.requesting-tooltip", amount(r.target), amount(r.missing) }
          cell.activity.tooltip = role == "buffer"
              and { "jatz-network.buffer-requesting-tooltip", tip, r.offers, amount(r.offered) }
            or tip
        end
      end
      local missing = item.request.missing + item.buffer.missing
      row.need_cell.needed.caption = amount(missing)
      row.need_cell.needed.style.font_color = missing >= 1 and { 1, 0.75, 0.3 } or { 0.7, 0.7, 0.7 }
      row.need_cell.needed.tooltip =
        { "jatz-network.needed-tooltip", amount(item.request.missing), amount(item.buffer.missing) }
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

function network_gui.open(player)
  local old = frame_of(player)
  if old then
    old.destroy()
  end
  storage.network_gui = storage.network_gui or {}
  storage.network_gui[player.index] = { filter = 1, page = 1, force = player.force.index }
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
  local freighters = inner.add({ type = "table", name = "freighters", column_count = 4 })
  freighters.add({
    type = "label",
    caption = { "jatz-network.freighters" },
    tooltip = { "jatz-network.freighters-tooltip" },
  })
  freighters.add({ type = "label", name = "total", caption = "…" })
  freighters.add({ type = "label", caption = { "jatz-network.active" }, tooltip = { "jatz-network.active-tooltip" } })
  freighters.add({ type = "label", name = "active", caption = "…" })
  local depots = inner.add({ type = "flow", name = "depots", direction = "horizontal" })
  for _, name in ipairs(KINDS) do
    local prototype = prototypes.entity[name]
    if prototype then
      depots.add({ type = "sprite", sprite = "entity/" .. name, tooltip = prototype.localised_name }).style.width = 24
      depots.add({ type = "label", name = name, caption = "…", tooltip = prototype.localised_name })
    end
  end
  inner.add({
    type = "label",
    name = "snapshot",
    caption = { "jatz-network.loading" },
    tooltip = { "jatz-network.snapshot-tooltip" },
  })
  inner.add({
    type = "drop-down",
    name = FILTER,
    items = {
      { "jatz-network.filter-all" },
      { "jatz-network.filter-needs" },
      { "jatz-network.filter-idle" },
    },
    selected_index = 1,
  })
  local tabs = inner.add({ type = "tabbed-pane", name = TABS })
  for _, kind in ipairs({ "item", "fluid" }) do
    local tab = tabs.add({ type = "tab", name = kind .. "_tab", caption = { "jatz-network." .. kind .. "s" } })
    local content = tabs.add({ type = "flow", name = kind .. "_content", direction = "vertical" })
    local picker = content.add({ type = "flow", direction = "horizontal" })
    picker.add({ type = "label", caption = { "jatz-network.find-resource" } })
    picker.add({
      type = "choose-elem-button",
      name = "jatz_network_" .. kind,
      elem_type = kind,
      tooltip = { "jatz-network.find-resource-tooltip" },
    })
    local headers = content.add({ type = "flow", direction = "horizontal" })
    label(headers, { "jatz-network.resource" }, 190)
    for _, role in ipairs(ROLES) do
      label(headers, { "jatz-network." .. role }, 135)
    end
    label(headers, { "jatz-network.needed" }, 80)
    content.add({ type = "label", name = "no_items", caption = { "jatz-network.no-items" } })
    local pane = content.add({ type = "scroll-pane", name = "resource_rows" })
    pane.style.maximal_height = 360
    for index = 1, PAGE_SIZE do
      local row = pane.add({ type = "flow", name = "row_" .. index, direction = "horizontal", visible = false })
      local resource_label = row.add({ type = "label", name = "resource_label" })
      resource_label.style.width, resource_label.style.single_line = 190, false
      for _, role in ipairs(ROLES) do
        local cell = row.add({ type = "flow", name = role .. "_cell", direction = "vertical" })
        cell.style.width = 135
        cell.add({ type = "label", name = "stock" })
        cell.add({ type = "label", name = "depot_count" })
        cell.add({ type = "label", name = "activity" })
      end
      local need = row.add({ type = "flow", name = "need_cell", direction = "vertical" })
      need.style.width = 80
      need.add({ type = "label", name = "needed" })
    end
    tabs.add_tab(tab, content)
  end
  tabs.selected_tab_index = 1
  local paging = inner.add({ type = "flow", name = "paging", direction = "horizontal" })
  paging.add({ type = "button", name = PREVIOUS, caption = { "jatz-network.previous" }, enabled = false })
  paging.add({ type = "label", name = "page_label", caption = { "jatz-network.page", 1, 1 } })
  paging.add({ type = "button", name = NEXT, caption = { "jatz-network.next" }, enabled = false })
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
        frame_of(player).inner.snapshot.caption = { "jatz-network.snapshot", age }
        state.age = age
        storage.network_viewer = player.index
        break
      end
    end
  end
end

return network_gui
