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

-- Road is built like any floor tile: from a ghost, on ordinary ground but not on water.
local function check_road_placement(surface, result)
  surface.set_tiles({ { name = "grass-1", position = { 66, 66 } }, { name = "water", position = { 68, 66 } } })
  for _, case in ipairs({ { 66, "road_on_grass" }, { 68, "road_on_water" } }) do
    local ghost = surface.create_entity({
      name = "tile-ghost",
      inner_name = ROAD,
      position = { case[1], 66 },
      force = "player",
    })
    if ghost then
      ghost.revive()
    end
    result[case[2]] = surface.get_tile(case[1], 66).name == ROAD
  end
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

-- Every depot lays road under its loading zone sign, and takes it away again when removed, but
-- only road it laid itself. Row at y 9.5 (loading zones at y 11), west of the freighter's drive.
local function setup_depot_roads(surface, result)
  local function zone_tile(x, name)
    surface.set_tiles({ { name = name, position = { x, 11 } } })
  end
  local roads = {}
  storage.depot_roads = roads
  -- Road one tile short of each depot's loading zone still connects: a provider and a request
  -- depot on grass, with road between their zones but not on them.
  zone_tile(-67, "grass-1")
  zone_tile(-57, "grass-1")
  roads.provider = depot(surface, "provider", -66.5, 9.5)
  roads.request = depot(surface, "request", -56.5, 9.5)
  lay_road(surface, -66, 11, -58, 11)
  result.depot_road_laid = surface.get_tile(-67, 11).name
  result.depot_road_hides = surface.get_hidden_tile({ -67, 11 })
  assert(roads.provider.insert({ name = "small-electric-pole", count = 5 }) == 5, "poles: cannot stock")
  assert(remote.call("jatz-distribution", "set_request", roads.request, "small-electric-pole", 5), "poles: refused")
  -- Removing a depot puts back what its road covered: concrete, and grass.
  roads.on_concrete = depot(surface, "provider", -46.5, 9.5)
  zone_tile(-41, "grass-1")
  roads.on_grass = depot(surface, "provider", -40.5, 9.5)
  -- Road already there isn't the depot's: it stays.
  zone_tile(-35, "jatz-road")
  roads.on_road = depot(surface, "provider", -34.5, 9.5)
  result.road_kept_on_build = surface.get_tile(-35, 11).name
  -- A tile placed over the depot's road is the player's: it stays.
  roads.covered = depot(surface, "provider", -28.5, 9.5)
  surface.set_tiles({ { name = "stone-path", position = { -29, 11 } } })
  -- Nothing is laid on water.
  zone_tile(-23, "water")
  roads.on_water = depot(surface, "provider", -22.5, 9.5)
  result.water_left = surface.get_tile(-23, 11).name
  for _, key in ipairs({ "on_concrete", "on_grass", "on_road", "covered", "on_water" }) do
    roads[key].destroy()
  end
  -- Two depots loading from one tile: the road stays until the second goes.
  roads.shared_a = depot(surface, "provider", 40.5, 9.5)
  roads.shared_b = depot(surface, "provider", 40.5, 13.5)
  roads.shared_b.direction = defines.direction.south
  roads.shared_b.destroy()
  roads.shared_b = surface.create_entity({
    name = "jatz-provider-depot",
    position = { 40.5, 13.5 },
    direction = defines.direction.south,
    force = "player",
    raise_built = true,
  })
  roads.shared_a.destroy()
end

