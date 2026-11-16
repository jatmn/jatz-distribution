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
  return inner().jatz_network_tabs[kind .. "_content"].resource_rows.row_1
end
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
    assert(not row("item").visible)
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
    assert(row("item").need_cell.needed.caption == (script.active_mods.quality and "45" or "50"))
    assert(inner().overview.freighters.total.caption == "3")
    local depots = inner().overview.depot_summary.depots
    assert(depots.column_count == 5)
    for _, name in ipairs({
      "jatz-provider-depot",
      "jatz-request-depot",
      "jatz-buffer-depot",
      "jatz-liquid-provider-depot",
      "jatz-liquid-request-depot",
      "jatz-liquid-buffer-depot",
    }) do
      assert(depots[name].sprite == "entity/" .. name and depots[name].number == 1)
      assert(depots[name].tooltip[2][1] == prototypes.entity[name].localised_name[1])
    end
    assert(depots["jatz-fuel-depot"].number == 0)
    assert(row("item").resource_icon.sprite == "item/iron-plate")
    assert(row("item").provider_cell.details.depot_count.caption == "1")
    assert(row("item").provider_cell.details.activity.caption == "1")
    if script.active_mods.quality then
      assert(iron.provider.grades.rare == 20)
    end
    inner().jatz_network_tabs.selected_tab_index = 2
    network.on_gui_selection_state_changed({ player_index = 1, element = inner().jatz_network_tabs })
    assert(row("fluid").provider_cell.stock.caption == "1000")
    assert(row("fluid").request_cell.stock.caption == "150")
    assert(row("fluid").buffer_cell.stock.caption == "200")
    assert(row("fluid").need_cell.needed.caption == "450")
    assert(row("fluid").resource_icon.sprite == "fluid/water")
    assert(row("fluid").request_cell.details.holding_icon.sprite == "entity/jatz-liquid-request-depot")
    network.on_configuration_changed()
    assert(not row("item").visible and storage.network_data == nil)
  elseif event.tick == 10 then
    player.opened = nil -- Real engine on_gui_closed, not an invented close event.
    assert(not player.gui.screen.jatz_network_frame)
    assert(not player.is_shortcut_toggled("jatz-network"))
    assert(storage.network_scan == nil and storage.network_data == nil)
    helpers.write_file("jatz-network-check.json", helpers.table_to_json({ passed = true }))
    script.finish_test(true)
  end
end)
