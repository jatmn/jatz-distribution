-- SPDX-License-Identifier: LGPL-3.0-only
-- The engine cannot raise on_player_dropped_item_into_entity by script. Supply its payload to
-- the production handler after moving one real item; control-events.lua checks the event wiring.
-- Real inventories and a burner inserter check that nothing remains available for extraction.
local gui = require("__jatz-distribution__/scripts/request-gui")
local logistics = require("__jatz-distribution__/scripts/logistics")
local FREIGHTER = logistics.freighter
script.on_event(defines.events.on_player_cursor_stack_changed, gui.on_player_cursor_stack_changed)
script.on_event(defines.events.on_tick, function(event)
  local player = game.get_player(1)
  if not player then
    return
  end
  if event.tick == 1 then
    local surface = game.create_surface("drop-check", { width = 64, height = 64 })
    surface.request_to_generate_chunks({ 0, 0 }, 2)
    surface.force_generate_chunk_requests()
    local pockets, cursor = player.get_main_inventory(), player.cursor_stack
    pockets.clear()
    cursor.set_stack({ name = FREIGHTER, count = 5 })
    local function drop(entity, item)
      gui.on_player_main_inventory_changed({ player_index = 1 }) -- Count before the drop.
      assert(entity.insert({ name = item, count = 1 }) == 1)
      cursor.count = cursor.count - 1
      gui.on_player_main_inventory_changed({ player_index = 1, entity = entity })
    end
    for index, role in ipairs({ "request", "buffer" }) do
      local target = surface.create_entity({
        name = "jatz-" .. role .. "-depot",
        position = { index * 8, 0 },
        force = player.force,
      })
      logistics.add(target)
      assert(logistics.match_freighters(target, 2) == 2)
      drop(target, FREIGHTER)
      assert(logistics.freighter_counts(target) == 1, "Z drop did not reach " .. role .. " slot")
      assert(logistics.requested_freighters(target) == 1, "Z drop did not trim robot request")
      local chest = target.get_inventory(defines.inventory.chest)
      assert(chest.get_item_count(FREIGHTER) == 0, "freighter exposed to inserters")
      gui.on_player_cursor_stack_changed({ player_index = 1 })
      assert(logistics.freighter_counts(target) == 1, "delayed event counted the drop twice")
      -- Other items stay cargo, even when a freighter was already left in the chest.
      chest.insert({ name = FREIGHTER, count = 1 })
      cursor.set_stack({ name = "iron-plate", count = 2 })
      drop(target, "iron-plate")
      assert(chest.get_item_count(FREIGHTER) == 1 and chest.get_item_count("iron-plate") == 1)
      chest.clear()
      for _ = 1, 99 do
        cursor.set_stack({ name = FREIGHTER, count = 1 })
        assert(logistics.put_freighters(target, cursor, 1) == 1)
      end
      cursor.set_stack({ name = FREIGHTER, count = 3 })
      local before = pockets.get_item_count(FREIGHTER)
      drop(target, FREIGHTER)
      assert(logistics.freighter_counts(target) == 100 and pockets.get_item_count(FREIGHTER) == before + 1)
      assert(chest.get_item_count(FREIGHTER) == 0, "overflow left for inserters")
      local inserter = surface.create_entity({
        name = "burner-inserter",
        position = { index * 8, -2 },
        direction = defines.direction.south,
        force = player.force,
      })
      if inserter.pickup_position.y < -2 then
        inserter.direction = defines.direction.north
      end
      inserter.get_fuel_inventory().insert({ name = "coal", count = 5 })
      local output =
        surface.create_entity({ name = "wooden-chest", position = { index * 8, -3 }, force = player.force })
      storage.outputs = storage.outputs or {}
      storage.outputs[index] = output
      if index == 1 then
        -- A freighter requested as cargo stays cargo.
        assert(logistics.set_request(target, FREIGHTER, 10))
        drop(target, FREIGHTER)
        assert(chest.get_item_count(FREIGHTER) == 1 and logistics.freighter_counts(target) == 100)
      end
    end
  elseif event.tick == 180 then
    for index, output in pairs(storage.outputs) do
      local expected = index == 1 and 1 or 0 -- The request depot's cargo, never its internal fleet.
      assert(output.get_inventory(defines.inventory.chest).get_item_count(FREIGHTER) == expected)
    end
    helpers.write_file("jatz-drop-check.json", helpers.table_to_json({ passed = true }))
    script.finish_test(true)
  end
end)
