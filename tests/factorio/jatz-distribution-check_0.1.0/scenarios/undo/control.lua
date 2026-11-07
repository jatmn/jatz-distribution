-- SPDX-License-Identifier: LGPL-3.0-only
-- Undo of a depot's removal, against the real engine with a player (the undo stack is a player's):
-- tools/test_mod.py runs it with `--test-scenario jatz-distribution-check/undo`. A request depot
-- cut (marked for deconstruction by the player), changed before robots take it (a bigger request,
-- freighters put in its chest), must have its settings as it went on the player's undo action; one
-- mined by hand, with freighters in its chest, must have all of them. Factorio has no script call
-- for undo itself, so the ghost an undo brings back is made here with the action's tags as
-- scripts/undo.lua puts them on it (tests/lua/control-events.lua covers that step): rebuilt by
-- robots and by the player, each depot must get its request back and its freighters. A cut depot a
-- player then fails to mine by hand (a full inventory) stays marked, and its settings when the
-- robots take it are the ones kept. With Space Age, a liquid request depot cut on a space platform
-- (the platform takes it at once) keeps its settings too, and the platform rebuilds it from its
-- ghost with its request and freighters. A depot mined by hand and a bare replacement at its spot
-- marked for deconstruction in the same tick each keep their own settings on their own action, and
-- so do two depots mined by hand at one spot in a tick with the undo history at its limit, and in
-- adjacent ticks.
-- Writes script-output/jatz-undo-check.json.
local FREIGHTER = "jatz-quinityn-freighter"
local DEPOT = "jatz-request-depot"
local CUT, MINED, KEPT = { x = 6.5, y = 0.5 }, { x = 6.5, y = -6.5 }, { x = 14.5, y = 0.5 }
local PLATFORM_DEPOT, AFLOAT = "jatz-liquid-request-depot", { x = 8.5, y = 0.5 }
local SWAPPED, AT_LIMIT, NEXT_TICK = { x = -2.5, y = -6.5 }, { x = -2.5, y = 6.5 }, { x = 2.5, y = -12.5 }

