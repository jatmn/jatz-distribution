-- SPDX-License-Identifier: LGPL-3.0-only
-- Quality (scripts/quality.lua), against the real engine with the Quality mod and a player:
-- tools/test_mod.py runs it with `--test-scenario jatz-distribution-check/quality` whenever the
-- Quality mod is on (with Space Age). Every depot stands on one road; each pair deals in its own
-- item, so they never fetch from each other.
-- * Requests by quality, whatever the depots' and freighters' quality: rare iron plates only
--   (normal depots and freighters), any quality of copper plates (highest first: the first freighter
--   brings the legendary and rare ones, filling its two stacks), steel at least rare (an epic
--   request depot and a rare provider, normal freighters), and none of the other qualities.
-- * A better freighter: a rare one, alone in its depot, is made at its quality (its health the
--   game's for it), drives 1.6 times as fast, brings 3 stacks a trip (2 x 1.6, rounded down), and
--   parks with a 32 MJ tank.
-- * Better depots: a rare request depot's chest and a rare liquid depot's tank are the game's bigger
--   ones, and a rare Fuel depot's hidden tank is rare too.
-- * Upgrades: a request depot robots upgrade to rare keeps its request and freighters; a provider a
--   player builds a rare one over keeps its priority and robot access.
-- * Blueprints: a request for at least rare keeps its quality and comparator in its tag, and its
--   settings' signal is rare, so a depot built from the blueprint asks for the same.
-- Writes script-output/jatz-quality-check.json.
local ROAD_Y = 2
local REMOTE = "jatz-distribution"

local function depot(surface, role, x, grade)
  local entity = surface.create_entity({
    name = "jatz-" .. role .. "-depot",
    position = { x, 0.5 },
    force = "player",
    quality = grade,
    raise_built = true,
  })
  assert(entity, role .. " depot: not built at " .. x)
  return entity
end

local function stock(entity, item, stacks)
  local chest = entity.get_inventory(defines.inventory.chest)
  for grade, count in pairs(stacks) do
    assert(chest.insert({ name = item, count = count, quality = grade }) == count, item .. ": cannot stock " .. grade)
  end
end

local function by_quality(entity, item)
  return entity.get_inventory(defines.inventory.chest).get_item_quality_counts(item)
end

-- The freighters on the road (any paint) of quality `grade`.
local function freighters_of(surface, grade)
  local found = {}
  for _, unit in pairs(surface.find_entities_filtered({ type = "unit", force = "player" })) do
    if unit.name:find("^jatz%-freighter%-drone") and unit.quality.name == grade then
      found[#found + 1] = unit
    end
  end
  return found
end

script.on_event(defines.events.on_tick, function(event)
  local player = game.get_player(1)
  if not player then
    return
  end
  local surface = player.surface
  local result = storage.result
  if event.tick == 1 then
    surface.request_to_generate_chunks({ 0, 0 }, 3)
    surface.force_generate_chunk_requests()
    local tiles = {}
    for x = -60, 60 do
      for y = -30, 30 do
        tiles[#tiles + 1] = { name = y == ROAD_Y and "jatz-road" or "concrete", position = { x, y } }
      end
    end
    surface.set_tiles(tiles)
    for _, entity in pairs(surface.find_entities({ { -60, -30 }, { 60, 30 } })) do
      if entity.type ~= "character" then
        entity.destroy()
      end
    end
    surface.destroy_decoratives({})
    player.teleport({ 30, -4 })
    result = {}
    storage.result = result
    local pairs_ = {}
    storage.pairs = pairs_

    -- Rare iron plates only: normal depots, normal freighters.
    pairs_.rare = { provider = depot(surface, "provider", -55.5), request = depot(surface, "request", -49.5) }
    stock(pairs_.rare.provider, "iron-plate", { normal = 40, rare = 15, epic = 5 })
    assert(remote.call(REMOTE, "set_request", pairs_.rare.request, "iron-plate", 30, "rare"), "rare: refused")
    assert(remote.call(REMOTE, "add_freighters", pairs_.rare.request, 2) == 2)

    -- Any quality of copper plates: highest first.
    pairs_.any = { provider = depot(surface, "provider", -43.5), request = depot(surface, "request", -37.5) }
    stock(pairs_.any.provider, "copper-plate", { normal = 40, rare = 15, legendary = 30 })
    assert(remote.call(REMOTE, "set_request", pairs_.any.request, "copper-plate", 85, nil, "any"), "any: refused")
    assert(remote.call(REMOTE, "add_freighters", pairs_.any.request, 1) == 1)

    -- Steel at least rare: an epic request depot, a rare provider, normal freighters.
    pairs_.at_least = {
      provider = depot(surface, "provider", -31.5, "rare"),
      request = depot(surface, "request", -25.5, "epic"),
    }
    stock(pairs_.at_least.provider, "steel-plate", { normal = 20, rare = 10, epic = 10 })
    assert(
      remote.call(REMOTE, "set_request", pairs_.at_least.request, "steel-plate", 50, "rare", ">="),
      "at least rare: refused"
    )
    assert(remote.call(REMOTE, "add_freighters", pairs_.at_least.request, 2) == 2)

    -- A rare freighter, alone in its depot, fetching stone.
    pairs_.freighter = { provider = depot(surface, "provider", -19.5), request = depot(surface, "request", -13.5) }
    stock(pairs_.freighter.provider, "stone", { normal = 500 })
    assert(remote.call(REMOTE, "set_request", pairs_.freighter.request, "stone", 500), "stone: refused")
    assert(remote.call(REMOTE, "add_freighters", pairs_.freighter.request, 1, "rare") == 1)

    -- Better depots: the game's 1.6 times a normal one's (rounded down), whatever the startup
    -- settings make that (the check mod's settings-updates.lua changes them all).
    local rare_request = depot(surface, "request", 40.5, "rare")
    local normal_request = depot(surface, "request", 34.5)
    result.rare_request_slots = #rare_request.get_inventory(defines.inventory.chest)
      == math.floor(#normal_request.get_inventory(defines.inventory.chest) * 1.6)
    local rare_liquid = depot(surface, "liquid-request", 46.5, "rare")
    -- (In whole units: the game's 1.6 times 25,000 is a hair over 40,000.)
    result.rare_liquid_capacity = math.floor(rare_liquid.get_fluid_capacity(1))
    assert(remote.call(REMOTE, "set_request", rare_liquid, "water", 100000), "water: refused")
    result.rare_liquid_request_capped = remote.call(REMOTE, "get_request", rare_liquid).count
    local rare_fuel = depot(surface, "fuel", 52.5, "rare")
    local normal_fuel = depot(surface, "fuel", 58.5)
    result.rare_fuel_tank = math.floor(remote.call(REMOTE, "fuel_contents", rare_fuel).capacity)
      == math.floor(remote.call(REMOTE, "fuel_contents", normal_fuel).capacity * 1.6)

    -- Robots upgrading a request depot to rare: it keeps its request and freighters.
    local port = surface.create_entity({ name = "roboport", position = { 10, -12 }, force = "player" })
    port.get_inventory(defines.inventory.roboport_robot).insert({ name = "construction-robot", count = 20 })
    surface.create_entity({ name = "electric-energy-interface", position = { 14, -12 }, force = "player" })
    surface.create_entity({ name = "medium-electric-pole", position = { 12.5, -9.5 }, force = "player" })
    local store = surface.create_entity({ name = "storage-chest", position = { 8.5, -15.5 }, force = "player" })
    store.insert({ name = "jatz-request-depot", quality = "rare", count = 1 })
    local upgraded = depot(surface, "request", 4.5)
    assert(remote.call(REMOTE, "set_request", upgraded, "wood", 7), "wood: refused")
    assert(remote.call(REMOTE, "add_freighters", upgraded, 3) == 3)
    assert(
      upgraded.order_upgrade({ target = { name = "jatz-request-depot", quality = "rare" }, force = "player" }),
      "upgrade: refused"
    )
    storage.upgraded_at = upgraded.position

    -- A player building a rare provider over a normal one: it keeps its priority and robot access.
    local replaced = depot(surface, "provider", 28.5)
    assert(remote.call(REMOTE, "set_priority", replaced, 7))
    assert(remote.call(REMOTE, "set_robot_access", replaced, true))
    local at, old_id = replaced.position, replaced.unit_number
    player.cursor_stack.set_stack({ name = "jatz-provider-depot", quality = "rare", count = 1 })
    player.build_from_cursor({ position = at })
    local now = surface.find_entities_filtered({ name = "jatz-provider-depot", position = at })[1]
    result.replaced_by_player = now
        and {
          quality = now.quality.name,
          new = now.unit_number ~= old_id,
          priority = remote.call(REMOTE, "get_priority", now),
          robot_access = remote.call(REMOTE, "get_robot_access", now),
        }
      or "not replaced"

    -- A blueprint of a request depot asking for at least rare: tag and settings keep the quality.
    local source = depot(surface, "request", 16.5)
    assert(remote.call(REMOTE, "set_request", source, "iron-gear-wheel", 20, "rare", "≥"), "gears: refused")
    local holder = game.create_inventory(1)
    holder.insert({ name = "blueprint" })
    local blueprint = holder[1]
    local mapping =
      blueprint.create_blueprint({ surface = surface, force = "player", area = { { 15, -1 }, { 18, 2 } } })
    remote.call(REMOTE, "setup_blueprint", blueprint, mapping)
    local tag, signal, comparator
    for _, entry in pairs(blueprint.get_blueprint_entities()) do
      if entry.name == "jatz-request-depot" then
        tag = entry.tags and entry.tags.jatz_request
      elseif entry.name == "jatz-depot-settings" then
        local condition = entry.control_behavior.decider_conditions.conditions[1]
        signal = condition.first_signal
        comparator = entry.tags and entry.tags.jatz_quality_comparator
      end
    end
    result.blueprint_tag = tag and { quality = tag.quality, comparator = tag.comparator } or "none"
    result.blueprint_settings = signal and { quality = signal.quality, comparator = comparator } or "none"
    local revived
    for _, ghost in
      pairs(blueprint.build_blueprint({ surface = surface, force = "player", position = { 22.5, -22.5 } }))
    do
      if ghost.valid then
        local _, entity = ghost.revive({ raise_revive = true })
        revived = entity or revived
      end
    end
    local built = revived and remote.call(REMOTE, "get_request", revived)
    result.blueprint_built = built and { quality = built.quality, comparator = built.comparator } or "none"
  elseif result and not result.freighter then
    -- The rare freighter on its way: its quality, health and speed.
    local seen = freighters_of(surface, "rare")[1]
    if seen then
      local base = prototypes.entity["jatz-freighter-drone"].speed
      result.freighter = {
        health = seen.max_health,
        speed = math.floor(seen.speed / base * 100 + 0.5) / 100,
      }
    end
  end
  if result and storage.pairs then
    -- What the copper depot's first freighter brought, by quality.
    local copper = storage.pairs.any.request
    if not result.any_first and next(by_quality(copper, "copper-plate")) then
      result.any_first = by_quality(copper, "copper-plate")
    end
    -- What the rare freighter brought on its first trip.
    local stone = storage.pairs.freighter.request.get_inventory(defines.inventory.chest).get_item_count("stone")
    if not result.freighter_first_load and stone > 0 then
      result.freighter_first_load = stone
    end
  end
  if result and event.tick == 1800 then
    local pairs_ = storage.pairs
    result.rare_received = by_quality(pairs_.rare.request, "iron-plate")
    result.rare_left = by_quality(pairs_.rare.provider, "iron-plate")
    result.any_received = by_quality(pairs_.any.request, "copper-plate")
    result.at_least_received = by_quality(pairs_.at_least.request, "steel-plate")
    result.at_least_left = by_quality(pairs_.at_least.provider, "steel-plate")
    local fuel = remote.call(REMOTE, "freighter_fuel", pairs_.freighter.request)
    local tanks = fuel.home_tanks and fuel.home_tanks[1] or fuel.out_tanks and fuel.out_tanks[1] or fuel.capacity
    result.freighter_tank = tanks / 1000000
    local upgraded = surface.find_entities_filtered({ name = "jatz-request-depot", position = storage.upgraded_at })[1]
    local request = upgraded and remote.call(REMOTE, "get_request", upgraded)
    local in_slot, out = 0, 0
    if upgraded then
      in_slot, out = remote.call(REMOTE, "freighter_counts", upgraded)
    end
    result.upgraded_by_robots = upgraded
        and {
          quality = upgraded.quality.name,
          request = request and (request.item .. " x" .. request.count) or "none",
          freighters = in_slot + out,
        }
      or "not upgraded"
    helpers.write_file("jatz-quality-check.json", helpers.table_to_json(result))
    script.finish_test(true)
  end
end)