-- Requests built as a player would, south and north-west of the other checks. Each uses its own
-- item, so no request can be served by another check's provider.
-- * connected: provider and request depots 20 tiles apart, joined by a U-shaped road that
--   detours 10 tiles south. The straight line between their loading zones is concrete, so the
--   freighter must follow the road there and back.
-- * island: a request depot whose loading zone is a single road tile, joined to nothing. A
--   freighter can't reach the provider, so nothing arrives.
-- * unpaved: a request depot with no road at its loading zone. No freighter is sent.
-- The rest are pairs 12 or 24 tiles apart on a straight road (see pair()).
local function setup_deliveries(surface, result)
  -- Unrotated depots load from the tile two south of their centre.
  local provider = depot(surface, "provider", -60.5, 45.5)
  local connected = depot(surface, "request", -40.5, 45.5)
  lay_road(surface, -61, 47, -61, 57)
  lay_road(surface, -61, 57, -41, 57)
  lay_road(surface, -41, 47, -41, 57)
  local island = depot(surface, "request", -20.5, 45.5)
  lay_road(surface, -21, 47, -21, 47)
  local unpaved = depot(surface, "request", -20.5, 60.5)
  -- Depots lay road under their loading zone; cover it, as a player paving over it would.
  assert(surface.get_tile(-21, 62).name == "jatz-depot-road", "unpaved: depot laid no road")
  surface.set_tiles({ { name = "concrete", position = { -21, 62 } } })
  assert(provider.insert({ name = "iron-plate", count = 50 }) == 50, "provider: cannot stock")
  assert(remote.call("jatz-distribution", "set_request", connected, "iron-plate", 30), "request: not registered")
  assert(remote.call("jatz-distribution", "set_request", island, "iron-plate", 10), "island: not registered")
  assert(remote.call("jatz-distribution", "set_request", unpaved, "iron-plate", 10), "unpaved: not registered")
  local request = remote.call("jatz-distribution", "get_request", connected)
  assert(request.item == "iron-plate" and request.count == 30, "request: not stored")
  local deliveries = {
    provider = provider,
    connected = connected,
    island = island,
    unpaved = unpaved,
    road_samples = 0,
    deepest = 0,
  }
  storage.deliveries = deliveries

  -- A provider at (x, y) and a request depot `apart` tiles east, joined by a straight road
  -- between their loading zones; the provider holds `stock`, the request asks for `count`.
  local function pair(x, y, apart, item, stock, count)
    local from = depot(surface, "provider", x + 0.5, y + 0.5)
    local to = depot(surface, "request", x + apart + 0.5, y + 0.5)
    lay_road(surface, x, y + 2, x + apart, y + 2)
    assert(from.insert({ name = item, count = stock }) == stock, item .. ": cannot stock")
    assert(remote.call("jatz-distribution", "set_request", to, item, count), item .. ": request refused")
    return { provider = from, request = to, item = item }
  end

  -- Item data survives the trip: armor keeps the equipment in its grid.
  deliveries.armor = pair(-66, 2, 12, "modular-armor", 1, 1)
  local armor = deliveries.armor.provider.get_inventory(defines.inventory.chest).find_item_stack("modular-armor")
  assert(armor.grid.put({ name = "solar-panel-equipment" }), "armor: cannot equip")
  -- Space Age: food keeps how far it has spoiled.
  if prototypes.item.yumako then
    deliveries.food = pair(-46, 2, 12, "yumako", 20, 20)
    local food = deliveries.food.provider.get_inventory(defines.inventory.chest).find_item_stack("yumako")
    food.spoil_percent = 0.5
  end
  -- A request depot with no room: nothing is fetched, nothing is spilled.
  deliveries.full = pair(-26, 2, 12, "copper-plate", 50, 10)
  local chest = deliveries.full.request.get_inventory(defines.inventory.chest)
  chest.insert({ name = "stone", count = #chest * 50 })
  assert(chest.get_insertable_count("copper-plate") == 0, "full: request depot still has room")
  -- A freighter destroyed on its way: the request sends another and is filled.
  deliveries.destroyed = pair(20, 2, 12, "steel-plate", 30, 30)
  -- The request changes to another item while the freighter is on its way out: it must not load
  -- the old item.
  deliveries.changed = pair(40, 2, 12, "plastic-bar", 20, 10)
  -- The road is cut behind a loaded freighter: it brings the cargo back to the provider, at once.
  deliveries.cut = pair(20, 20, 24, "iron-gear-wheel", 30, 20)
  -- A road with a gap: the first trip fails; mending the road sends a freighter at once, without
  -- waiting for the retry cooldown.
  deliveries.mended = pair(-66, 20, 12, "pipe", 20, 20)
  surface.set_tiles({ { name = "concrete", position = { -60, 22 } } })
  -- Two providers on one road; the nearer one is removed while a freighter heads for it: the
  -- freighter goes on to the other.
  deliveries.rerouted = pair(-46, 20, 20, "stone-brick", 10, 10)
  deliveries.rerouted.nearer = depot(surface, "provider", -37.5, 20.5)
  assert(deliveries.rerouted.nearer.insert({ name = "stone-brick", count = 10 }) == 10, "brick: cannot stock")
  -- Nearest by road, not in a straight line: the request depot's nearer provider (8 tiles away) is
  -- reachable only by a 34-tile U; a farther one (16 tiles) has a straight 16-tile road. The
  -- freighter must use the farther one.
  local shortest = {
    request = depot(surface, "request", 30.5, 45.5),
    near = depot(surface, "provider", 22.5, 45.5),
    far = depot(surface, "provider", 46.5, 45.5),
  }
  lay_road(surface, 30, 47, 46, 47)
  lay_road(surface, 22, 47, 22, 60)
  lay_road(surface, 22, 60, 30, 60)
  lay_road(surface, 30, 47, 30, 60)
  assert(shortest.near.insert({ name = "coal", count = 10 }) == 10, "coal: cannot stock")
  assert(shortest.far.insert({ name = "coal", count = 10 }) == 10, "coal: cannot stock")
  assert(remote.call("jatz-distribution", "set_request", shortest.request, "coal", 10), "coal: request refused")
  deliveries.shortest = shortest
  -- The request depot is removed while its freighter heads out: the freighter leaves, nothing moves.
  deliveries.orphaned = pair(50, 20, 12, "wooden-chest", 10, 10)

  -- Requests are validated, and clones keep them.
  local original = depot(surface, "request", 60.5, 45.5)
  assert(remote.call("jatz-distribution", "set_request", original, "wood", 5), "wood: request refused")
  result.bad_item_rejected = remote.call("jatz-distribution", "set_request", original, "no-such-item", 5) == false
    and remote.call("jatz-distribution", "set_request", original, "wood", "lots") == false
  local kept = remote.call("jatz-distribution", "get_request", original)
  result.refused_request_kept = kept ~= nil and kept.item == "wood" and kept.count == 5
  if not kept then
    remote.call("jatz-distribution", "set_request", original, "wood", 5)
  end
  local clone = original.clone({ position = { 60.5, 55.5 } })
  local cloned = remote.call("jatz-distribution", "get_request", clone)
  result.cloned_request = cloned and (cloned.item .. " x" .. cloned.count) or "none"
  result.request_cleared = remote.call("jatz-distribution", "set_request", clone, nil) == true
    and remote.call("jatz-distribution", "get_request", clone) == nil
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
        tile.name == ROAD or tile.name == "jatz-depot-road",
        string.format("freighter off road on %s at (%.2f, %.2f)", tile.name, drone.position.x, drone.position.y)
      )
    end
    deliveries.road_samples = deliveries.road_samples + 1
    if drone.position.x < -30 and drone.position.y > 40 then
      deliveries.deepest = math.max(deliveries.deepest, drone.position.y)
    end
  end
end

local function count(entity, item)
  return entity.get_inventory(defines.inventory.chest).get_item_count(item or "iron-plate")
end

local function status(entity)
  return remote.call("jatz-distribution", "get_status", entity)
end

-- Interfere with trips as they happen: destroy one freighter, change one request, cut one road.
local function interfere(surface)
  local roads = storage.depot_roads
  if game.tick == 30 then
    -- The first of two depots sharing a loading tile went at tick 0: the road is still there.
    roads.shared_kept = surface.get_tile(40, 11).name
    roads.shared_b.destroy()
  end
  local deliveries = storage.deliveries
  local destroyed = deliveries.destroyed
  if not destroyed.done and status(destroyed.request) == "delivering" then
    local drones = surface.find_entities_filtered({ name = DRONE, position = { 32.5, 4.5 }, radius = 3 })
    if #drones == 1 then
      drones[1].destroy()
      destroyed.done = true
    end
  end
  local changed = deliveries.changed
  if not changed.done and status(changed.request) == "delivering" then
    assert(remote.call("jatz-distribution", "set_request", changed.request, "electronic-circuit", 5), "change refused")
    changed.done = true
  end
  local cut = deliveries.cut
  if not cut.done and count(cut.provider, cut.item) < 30 then
    -- Loaded and about to head east: remove a road tile halfway, as a mod would, reporting it.
    surface.set_tiles({ { name = "concrete", position = { 32, 22 } } }, true, false, true, true)
    cut.done = game.tick
  end
  if cut.done and not cut.returned and count(cut.provider, cut.item) == 30 then
    cut.returned = game.tick
  end
  local mended = deliveries.mended
  if not mended.done and status(mended.request) == "unreachable" then
    surface.set_tiles({ { name = ROAD, position = { -60, 22 } } }, true, false, true, true)
    mended.done = game.tick
  end
  if mended.done and not mended.delivered and count(mended.request, mended.item) == 20 then
    mended.delivered = game.tick
  end
  -- The freighter that set off from a request depot's loading zone (centre 2 tiles south).
  local function freighter_of(entity)
    local drones = surface.find_entities_filtered({
      name = DRONE,
      position = { entity.position.x, entity.position.y + 2 },
      radius = 3,
    })
    return drones[1]
  end
  -- No freighter is ever sent from the isolated road tile: the route is known missing beforehand.
  if freighter_of(deliveries.island) then
    deliveries.island_sent = true
  end
  local rerouted = deliveries.rerouted
  if not rerouted.done and status(rerouted.request) == "delivering" then
    rerouted.freighter = freighter_of(rerouted.request)
    rerouted.nearer.destroy()
    rerouted.done = true
  end
  if rerouted.done and not rerouted.freighter.valid and count(rerouted.request, "stone-brick") < 10 then
    -- The freighter gave up instead of going on to the other provider.
    rerouted.replaced = true
  end
  local orphaned = deliveries.orphaned
  if not orphaned.done and status(orphaned.request) == "delivering" then
    orphaned.freighter = freighter_of(orphaned.request)
    orphaned.request.destroy()
    orphaned.done = game.tick
  end
  if orphaned.done and not orphaned.left and not orphaned.freighter.valid then
    orphaned.left = game.tick
  end
end

-- Once every trip has played out, record what happened.
local function deliveries_finished(surface, tick, result)
  local deliveries = storage.deliveries
  local armor, full, destroyed, changed, cut =
    deliveries.armor, deliveries.full, deliveries.destroyed, deliveries.changed, deliveries.cut
  local done = count(deliveries.connected) >= 30
    and count(armor.request, armor.item) == 1
    and (not deliveries.food or count(deliveries.food.request, "yumako") == 20)
    and destroyed.done
    and count(destroyed.request, destroyed.item) == 30
    and changed.done
    and cut.returned
    and deliveries.mended.delivered
    and count(deliveries.rerouted.request, "stone-brick") == 10
    and deliveries.orphaned.left
    and count(deliveries.shortest.request, "coal") == 10
    and count(storage.depot_roads.request, "small-electric-pole") == 5
    and #surface.find_entities_filtered({ name = DRONE }) == 0
  if not done or tick < DELIVERY_SETTLE then
    if tick >= DELIVERY_DEADLINE then
      error(
        string.format(
          "deliveries did not finish in time: iron %d (%s), armor %d, steel %d (destroyed %s), plastic change %s, gears back %d (cut %s, %s), pipes after mending %d (%s), bricks rerouted %d, %d freighter(s) out",
          count(deliveries.connected),
          tostring(status(deliveries.connected)),
          count(armor.request, armor.item),
          count(destroyed.request, destroyed.item),
          tostring(destroyed.done),
          tostring(changed.done),
          count(cut.provider, cut.item),
          tostring(cut.done),
          tostring(status(cut.request)),
          count(deliveries.mended.request, "pipe"),
          tostring(status(deliveries.mended.request)),
          count(deliveries.rerouted.request, "stone-brick"),
          #surface.find_entities_filtered({ name = DRONE })
        )
      )
    end
    return false
  end
  result.delivered = count(deliveries.connected)
  result.provider_left = count(deliveries.provider)
  result.island_received = count(deliveries.island)
  result.request_status = status(deliveries.connected)
  result.island_status = status(deliveries.island)
  result.unpaved_status = status(deliveries.unpaved)
  result.road_samples = deliveries.road_samples
  -- The road's south edge is the tile row at y 57; the straight route stays at y 47.
  result.detour = deliveries.deepest - 47.5
  assert(result.road_samples > 0, "no freighter was ever seen driving")
  assert(result.detour > 9, "the freighter did not follow the road south")
  local delivered = armor.request.get_inventory(defines.inventory.chest).find_item_stack("modular-armor")
  result.armor_equipment = delivered.grid and #delivered.grid.equipment or 0
  if deliveries.food then
    local food = deliveries.food.request.get_inventory(defines.inventory.chest).find_item_stack("yumako")
    result.food_spoiled = food.spoil_percent
    assert(food.spoil_percent >= 0.5, "food arrived fresher than it left")
  end
  result.full_status = status(full.request)
  result.full_provider_left = count(full.provider, full.item)
  result.redelivered_after_destroy = count(destroyed.request, destroyed.item)
  result.changed_provider_left = count(changed.provider, changed.item)
  result.changed_received = count(changed.request, changed.item)
  result.changed_status = status(changed.request)
  result.cut_returned = count(cut.provider, cut.item)
  result.cut_received = count(cut.request, cut.item)
  result.cut_status = status(cut.request)
  -- Without re-planning, a freighter stands stuck about six seconds before giving up.
  result.cut_turnaround = cut.returned - cut.done
  assert(result.cut_turnaround < 240, "the cut was noticed late: " .. result.cut_turnaround .. " ticks")
  -- Without a retry on road changes, the 10 s cooldown would hold this one back.
  result.mended_delay = deliveries.mended.delivered - deliveries.mended.done
  assert(result.mended_delay < 400, "the mended road was used late: " .. result.mended_delay .. " ticks")
  result.rerouted_received = count(deliveries.rerouted.request, "stone-brick")
  result.rerouted_from_farther = 10 - count(deliveries.rerouted.provider, "stone-brick")
  result.orphaned_provider_left = count(deliveries.orphaned.provider, "wooden-chest")
  result.shortest_from_far = 10 - count(deliveries.shortest.far, "coal")
  result.shortest_from_near = 10 - count(deliveries.shortest.near, "coal")
  result.island_freighter_sent = deliveries.island_sent == true
  local roads = storage.depot_roads
  result.connected_by_depot_roads = count(roads.request, "small-electric-pole")
  result.concrete_restored = surface.get_tile(-47, 11).name
  result.grass_restored = surface.get_tile(-41, 11).name
  result.road_kept_on_removal = surface.get_tile(-35, 11).name
  result.covered_kept = surface.get_tile(-29, 11).name
  result.shared_kept = roads.shared_kept
  result.shared_restored = surface.get_tile(40, 11).name
  -- The freighter heading for the removed provider went on to the other one itself.
  result.rerouted_same_freighter = not deliveries.rerouted.replaced
  -- The freighter of a removed request depot left at once, rather than driving on.
  result.orphaned_left_after = deliveries.orphaned.left - deliveries.orphaned.done
  assert(result.orphaned_left_after <= 2, "orphaned freighter kept driving: " .. result.orphaned_left_after .. " ticks")
  -- Nothing was left on the ground anywhere.
  result.spilled = surface.count_entities_filtered({ type = "item-entity" })
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
  -- Drawn at 75% of the artwork's scale, with the boxes scaled to match.
  local box = prototypes.entity[FREIGHTER].collision_box
  result.freighter_box = { box.right_bottom.x - box.left_top.x, box.right_bottom.y - box.left_top.y }
  check_road(result)
  check_road_placement(surface, result)
  setup_depot_roads(surface, result)
  check_menu_placement(result)
  setup_deliveries(surface, result)
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
  interfere(surface)
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
