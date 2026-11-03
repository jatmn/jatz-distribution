-- SPDX-License-Identifier: LGPL-3.0-only
-- Checks that every Jat'z Distribution item is free to craft and can be placed, that every
-- depot works in all four directions with its pipe ports, that the freighter can be driven, and
-- that freighters deliver from provider to request depots driving only on road.
-- Writes script-output/jatz-distribution-check.json; tools/test_mod.py runs it headless.

local FREIGHTER = "jatz-quinityn-freighter"
local ROLES = { "provider", "request", "buffer", "fuel", "liquid-provider", "liquid-request", "liquid-buffer" }
local HEADINGS = { defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west }
local VECTORS = { [0] = { 0, -1 }, [4] = { 1, 0 }, [8] = { 0, 1 }, [12] = { -1, 0 } }
local DRIVE_TICKS = 120
local ROAD = "jatz-road"
local DRONE = "jatz-freighter-drone"
-- Deliveries have this long to finish; tools/test_mod.py runs a little longer.
local DELIVERY_DEADLINE = 1700
-- A failed route must have been tried and reported before the report is written.
local DELIVERY_SETTLE = 600
-- The designed pipe ports (assets/depots/README.md, "Using it in Factorio"), written out here
-- independently of the generated depot definitions the prototypes are built from, so a port
-- moved in the data fails this check. Unrotated positions in tiles; directions face outward.
local EXPECTED_PORTS = {
  provider = {},
  request = {},
  buffer = {},
  -- Shown half a turn from its artwork so its opening faces south: the port is on the east.
  fuel = { { x = 1, y = 0, direction = defines.direction.east } },
  ["liquid-provider"] = { { x = 0, y = -1, direction = defines.direction.north } },
  ["liquid-request"] = { { x = 0, y = -1, direction = defines.direction.north } },
  ["liquid-buffer"] = {
    { x = -1, y = -1, direction = defines.direction.north },
    { x = 1, y = -1, direction = defines.direction.north },
  },
}

local function rotated(x, y, turns)
  for _ = 1, turns do
    x, y = -y, x
  end
  return x, y
end

-- Where our items must appear in the crafting menu and Factoriopedia, in order.
local ROW = {
  "jatz-provider-depot",
  "jatz-request-depot",
  "jatz-buffer-depot",
  "jatz-liquid-provider-depot",
  "jatz-liquid-request-depot",
  "jatz-liquid-buffer-depot",
  "jatz-fuel-depot",
  FREIGHTER,
  ROAD,
}

-- Our row must be in the car and tank's tab, directly above their row, and in ROW order.
local function check_menu_placement(result)
  local ours, transport = prototypes.item_subgroup["jatz-distribution"], prototypes.item_subgroup["transport"]
  assert(ours.group.name == transport.group.name, "our row must be in the car and tank's tab")
  assert(ours.order < transport.order, "our row must come before the car and tank row")
  for name, subgroup in pairs(prototypes.item_subgroup) do
    if subgroup.group.name == ours.group.name and name ~= ours.name and name ~= transport.name then
      assert(
        not (subgroup.order > ours.order and subgroup.order < transport.order),
        name .. " sits between our row and the car row"
      )
    end
  end
  for index, name in ipairs(ROW) do
    local item = prototypes.item[name]
    assert(item.subgroup.name == ours.name, name .. ": not in our row")
    if index > 1 then
      assert(prototypes.item[ROW[index - 1]].order < item.order, name .. ": out of order in our row")
    end
  end
  result.menu_tab = ours.group.name
  result.menu_row_order = ours.order
  result.car_row_order = transport.order
end

local function locale_key(localised)
  return type(localised) == "table" and localised[1] or localised
end

