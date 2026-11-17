-- SPDX-License-Identifier: LGPL-3.0-only
-- Real engine GUI/inventory checks using the production modules in this scenario's Lua state.
-- The engine cannot raise on_lua_shortcut by script, so call that public handler here. Normal
-- GUI events are routed to the same handlers; control-events.lua checks the mod's event wiring.
local network = require("__jatz-distribution__/scripts/network-gui")
local logistics = require("__jatz-distribution__/scripts/logistics")
local function inner()
  return game.get_player(1).gui.screen.jatz_network_frame.inner
end
local function row(kind)
  return inner().jatz_network_tabs[kind .. "_content"].resource_rows.row_1.cells
end
local function pin()
  return game.get_player(1).gui.screen.jatz_network_frame.children[1].jatz_network_pin
end
local depots_surface
script.on_event(defines.events.on_gui_closed, network.on_gui_closed)
script.on_event(defines.events.on_gui_click, network.on_gui_click)
script.on_event(defines.events.on_gui_selected_tab_changed, network.on_gui_selection_state_changed)
script.on_event(defines.events.on_gui_selection_state_changed, network.on_gui_selection_state_changed)
script.on_event(defines.events.on_tick, function(event)
  local player = game.get_player(1)
  if not player then
    return
  end
  if event.tick == 1 then
    local surface = game.create_surface("network-check", { width = 128, height = 128 })
    depots_surface = surface
    surface.request_to_generate_chunks({ 0, 0 }, 2)
    surface.force_generate_chunk_requests()
    player.force.technologies["jatz-freight-system"].researched = true
    local x = -48
    local function depot(name)
      x = x + 8
      local entity = surface.create_entity({ name = name, position = { x, 0 }, force = player.force })
      assert(entity, name)
      logistics.add(entity)
      return entity, storage.depots[entity.unit_number]
    end
    local provider = depot("jatz-provider-depot")
    provider.insert({ name = "iron-plate", count = 100 })
    if script.active_mods.quality then
      provider.insert({ name = "iron-plate", quality = "rare", count = 20 })
    end
    local requester, request = depot("jatz-request-depot")
    requester.insert({ name = "iron-plate", count = 10 })
    if script.active_mods.quality then
      requester.insert({ name = "iron-plate", quality = "rare", count = 40 })
    end
    assert(logistics.set_request(requester, "iron-plate", 50))
    local buffer = depot("jatz-buffer-depot")
    buffer.insert({ name = "iron-plate", count = 15 })
    if script.active_mods.quality then
      buffer.insert({ name = "iron-plate", quality = "rare", count = 5 })
    end
    assert(logistics.set_request(buffer, "iron-plate", 30, nil, "any"))
    local liquid = depot("jatz-liquid-provider-depot")
    liquid.insert_fluid({ name = "water", amount = 1000 })
    local tank, fluid_request = depot("jatz-liquid-request-depot")
    tank.insert_fluid({ name = "water", amount = 100 })
    assert(logistics.set_request(tank, "water", 500))
    fluid_request.reserve = { name = "water", amount = 50, temperature = 15 }
    local liquid_buffer = depot("jatz-liquid-buffer-depot")
    liquid_buffer.insert_fluid({ name = "water", amount = 200 })
    assert(logistics.set_request(liquid_buffer, "water", 300))
    -- Use real inventories and real demand helpers, with explicit known in-flight commitments.
    storage.promised, storage.promise_totals, storage.coming, storage.spoiling = {}, {}, {}, {}
    storage.promise_totals[provider.unit_number] = { ["iron-plate"] = 30 }
    storage.coming[requester.unit_number] = { ["iron-plate"] = { [1] = 5 } }
    request.trucks = game.create_inventory(1)
    request.trucks.insert({ name = "jatz-quinityn-freighter", count = 3 })
    network.on_lua_shortcut({ player_index = 1, prototype_name = "jatz-network" })
    assert(player.opened == player.gui.screen.jatz_network_frame)
    assert(not row("item").parent.visible)
    -- The player stands on Nauvis, where the force has no depots: all surfaces.
    assert(player.surface ~= surface and storage.network_gui[1].surface == player.surface.index)
  end
  network.refresh(event.tick)
  if event.tick == 5 then
    local iron = storage.network_data[player.force.index].all.items["item/iron-plate"]
    assert(iron.provider.held == (script.active_mods.quality and 120 or 100))
    assert(iron.provider.depots == 1 and iron.provider.offers == 1)
    assert(iron.provider.offered == (script.active_mods.quality and 90 or 70))
    assert(
      iron.request.held == (script.active_mods.quality and 50 or 10)
        and iron.request.requested == 1
        and iron.request.missing == 35
    )
    assert(
      iron.buffer.held == (script.active_mods.quality and 20 or 15)
        and iron.buffer.requested == 1
        and iron.buffer.missing == (script.active_mods.quality and 10 or 15)
    )
    assert(row("item").needed.caption == (script.active_mods.quality and "45" or "50"))
    assert(inner().overview.freighters.fleet.total.caption == "3")
    local depots = inner().overview.depot_summary.depots
    assert(depots.column_count == 4)
    for _, name in ipairs({
      "jatz-provider-depot",
      "jatz-request-depot",
      "jatz-buffer-depot",
      "jatz-liquid-provider-depot",
      "jatz-liquid-request-depot",
      "jatz-liquid-buffer-depot",
    }) do
      assert(
        depots[name].type == "flow"
          and depots[name].icon.type == "sprite"
          and depots[name].icon.sprite == "entity/" .. name
          and depots[name].count.caption == "1"
      )
      assert(depots[name].tooltip[2][1] == prototypes.entity[name].localised_name[1])
    end
    assert(inner().overview.support.depots["jatz-fuel-depot"].count.caption == "0")
    -- Summary headings start at their icons' left edge.
    assert(depots.style.column_alignments[2] == "middle-left")
    assert(inner().overview.freighters.on_road.marker.children[1].resize_to_sprite == false)
    local resource = row("item")
    assert(resource.resource_icon.sprite == "item/iron-plate")
    assert(resource.provider_count.caption == "1" and resource.request_count.caption == "1")
    -- One line per resource: an icon, then numbers only, in the header's fixed columns.
    local content = inner().jatz_network_tabs.item_content
    local headers, columns = content.headers, content.columns
    assert(headers.type == "table" and columns.type == "table" and resource.type == "table")
    assert(#resource.children == 8 and columns.column_count == 8 and headers.column_count == 5)
    for _, grid in ipairs({ headers, columns }) do
      assert(grid.style.minimal_width == resource.style.minimal_width)
      assert(grid.style.left_padding == resource.style.left_padding)
      assert(grid.style.horizontal_spacing == resource.style.horizontal_spacing)
    end
    local icon = resource.resource_icon.style
    assert(resource.resource_icon.type == "sprite" and icon.minimal_width == 40 and icon.minimal_height == 40)
    assert(headers.jatz_network_item.style.minimal_width == icon.minimal_width)
    assert(headers.jatz_network_item.style.right_margin == icon.right_margin)
    assert(columns.children[1].style.minimal_width == icon.minimal_width + icon.right_margin)
    for column = 2, 8 do
      local cell, heading = resource.children[column], columns.children[column]
      assert(cell.type == "label" and heading.name == cell.name)
      assert(heading.style.minimal_width == cell.style.minimal_width)
      assert(heading.style.horizontal_align == "right" and cell.style.horizontal_align == "right")
      assert(resource.style.column_alignments[column] == "middle-right")
    end
    local spacing = resource.style.horizontal_spacing
    for _, role in ipairs({ "provider", "request", "buffer" }) do
      assert(
        headers[role].style.minimal_width
          == resource[role .. "_stock"].style.minimal_width + spacing + resource[role .. "_count"].style.minimal_width
      )
      assert(headers[role].children[1].sprite == "entity/jatz-" .. role .. "-depot")
    end
    assert(headers.children[5].style.minimal_width == resource.needed.style.minimal_width)
    assert(columns.provider_count.caption[1] == "jatz-network.depots")
    assert(columns.request_count.caption[1] == "jatz-network.requests")
    assert(resource.parent.separator.type == "line" and resource.parent.separator.direction == "horizontal")
    assert(resource.parent.separator.style.minimal_width == resource.style.minimal_width)
    local old_frame = player.gui.screen.jatz_network_frame
    assert(old_frame.tags.layout ~= nil)
    old_frame.tags = {}
    network.on_gui_selection_state_changed({ player_index = 1, element = old_frame.inner.jatz_network_tabs })
    assert(player.gui.screen.jatz_network_frame ~= old_frame)
    assert(inner().overview.freighters.fleet.total.caption == "3")
    assert(row("item").resource_icon.sprite == "item/iron-plate")
    if script.active_mods.quality then
      assert(iron.provider.grades.rare == 20)
    end
    inner().jatz_network_tabs.selected_tab_index = 2
    network.on_gui_selection_state_changed({ player_index = 1, element = inner().jatz_network_tabs })
    assert(row("fluid").provider_stock.caption == "1000")
    assert(row("fluid").request_stock.caption == "150")
    assert(row("fluid").buffer_stock.caption == "200")
    assert(row("fluid").needed.caption == "450")
    assert(row("fluid").resource_icon.sprite == "fluid/water")
    local fluid_headers = inner().jatz_network_tabs.fluid_content.headers
    assert(fluid_headers.request.children[1].sprite == "entity/jatz-liquid-request-depot")
    network.on_configuration_changed()
    assert(not row("item").parent.visible and storage.network_data == nil)
  elseif event.tick == 10 then
    assert(inner().controls.jatz_network_surface.selected_index == 1)
    player.opened = nil -- Real engine on_gui_closed, not an invented close event.
    assert(not player.gui.screen.jatz_network_frame)
    assert(not player.is_shortcut_toggled("jatz-network"))
    assert(storage.network_scan == nil and storage.network_data == nil)
    -- In remote view, LuaPlayer::surface is the surface viewed; the window opens on it.
    player.set_controller({ type = defines.controllers.remote, surface = depots_surface, position = { 0, 0 } })
    assert(player.surface == depots_surface and player.physical_surface ~= depots_surface)
    network.on_lua_shortcut({ player_index = 1, prototype_name = "jatz-network" })
    assert(storage.network_gui[1].surface == depots_surface.index)
  elseif event.tick == 15 then
    local dropdown = inner().controls.jatz_network_surface
    assert(#dropdown.items == 2 and dropdown.selected_index == 2)
    assert(storage.network_gui[1].surface == depots_surface.index)
    assert(row("item").provider_stock.caption == (script.active_mods.quality and "120" or "100"))
    -- Pinning: the window stops being the opened GUI, and the engine raises on_gui_closed for it
    -- during the click, with the pin already set, so the handler keeps it. The jatz-distribution
    -- mod's own Lua state gets that event too and closes its namesake frame, so the frame itself
    -- doesn't survive here; tests/lua/control-events.lua covers the rest of pinning.
    assert(pin().type == "sprite-button" and not pin().toggled)
    local closing
    script.on_event(defines.events.on_gui_closed, function(closed)
      closing = closing or { pinned = storage.network_gui[1].pinned, ours = network.on_gui_closed(closed) }
    end)
    network.on_gui_click({ player_index = 1, element = pin() })
    assert(closing and closing.pinned and closing.ours and player.opened == nil)
    assert(storage.network_gui[1] and storage.network_gui[1].pinned)
    helpers.write_file("jatz-network-check.json", helpers.table_to_json({ passed = true }))
    script.finish_test(true)
  end
end)