-- The freighters kept on every undo action for the removal of a request depot at `position`,
-- newest first (0 for none).
local function freighters_kept_at(position)
  local stack = game.get_player(1).undo_redo_stack
  local kept = {}
  for item = 1, stack.get_undo_item_count() do
    for action_index, action in ipairs(stack.get_undo_item(item)) do
      local target = action.target
      if
        action.type == "removed-entity"
        and target.name == DEPOT
        and target.position.x == position.x
        and target.position.y == position.y
      then
        local settings = stack.get_undo_tag(item, action_index, "jatz_settings") or {}
        kept[#kept + 1] = settings.jatz_freighters or 0
      end
    end
  end
  return kept
end

-- The settings on the player's undo action for the removal of `name` (a request depot unless
-- given) at `position` on the surface `surface_index` (the player's unless given).
local function settings_at(position, name, surface_index)
  local stack = game.get_player(1).undo_redo_stack
  surface_index = surface_index or game.get_player(1).surface_index
  for item = 1, stack.get_undo_item_count() do
    for action_index, action in ipairs(stack.get_undo_item(item)) do
      local target = action.target
      if
        action.type == "removed-entity"
        and action.surface_index == surface_index
        and target.name == (name or DEPOT)
        and target.position.x == position.x
        and target.position.y == position.y
      then
        return stack.get_undo_tag(item, action_index, "jatz_settings")
      end
    end
  end
end

-- A depot's freighters: in its slot, out, in its chest and asked for. A liquid depot has no chest:
-- its freighters arrive in its truck chest (invisible, at its centre).
local function freighters(depot)
  local slot, out = remote.call("jatz-distribution", "freighter_counts", depot)
  local requested = remote.call("jatz-distribution", "requested_freighters", depot)
  local chest = depot.get_inventory(defines.inventory.chest)
  if not chest then
    local truck = depot.surface.find_entities_filtered({ name = "jatz-truck-chest", position = depot.position })[1]
    chest = truck and truck.get_inventory(defines.inventory.chest)
  end
  return slot + out + (chest and chest.get_item_count(FREIGHTER) or 0) + requested
end

local function depot_at(position, name, surface)
  surface = surface or game.get_player(1).surface
  return surface.find_entities_filtered({ name = name or DEPOT, position = position })[1]
end

script.on_event(defines.events.on_tick, function(event)
  local player = game.get_player(1)
  if not player then
    return
  end
  local surface = player.surface
  local result = storage.result
  if event.tick == 1 then
    surface.request_to_generate_chunks({ 0, 0 }, 2)
    surface.force_generate_chunk_requests()
    local tiles = {}
    for x = -20, 20 do
      for y = -20, 20 do
        tiles[#tiles + 1] = { name = "concrete", position = { x, y } }
      end
    end
    surface.set_tiles(tiles)
    for _, entity in pairs(surface.find_entities({ { -20, -20 }, { 20, 20 } })) do
      if entity.type ~= "character" then
        entity.destroy()
      end
    end
    player.teleport({ 0, 0 })
    -- Construction robots and a storage chest, with 5 freighters for the rebuilt depots.
    local port = surface.create_entity({ name = "roboport", position = { -8, 0 }, force = player.force })
    port.get_inventory(defines.inventory.roboport_robot).insert({ name = "construction-robot", count = 20 })
    surface.create_entity({ name = "electric-energy-interface", position = { -12, 0 }, force = player.force })
    surface.create_entity({ name = "medium-electric-pole", position = { -10.5, 2.5 }, force = player.force })
    storage.store = surface.create_entity({ name = "storage-chest", position = { -8.5, 4.5 }, force = player.force })
    storage.store.insert({ name = FREIGHTER, count = 5 })
    storage.result = {}
    -- Cut: 3 freighters, asking for 5 wood; marked by the player, as a cut does.
    local cut = surface.create_entity({ name = DEPOT, position = CUT, force = player.force, raise_built = true })
    assert(remote.call("jatz-distribution", "set_request", cut, "wood", 5))
    assert(remote.call("jatz-distribution", "add_freighters", cut, 3) == 3)
    assert(cut.order_deconstruction(player.force, player, 0))
    -- Changed before the robots come: a bigger request, and 2 more freighters in its chest.
    assert(remote.call("jatz-distribution", "set_request", cut, "wood", 8))
    cut.get_inventory(defines.inventory.chest).insert({ name = FREIGHTER, count = 2 })
    -- Cut too, then mined by hand with a full inventory (before the player holds any depot to
    -- stack it on): the mining fails and it stays, still marked; its request changes before the
    -- robots take it, which must be what is kept.
    local kept = surface.create_entity({ name = DEPOT, position = KEPT, force = player.force, raise_built = true })
    assert(remote.call("jatz-distribution", "set_request", kept, "wood", 5))
    assert(remote.call("jatz-distribution", "add_freighters", kept, 1) == 1)
    assert(kept.order_deconstruction(player.force, player, 0))
    local pockets = player.get_main_inventory()
    while pockets.can_insert({ name = "stone", count = 50 }) do
      pockets.insert({ name = "stone", count = 50 })
    end
    storage.result.failed_mining_left_it = not player.mine_entity(kept, false)
      and kept.valid
      and kept.to_be_deconstructed()
    pockets.remove({ name = "stone", count = pockets.get_item_count("stone") })
    assert(remote.call("jatz-distribution", "set_request", kept, "wood", 9))
    -- With Space Age: a liquid request depot on a space platform (gravity stops the item depots
    -- there), cut; the platform takes it within the tick.
    if script.active_mods["space-age"] then
      local platform = player.force.create_space_platform({
        name = "undo",
        planet = "nauvis",
        starter_pack = "space-platform-starter-pack",
      })
      platform.apply_starter_pack()
      local foundation = {}
      for x = 4, 14 do
        for y = -5, 5 do
          foundation[#foundation + 1] = { name = "space-platform-foundation", position = { x, y } }
        end
      end
      platform.surface.set_tiles(foundation)
      local floating = platform.surface.create_entity({
        name = PLATFORM_DEPOT,
        position = AFLOAT,
        force = player.force,
        raise_built = true,
      })
      assert(remote.call("jatz-distribution", "set_request", floating, "water", 1000))
      assert(remote.call("jatz-distribution", "add_freighters", floating, 2) == 2)
      assert(floating.order_deconstruction(player.force, player, 0))
      storage.platform_surface = platform.surface.index
    end
    -- Mined by hand: 1 freighter in its slot, 2 in its chest.
    local mined = surface.create_entity({ name = DEPOT, position = MINED, force = player.force, raise_built = true })
    assert(remote.call("jatz-distribution", "add_freighters", mined, 1) == 1)
    mined.get_inventory(defines.inventory.chest).insert({ name = FREIGHTER, count = 2 })
    assert(player.mine_entity(mined, true), "the player could not mine the depot")
    -- Mined by hand with 2 freighters, then a bare replacement at the same spot marked for
    -- deconstruction in the same tick, before the mining's action is tagged: each keeps its own.
    local swapped =
      surface.create_entity({ name = DEPOT, position = SWAPPED, force = player.force, raise_built = true })
    assert(remote.call("jatz-distribution", "add_freighters", swapped, 2) == 2)
    assert(player.mine_entity(swapped, true), "the player could not mine the depot")
    local replacement =
      surface.create_entity({ name = DEPOT, position = SWAPPED, force = player.force, raise_built = true })
    assert(replacement.order_deconstruction(player.force, player, 0))
    -- A depot with 2 freighters mined by hand here, and a bare one at its spot mined the next tick.
    local first =
      surface.create_entity({ name = DEPOT, position = NEXT_TICK, force = player.force, raise_built = true })
    assert(remote.call("jatz-distribution", "add_freighters", first, 2) == 2)
    assert(player.mine_entity(first, true), "the player could not mine the depot")
  elseif result and event.tick == 2 then
    local second =
      surface.create_entity({ name = DEPOT, position = NEXT_TICK, force = player.force, raise_built = true })
    assert(player.mine_entity(second, true), "the player could not mine the depot")
  elseif result and event.tick == 600 then
    result.swapped_kept = freighters_kept_at(SWAPPED)
    result.next_tick_kept = freighters_kept_at(NEXT_TICK)
    result.cut_removed = depot_at(CUT) == nil
    local cut = settings_at(CUT) or {}
    result.cut_settings = { request = cut.jatz_request, freighters = cut.jatz_freighters }
    local mined = settings_at(MINED) or {}
    result.mined_settings = { request = mined.jatz_request, freighters = mined.jatz_freighters }
    if storage.platform_surface then
      local afloat = settings_at(AFLOAT, PLATFORM_DEPOT, storage.platform_surface) or {}
      result.platform_settings = { request = afloat.jatz_request, freighters = afloat.jatz_freighters }
      -- Its ghost, given the tags as scripts/undo.lua gives them, for the platform to build from
      -- its hub, which took the depot and its freighters.
      local platform_surface = game.surfaces[storage.platform_surface]
      result.platform_removed = depot_at(AFLOAT, PLATFORM_DEPOT, platform_surface) == nil
      local ghost = platform_surface.create_entity({
        name = "entity-ghost",
        inner_name = PLATFORM_DEPOT,
        position = AFLOAT,
        force = player.force,
      })
      ghost.tags = afloat
    end
    local kept = settings_at(KEPT) or {}
    result.kept_settings = { request = kept.jatz_request, freighters = kept.jatz_freighters }
    -- The ghosts the undos bring back, given the tags as scripts/undo.lua gives them: the cut one
    -- for robots to build, the mined one for the player to build by hand.
    for _, spot in ipairs({ { CUT, cut }, { MINED, mined } }) do
      local ghost = surface.create_entity({
        name = "entity-ghost",
        inner_name = DEPOT,
        position = spot[1],
        force = player.force,
      })
      ghost.tags = spot[2]
    end
    player.get_main_inventory().insert({ name = DEPOT, count = 1 })
    player.cursor_stack.set_stack({ name = DEPOT, count = 1 })
    player.build_from_cursor({ position = MINED })
    -- The undo history at its limit (100 items: one more drops the oldest), from 99: chests mined.
    local stack = player.undo_redo_stack
    local x = -12
    while stack.get_undo_item_count() < 99 do
      local chest = surface.create_entity({ name = "wooden-chest", position = { x + 0.5, 12.5 }, force = player.force })
      assert(player.mine_entity(chest, true), "the player could not mine a chest")
      x = x + 1
    end
    -- Then in one tick, a depot with 2 freighters mined by hand, and a bare one at its spot too:
    -- each keeps its own, though the history drops its oldest under them.
    for _, count in ipairs({ 2, 0 }) do
      local depot =
        surface.create_entity({ name = DEPOT, position = AT_LIMIT, force = player.force, raise_built = true })
      if count > 0 then
        assert(remote.call("jatz-distribution", "add_freighters", depot, count) == count)
      end
      assert(player.mine_entity(depot, true), "the player could not mine the depot")
    end
  elseif result and event.tick == 1200 then
    result.limit_kept = freighters_kept_at(AT_LIMIT)
    local rebuilt = { cut_rebuilt = { CUT }, mined_rebuilt = { MINED } }
    if storage.platform_surface then
      rebuilt.platform_rebuilt = { AFLOAT, PLATFORM_DEPOT, game.surfaces[storage.platform_surface] }
    end
    for name, spot in pairs(rebuilt) do
      local depot = depot_at(spot[1], spot[2], spot[3])
      result[name] = depot
          and { request = remote.call("jatz-distribution", "get_request", depot), freighters = freighters(depot) }
        or "not rebuilt"
    end
    helpers.write_file("jatz-undo-check.json", helpers.table_to_json(result))
    script.finish_test(true)
  end
end)