local function check_recipe(name, result)
  local item = prototypes.item[name]
  assert(item and item.place_result and item.place_result.name == name, name .. ": item must place the entity")
  -- tools/test_mod.py checks that each of these keys has an English translation.
  result.localised_names[name] = {
    entity = locale_key(item.place_result.localised_name),
    item = locale_key(item.localised_name),
    recipe = locale_key(prototypes.recipe[name].localised_name),
  }
  local recipe = game.forces.player.recipes[name]
  assert(recipe and recipe.enabled, name .. ": recipe must be available from the start")
  assert(#recipe.ingredients == 0, name .. ": recipe must be free")
  assert(#recipe.products == 1 and recipe.products[1].name == name, name .. ": recipe must make the item")
  result.free_recipes = result.free_recipes + 1
end

local function check_port_layout(name, role)
  local expected = EXPECTED_PORTS[role]
  local fluidboxes = prototypes.entity[name].fluidbox_prototypes
  if #expected == 0 then
    assert(#fluidboxes == 0, name .. ": a cargo depot must not have pipe ports")
    return
  end
  assert(#fluidboxes == 1, name .. ": expected one fluid box")
  local connections = fluidboxes[1].pipe_connections
  assert(#connections == #expected, name .. ": wrong number of pipe ports")
  for _, port in ipairs(expected) do
    local found = false
    for _, connection in ipairs(connections) do
      local position = connection.positions[1]
      found = found or (position.x == port.x and position.y == port.y and connection.direction == port.direction)
    end
    assert(found, string.format("%s: no port at (%d, %d) facing %d", name, port.x, port.y, port.direction))
  end
end

local function check_depot(surface, role, row, result)
  local name = "jatz-" .. role .. "-depot"
  check_recipe(name, result)
  check_port_layout(name, role)
  for index, heading in ipairs(HEADINGS) do
    local position = { -30 + (index - 1) * 16 + 0.5, -56 + row * 8 + 0.5 }
    local ghost = surface.create_entity({
      name = "entity-ghost",
      inner_name = name,
      position = position,
      direction = heading,
      force = "player",
    })
    assert(ghost and ghost.direction == heading, name .. ": ghost direction")
    ghost.destroy()
    result.ghosts = result.ghosts + 1
    assert(
      surface.can_place_entity({ name = name, position = position, direction = heading, force = "player" }),
      name .. ": cannot place"
    )
    local entity = surface.create_entity({ name = name, position = position, direction = heading, force = "player" })
    assert(entity and entity.direction == heading, name .. ": placed direction")
    result.placed = result.placed + 1
    for step = 1, 4 do
      assert(entity.rotate({}), name .. ": rotation failed")
      assert(entity.direction == HEADINGS[(index - 1 + step) % 4 + 1], name .. ": rotation direction")
      result.rotations = result.rotations + 1
    end
    for _, port in ipairs(EXPECTED_PORTS[role]) do
      local vector = VECTORS[port.direction]
      local x, y = rotated(port.x + vector[1], port.y + vector[2], index - 1)
      local pipe =
        surface.create_entity({ name = "pipe", position = { position[1] + x, position[2] + y }, force = "player" })
      local connected = false
      for _, connection in ipairs(entity.get_fluid_box_pipe_connections(1)) do
        connected = connected or connection.target == pipe
      end
      assert(connected, name .. ": pipe port did not connect")
      result.pipe_connections = result.pipe_connections + 1
    end
    if entity.type == "container" then
      assert(entity.insert({ name = "iron-plate", count = 10 }) == 10, name .. ": cannot store items")
    else
      local fluid = role == "fuel" and "light-oil" or "water"
      assert(entity.insert_fluid({ name = fluid, amount = 500 }) == 500, name .. ": cannot store fluid")
    end
  end
end

-- Building a depot clears decoratives whose footprint overlaps its loading zone tile, and only
-- those: a floor-layer sand rock on the zone goes, a desert bush two tiles further out stays.
local function check_loading_zone_clearing(surface, result)
  for row, role in ipairs(ROLES) do
    local name = "jatz-" .. role .. "-depot"
    for turn, heading in ipairs(HEADINGS) do
      local position = { 30 + (turn - 1) * 8 + 0.5, -56 + (row - 1) * 8 + 0.5 }
      local zx, zy = rotated(0, 2, turn - 1)
      local fx, fy = rotated(0, 4, turn - 1)
      local zone = { x = position[1] + zx - 0.5, y = position[2] + zy - 0.5 }
      local beyond = { x = position[1] + fx - 0.5, y = position[2] + fy - 0.5 }
      -- Decoratives grow on natural ground, not concrete: give them desert sand to sit on.
      surface.set_tiles({ { name = "sand-1", position = zone }, { name = "sand-1", position = beyond } })
      surface.create_decoratives({
        check_collision = false,
        decoratives = {
          { name = "medium-sand-rock", position = zone, amount = 1 },
          { name = "white-desert-bush", position = beyond, amount = 1 },
        },
      })
      assert(#surface.find_decoratives_filtered({ position = zone }) == 1, name .. ": test rock not placed")
      surface.create_entity({
        name = name,
        position = position,
        direction = heading,
        force = "player",
        raise_built = true,
      })
      assert(#surface.find_decoratives_filtered({ position = zone }) == 0, name .. ": loading zone not cleared")
      assert(
        #surface.find_decoratives_filtered({ position = beyond, name = "white-desert-bush" }) == 1,
        name .. ": cleared decoratives beyond the loading zone"
      )
      result.cleared_zones = result.cleared_zones + 1
    end
  end
end

-- The road item is free and lays the road tile.
local function check_road(result)
  local item = prototypes.item[ROAD]
  assert(item.place_as_tile_result and item.place_as_tile_result.result.name == ROAD, "road: item must lay the tile")
  result.localised_names[ROAD] = {
    tile = locale_key(prototypes.tile[ROAD].localised_name),
    item = locale_key(item.localised_name),
    recipe = locale_key(prototypes.recipe[ROAD].localised_name),
  }
  local recipe = game.forces.player.recipes[ROAD]
  assert(recipe and recipe.enabled and #recipe.ingredients == 0, "road: recipe must be free from the start")
  assert(recipe.products[1].name == ROAD, "road: recipe must make road")
  assert(not prototypes.tile[ROAD].collision_mask.layers.jatz_off_road, "road: must not be off-road")
  assert(prototypes.tile.concrete.collision_mask.layers.jatz_off_road, "concrete: must be off-road")
  result.free_recipes = result.free_recipes + 1
end

-- Lay road over every tile from one corner to the other (inclusive).
local function lay_road(surface, x1, y1, x2, y2)
  local tiles = {}
  for x = math.min(x1, x2), math.max(x1, x2) do
    for y = math.min(y1, y2), math.max(y1, y2) do
      tiles[#tiles + 1] = { name = ROAD, position = { x, y } }
    end
  end
  surface.set_tiles(tiles)
end

local function depot(surface, role, x, y)
  return surface.create_entity({
    name = "jatz-" .. role .. "-depot",
    position = { x, y },
    force = "player",
    raise_built = true,
  })
end

-- Three requests for iron plate, built as a player would, south of the other checks:
-- * connected: provider and request depots 20 tiles apart, joined by a U-shaped road that
--   detours 10 tiles south. The straight line between their loading zones is concrete, so the
--   freighter must follow the road there and back.
-- * island: a request depot whose loading zone is a single road tile, joined to nothing. A
--   freighter can't reach the provider, so nothing arrives.
-- * unpaved: a request depot with no road at its loading zone. No freighter is sent.
local function setup_deliveries(surface)
  -- Unrotated depots load from the tile two south of their centre.
  local provider = depot(surface, "provider", -60.5, 45.5)
  local connected = depot(surface, "request", -40.5, 45.5)
  lay_road(surface, -61, 47, -61, 57)
  lay_road(surface, -61, 57, -41, 57)
  lay_road(surface, -41, 47, -41, 57)
  local island = depot(surface, "request", -20.5, 45.5)
  lay_road(surface, -21, 47, -21, 47)
  local unpaved = depot(surface, "request", -20.5, 60.5)
  assert(provider.insert({ name = "iron-plate", count = 50 }) == 50, "provider: cannot stock")
  assert(remote.call("jatz-distribution", "set_request", connected, "iron-plate", 30), "request: not registered")
  assert(remote.call("jatz-distribution", "set_request", island, "iron-plate", 10), "island: not registered")
  assert(remote.call("jatz-distribution", "set_request", unpaved, "iron-plate", 10), "unpaved: not registered")
  local request = remote.call("jatz-distribution", "get_request", connected)
  assert(request.item == "iron-plate" and request.count == 30, "request: not stored")
  storage.deliveries = {
    provider = provider,
    connected = connected,
    island = island,
    unpaved = unpaved,
    road_samples = 0,
    deepest = 0,
  }
end

-- Every freighter on the way must stand wholly on road.
local function check_freighters_on_road(surface)
  local deliveries = storage.deliveries
  for _, drone in pairs(surface.find_entities_filtered({ name = DRONE })) do
    local box = drone.bounding_box
    for _, corner in ipairs({
      { box.left_top.x, box.left_top.y },
      { box.right_bottom.x - 0.001, box.left_top.y },
      { box.left_top.x, box.right_bottom.y - 0.001 },
      { box.right_bottom.x - 0.001, box.right_bottom.y - 0.001 },
    }) do
      local tile = surface.get_tile(math.floor(corner[1]), math.floor(corner[2]))
      assert(
        tile.name == ROAD,
        string.format("freighter off road on %s at (%.2f, %.2f)", tile.name, drone.position.x, drone.position.y)
      )
    end
    deliveries.road_samples = deliveries.road_samples + 1
    deliveries.deepest = math.max(deliveries.deepest, drone.position.y)
  end
end

local function count_iron(entity)
  return entity.get_inventory(defines.inventory.chest).get_item_count("iron-plate")
end

-- Once the connected request is stocked and no freighter is out, record what happened.
local function deliveries_finished(surface, tick, result)
  local deliveries = storage.deliveries
  local done = count_iron(deliveries.connected) >= 30 and #surface.find_entities_filtered({ name = DRONE }) == 0
  if not done or tick < DELIVERY_SETTLE then
    if tick >= DELIVERY_DEADLINE then
      error(
        string.format(
          "deliveries did not finish in time: request has %d iron (status %s), provider %d, %d freighter(s) out, %d on-road samples, deepest y %.1f",
          count_iron(deliveries.connected),
          tostring(remote.call("jatz-distribution", "get_status", deliveries.connected)),
          count_iron(deliveries.provider),
          #surface.find_entities_filtered({ name = DRONE }),
          deliveries.road_samples,
          deliveries.deepest
        )
      )
    end
    return false
  end
  result.delivered = count_iron(deliveries.connected)
  result.provider_left = count_iron(deliveries.provider)
  result.island_received = count_iron(deliveries.island)
  result.request_status = remote.call("jatz-distribution", "get_status", deliveries.connected)
  result.island_status = remote.call("jatz-distribution", "get_status", deliveries.island)
  result.unpaved_status = remote.call("jatz-distribution", "get_status", deliveries.unpaved)
  result.road_samples = deliveries.road_samples
  -- The road's south edge is the tile row at y 57; the straight route stays at y 47.
  result.detour = deliveries.deepest - 47.5
  assert(result.road_samples > 0, "no freighter was ever seen driving")
  assert(result.detour > 9, "the freighter did not follow the road south")
  return true
end

script.on_init(function()
  local surface = game.create_surface("jatz-check", { width = 160, height = 160 })
  surface.request_to_generate_chunks({ 0, 0 }, 3)
  surface.force_generate_chunk_requests()
  for _, entity in pairs(surface.find_entities()) do
    entity.destroy()
  end
  local tiles = {}
  for x = -72, 72 do
    for y = -72, 72 do
      tiles[#tiles + 1] = { name = "concrete", position = { x, y } }
    end
  end
  surface.set_tiles(tiles)
  -- Start without any map-generated decoratives, so the loading zone checks see only their own.
  surface.destroy_decoratives({})

  local result = {
    engine = script.active_mods.base,
    mod = script.active_mods["jatz-distribution"],
    free_recipes = 0,
    ghosts = 0,
    placed = 0,
    rotations = 0,
    pipe_connections = 0,
    localised_names = {},
    cleared_zones = 0,
  }
  for row, role in ipairs(ROLES) do
    check_depot(surface, role, row - 1, result)
  end
  check_loading_zone_clearing(surface, result)

  check_recipe(FREIGHTER, result)
  check_road(result)
  check_menu_placement(result)
  setup_deliveries(surface)
  local start = { 0.5, 30.5 }
  assert(surface.can_place_entity({ name = FREIGHTER, position = start, force = "player" }), "freighter: cannot place")
  local freighter = surface.create_entity({ name = FREIGHTER, position = start, force = "player" })
  assert(freighter.get_fuel_inventory().insert({ name = "coal", count = 50 }) == 50, "freighter: cannot fuel")
  local driver = surface.create_entity({ name = "character", position = { 3.5, 30.5 }, force = "player" })
  freighter.set_driver(driver)
  assert(freighter.get_driver() == driver, "freighter: cannot be entered")
  freighter.riding_state = {
    acceleration = defines.riding.acceleration.accelerating,
    direction = defines.riding.direction.straight,
  }
  storage.freighter = freighter
  storage.start = { x = freighter.position.x, y = freighter.position.y }
  storage.result = result
end)

script.on_event(defines.events.on_tick, function(event)
  local result = storage.result
  if not result or result.written then
    return
  end
  local surface = game.surfaces["jatz-check"]
  if event.tick % 10 == 0 then
    check_freighters_on_road(surface)
  end
  if not result.driven_tiles and event.tick >= DRIVE_TICKS then
    local freighter = storage.freighter
    local dx, dy = freighter.position.x - storage.start.x, freighter.position.y - storage.start.y
    result.driven_tiles = math.sqrt(dx * dx + dy * dy)
    result.speed = freighter.speed
    assert(result.driven_tiles > 1, "freighter: did not drive")
  end
  if result.driven_tiles and deliveries_finished(surface, event.tick, result) then
    result.written = true
    helpers.write_file("jatz-distribution-check.json", helpers.table_to_json(result), false)
    log("JATZ_DISTRIBUTION_CHECK passed")
  end
end)
