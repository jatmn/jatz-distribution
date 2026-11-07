-- SPDX-License-Identifier: LGPL-3.0-only
-- Checks what every Jat'z Distribution recipe takes once researched, that each item can be placed,
-- that research unlocks the recipes and makes freighters faster and bigger, that every
-- depot works in all four directions with its pipe ports, that the freighter can be driven, and
-- that freighters deliver from provider to request depots driving only on road.
-- Writes script-output/jatz-distribution-check.json; tools/test_mod.py runs it headless.

local FREIGHTER = "jatz-quinityn-freighter"
-- With Space Age, its second recipe, fuelled with carbon.
local FREIGHTER_CARBON = "jatz-quinityn-freighter-carbon"
-- The mod's own research levels (scripts/research.lua), checked against the game's technologies.
local research = require("__jatz-distribution__/scripts/research")
local ROLES = { "provider", "request", "buffer", "fuel", "liquid-provider", "liquid-request", "liquid-buffer" }
local HEADINGS = { defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west }
local VECTORS = { [0] = { 0, -1 }, [4] = { 1, 0 }, [8] = { 0, 1 }, [12] = { -1, 0 } }
local DRIVE_TICKS = 120
local ROAD = "jatz-road"
-- The delivering freighter, empty; loaded ones are its painted twins (scripts/freighter-paint.lua),
-- so finding freighters looks for every one of them.
local DRONE = "jatz-freighter-drone"
local DRONES = { DRONE, DRONE .. "-loaded" }
for r = 0, 5 do
  for g = 0, 5 do
    for b = 0, 5 do
      DRONES[#DRONES + 1] = string.format("%s-%d%d%d", DRONE, r, g, b)
    end
  end
end
-- Iron plates take iron ore's map color, water its own (prototypes/freighter-colors.lua).
local IRON_PAINT, WATER_PAINT = DRONE .. "-233", DRONE .. "-023"
-- Stuck to the sticky pair's freighter as it reaches the provider, for this long (data.lua): it
-- wears off a little after loading, on the way home.
local STICKER, STICKER_TICKS = "jatz-check-sticker", 90
local MONITOR = "jatz-road-monitor"
-- Deliveries have this long to finish; tools/test_mod.py runs a little longer. The dry freighter
-- sets the pace: it waits out the 10-second retry after coal arrives at tick 300, then crawls to
-- the Fuel depot at a tenth of the drone's 0.066 tiles a tick before its round trip.
local DELIVERY_DEADLINE = 2500
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
  MONITOR,
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
  -- An upgrade level's name joins its technology's name and its number: { "", name, ... }.
  if type(localised) == "table" and localised[1] == "" then
    return locale_key(localised[2])
  end
  return type(localised) == "table" and localised[1] or localised
end

-- What a recipe takes, once researched: { time = seconds, ingredients = { [name] = amount },
-- made = amount }, for tools/test_mod.py to compare with its list. It must make one `product`.
local function record_recipe(name, product, result)
  local recipe = game.forces.player.recipes[name]
  assert(recipe and recipe.enabled, name .. ": recipe must be available once researched")
  assert(#recipe.products == 1 and recipe.products[1].name == product, name .. ": recipe must make " .. product)
  local ingredients = {}
  for _, ingredient in ipairs(recipe.ingredients) do
    ingredients[ingredient.name] = ingredient.amount
  end
  result.recipes[name] = { time = recipe.energy, ingredients = ingredients, made = recipe.products[1].amount }
end

-- unplaceable: the item must not place its entity, which stays defined but hidden (the freighter
-- without the jatz-freighter-drivable setting).
local function check_recipe(name, result, unplaceable)
  local item = prototypes.item[name]
  if unplaceable then
    assert(item and not item.place_result, name .. ": item must not place the entity")
    assert(prototypes.entity[name].hidden, name .. ": an entity no item places must be hidden")
  else
    assert(item and item.place_result and item.place_result.name == name, name .. ": item must place the entity")
  end
  -- tools/test_mod.py checks that each of these keys has an English translation.
  result.localised_names[name] = {
    entity = locale_key(prototypes.entity[name].localised_name),
    item = locale_key(item.localised_name),
    recipe = locale_key(prototypes.recipe[name].localised_name),
  }
  record_recipe(name, name, result)
end

-- The Fuel depot is a container; its port is on the hidden tank under it, which holds its liquid fuel.
local FUEL_TANK = "jatz-fuel-depot-tank"

-- Every recipe is locked until researched: the freight system unlocks its recipes, and the liquid
-- ones stay locked until liquid freight is researched after it, the road network monitor until its
-- own research.
local function check_research(result)
  local force = game.forces.player
  result.research_unlocks = {}
  for _, name in ipairs(research.unlocks) do
    local technology = prototypes.technology[name]
    local unlocks = { prerequisites = {}, recipes = {}, locked = 0, unlocked = 0 }
    for prerequisite in pairs(technology.prerequisites) do
      unlocks.prerequisites[#unlocks.prerequisites + 1] = prerequisite
    end
    table.sort(unlocks.prerequisites)
    for _, effect in ipairs(technology.effects) do
      if effect.type == "unlock-recipe" then
        unlocks.recipes[#unlocks.recipes + 1] = effect.recipe
        if not force.recipes[effect.recipe].enabled then
          unlocks.locked = unlocks.locked + 1
        end
      end
    end
    force.technologies[name].researched = true
    for _, recipe in ipairs(unlocks.recipes) do
      if force.recipes[recipe].enabled then
        unlocks.unlocked = unlocks.unlocked + 1
      end
    end
    result.research_unlocks[name] = unlocks
    result.localised_names[name] = { technology = locale_key(technology.localised_name) }
  end
  -- Speed: four levels, then an infinite one; item and fluid capacity: five levels each. Each after
  -- the one before; fluid capacity after liquid freight.
  local speed_top = prototypes.technology[research.speed .. "-" .. (research.speed_levels + 1)]
  result.speed_infinite = speed_top.max_level == 4294967295 and speed_top.research_unit_count_formula ~= nil
  result.research_levels = {}
  for name, upgrade in pairs({
    [research.speed] = { levels = research.speed_levels + 1, first = research.system },
    [research.item_capacity] = { levels = research.capacity_levels, first = research.system },
    [research.fluid_capacity] = { levels = research.capacity_levels, first = research.liquid },
  }) do
    for level = 1, upgrade.levels do
      local technology = prototypes.technology[name .. "-" .. level]
      local before = level > 1 and name .. "-" .. (level - 1) or upgrade.first
      assert(technology and technology.prerequisites[before], name .. "-" .. level .. ": must follow " .. before)
      result.localised_names[technology.name] = { technology = locale_key(technology.localised_name) }
    end
    result.research_levels[name] = upgrade.levels
  end
  -- The levels a force has, from the game's own technologies: four speed levels and the infinite
  -- one written to level 7 (5 and 6 done) are six; a new force has none.
  local researched = game.create_force("jatz-researched")
  local technologies = researched.technologies
  technologies[research.system].researched = true
  technologies[research.liquid].researched = true
  for level = 1, research.speed_levels do
    technologies[research.speed .. "-" .. level].researched = true
  end
  technologies[speed_top.name].level = 7
  for level = 1, 2 do
    technologies[research.item_capacity .. "-" .. level].researched = true
  end
  for level = 1, 3 do
    technologies[research.fluid_capacity .. "-" .. level].researched = true
  end
  result.researched_levels = {
    speed = research.levels(researched, research.speed),
    item_capacity = research.levels(researched, research.item_capacity),
    fluid_capacity = research.levels(researched, research.fluid_capacity),
    fresh = research.levels(game.create_force("jatz-unresearched"), research.speed),
  }
end

local function check_port_layout(name, role)
  local expected = EXPECTED_PORTS[role]
  if role == "fuel" then
    assert(#prototypes.entity[name].fluidbox_prototypes == 0, name .. ": the port belongs to its tank")
    name = FUEL_TANK
  end
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
    -- Built as a player would (raising the event), a Fuel depot gets its tank.
    local entity = surface.create_entity({
      name = name,
      position = position,
      direction = heading,
      force = "player",
      raise_built = role == "fuel",
    })
    assert(entity and entity.direction == heading, name .. ": placed direction")
    local tank = role == "fuel" and surface.find_entity(FUEL_TANK, position)
    assert(role ~= "fuel" or (tank and tank.direction == heading), name .. ": no tank facing as it does")
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
      for _, connection in ipairs((tank or entity).get_fluid_box_pipe_connections(1)) do
        connected = connected or connection.target == pipe
      end
      assert(connected, name .. ": pipe port did not connect")
      result.pipe_connections = result.pipe_connections + 1
    end
    -- Every depot takes a red wire, facing any way.
    local combinator = surface.create_entity({
      name = "constant-combinator",
      position = { position[1] + 4, position[2] },
      force = "player",
    })
    local red = defines.wire_connector_id.circuit_red
    assert(
      entity.get_wire_connector(red, true).connect_to(combinator.get_wire_connector(red, true), false),
      name .. ": no circuit wire"
    )
    assert(entity.get_circuit_network(red), name .. ": wired, but on no circuit network")
    combinator.destroy()
    result.wired_depots = result.wired_depots + 1
    if entity.type == "container" then
      assert(entity.insert({ name = "iron-plate", count = 10 }) == 10, name .. ": cannot store items")
    end
    if entity.type ~= "container" or tank then
      result.tank_sizes[role] = (tank or entity).get_fluid_capacity(1)
      local fluid = role == "fuel" and "light-oil" or "water"
      assert((tank or entity).insert_fluid({ name = fluid, amount = 500 }) == 500, name .. ": cannot store fluid")
    end
    if tank and index == 1 then
      -- Turned by a script, which raises no event: its tank must follow within a second.
      assert(entity.rotate({}), name .. ": rotation failed")
      storage.turned_fuel = { depot = entity, tank = tank, from = heading }
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
  record_recipe(ROAD, ROAD, result)
  assert(not prototypes.tile[ROAD].collision_mask.layers.jatz_off_road, "road: must not be off-road")
  assert(prototypes.tile.concrete.collision_mask.layers.jatz_off_road, "concrete: must be off-road")
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
  -- Nothing but belts, pipes, train tracks and vehicles can be built on road, and depots and their
  -- ghosts can't either; a depot's loading zone can be road (here the road just laid at 66, 66,
  -- south of an unrotated depot at 66.5, 64.5).
  local function can_place(name, position, check)
    return surface.can_place_entity({
      name = name,
      position = position,
      force = "player",
      build_check_type = defines.build_check_type[check or "manual"],
    })
  end
  result.depot_on_road = can_place("jatz-request-depot", { 66.5, 66.5 })
  result.depot_ghost_on_road = can_place("jatz-request-depot", { 66.5, 66.5 }, "manual_ghost")
  result.depot_zone_on_road = can_place("jatz-request-depot", { 66.5, 64.5 })
  result.on_road = {}
  for _, name in ipairs({ "small-electric-pole", "inserter", "wooden-chest", "transport-belt", "pipe", FREIGHTER }) do
    result.on_road[name] = can_place(name, { 66.5, 66.5 })
  end
  result.on_road["straight-rail"] = can_place("straight-rail", { 67, 67 })
  -- The road network monitor is a building like any other: beside road, never on it (freighters
  -- would drive through it).
  result.on_road[MONITOR] = can_place(MONITOR, { 66.5, 66.5 })
  result.monitor_beside_road = can_place(MONITOR, { 66.5, 67.5 })
  -- Road can't be laid under them either, a gate included while it stands open (an open gate
  -- uses its opened collision mask): an open gate, a closed one and a pole on grass, where
  -- `lay_road_under` tries road once the first is open.
  local under = {}
  for index, name in ipairs({ "gate", "gate", "small-electric-pole" }) do
    local position = { 70 + index * 2, 66 }
    surface.set_tiles({ { name = "grass-1", position = position } })
    under[index] = surface.create_entity({
      name = name,
      position = { position[1] + 0.5, position[2] + 0.5 },
      force = "player",
    })
  end
  under[1].request_to_open("player", 3600)
  storage.road_under = under
end

-- Once the open gate is fully open, try laying road under it, the closed gate and the pole, one
-- tile at a time, as building a tile does: refused wherever an entity collides with road.
local function lay_road_under(surface, result)
  local under = storage.road_under
  if result.road_under or not under[1].is_opened() then
    return
  end
  result.road_under = {}
  for index, key in ipairs({ "open_gate", "closed_gate", "pole" }) do
    local position = { 70 + index * 2, 66 }
    surface.set_tiles({ { name = ROAD, position = position } }, true, "abort_on_collision")
    result.road_under[key] = surface.get_tile(position[1], position[2]).name
  end
  result.road_under.gate_still_open = under[1].is_opened()
  result.road_under.gate_closed = under[2].is_closed()
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

-- Request and buffer depots get `trucks` freighters in their slot (3 unless given).
local function depot(surface, role, x, y, trucks, force)
  local entity = surface.create_entity({
    name = "jatz-" .. role .. "-depot",
    position = { x, y },
    force = force or "player",
    raise_built = true,
  })
  if (role == "request" or role == "buffer") and (trucks or 3) > 0 then
    local added = remote.call("jatz-distribution", "add_freighters", entity, trucks or 3)
    assert(added == (trucks or 3), "cannot stock freighters")
  end
  return entity
end

-- Freighters lying on the ground in an area, and other items there.
local function on_ground(surface, area)
  local freighters, other = 0, 0
  for _, item in pairs(surface.find_entities_filtered({ type = "item-entity", area = area })) do
    if item.stack.name == FREIGHTER then
      freighters = freighters + item.stack.count
    else
      other = other + 1
    end
  end
  return freighters, other
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
    -- Every cargo icon seen on a freighter.
    cargo_icons = {},
    -- Ticks the connected pair's freighter reached the provider's loading zone, loaded, got home
    -- and unloaded.
    stops = {},
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

  -- A force with six speed levels and two item capacity levels (check_research): its one freighter
  -- leaves at 2.2 times the speed and carries 12 stacks of iron plates (1200), not 10. Speed
  -- research undone while it is out (watch_researched) slows it down on the road.
  deliveries.researched = {
    provider = depot(surface, "provider", -65.5, -7.5, nil, "jatz-researched"),
    request = depot(surface, "request", -53.5, -7.5, 1, "jatz-researched"),
  }
  lay_road(surface, -66, -6, -54, -6)
  assert(deliveries.researched.provider.insert({ name = "iron-plate", count = 2000 }) == 2000, "researched: stock")
  assert(
    remote.call("jatz-distribution", "set_request", deliveries.researched.request, "iron-plate", 2000),
    "researched: request refused"
  )

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
  -- Something stuck to the freighter when it loads (interfere sticks a sticker to it): it keeps
  -- its paint, and the sticker, until the sticker wears off. A long road, so that is on the way.
  deliveries.sticky = pair(-10, 2, 24, "iron-plate", 10, 10)
  deliveries.sticky.road = { { -10, 3 }, { 14, 6 } }
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
  -- Enemies on the road. A medium biter, held still and ignoring everything, stands on the road
  -- between a provider and a request depot, beside a player: the freighter runs the biter over
  -- and drives on, and the player is unhurt.
  deliveries.runover = pair(-9, 64, 20, "iron-ore", 10, 10)
  local biter = surface.create_entity({ name = "medium-biter", position = { 1.5, 66.5 }, force = "enemy" })
  biter.commandable.set_command({ type = defines.command.stop, distraction = defines.distraction.none })
  deliveries.runover.biter_id = biter.unit_number
  deliveries.runover.bystander =
    surface.create_entity({ name = "character", position = { 5.5, 66.5 }, force = "player" })
  -- On a second road, behemoth biters are set on a freighter as it drives out: they destroy it,
  -- with any cargo it has loaded, and it explodes and leaves a wreck where it dies. Its depot
  -- asks robots for a replacement, which the roboport's robots bring. Its other freighters fill
  -- the request from the provider's other 10.
  deliveries.ambush = pair(-9, 54, 20, "copper-ore", 20, 10)
  -- Buffer depots, on one road (loading zones at y -25): a provider (100 copper cable), a request
  -- depot 10 tiles away set to request from buffer depots, a buffer depot right beside it asking
  -- for 15, and a buffer depot 20 tiles away holding 30 with no request of its own. The request
  -- depot takes its 20 from the farther buffer, not the nearer provider; the asking buffer fills
  -- from the provider only, never from the other buffer.
  local buffering = {
    provider = depot(surface, "provider", -66.5, -26.5),
    request = depot(surface, "request", -56.5, -26.5, 2),
    filling = depot(surface, "buffer", -46.5, -26.5, 2),
    stocked = depot(surface, "buffer", -36.5, -26.5, 0),
  }
  lay_road(surface, -67, -25, -37, -25)
  assert(buffering.provider.insert({ name = "copper-cable", count = 100 }) == 100, "cable: cannot stock")
  assert(buffering.stocked.insert({ name = "copper-cable", count = 30 }) == 30, "cable: cannot stock buffer")
  assert(remote.call("jatz-distribution", "set_request", buffering.request, "copper-cable", 20), "cable: refused")
  assert(remote.call("jatz-distribution", "set_from_buffers", buffering.request, true), "from buffers: refused")
  assert(remote.call("jatz-distribution", "set_request", buffering.filling, "copper-cable", 15), "buffer: refused")
  result.buffer_has_no_from_buffers = remote.call("jatz-distribution", "set_from_buffers", buffering.filling, true)
  deliveries.buffering = buffering
  -- Priority, on one road (loading zones at y -25): a request depot for 10 stone, a provider 10
  -- tiles away at priority 2 and one 30 tiles away at priority 9, each holding 20. The freighter
  -- goes to the farther one, for its higher priority.
  local prioritised = {
    request = depot(surface, "request", 20.5, -26.5, 1),
    near = depot(surface, "provider", 30.5, -26.5),
    far = depot(surface, "provider", 50.5, -26.5),
  }
  lay_road(surface, 20, -25, 50, -25)
  assert(prioritised.near.insert({ name = "stone", count = 20 }) == 20, "stone: cannot stock")
  assert(prioritised.far.insert({ name = "stone", count = 20 }) == 20, "stone: cannot stock")
  result.priority_default = remote.call("jatz-distribution", "get_priority", prioritised.near)
  assert(remote.call("jatz-distribution", "set_priority", prioritised.near, 2), "priority: refused")
  assert(remote.call("jatz-distribution", "set_priority", prioritised.far, 9), "priority: refused")
  result.request_has_no_priority = remote.call("jatz-distribution", "set_priority", prioritised.request, 9)
  assert(remote.call("jatz-distribution", "set_request", prioritised.request, "stone", 10), "stone: refused")
  deliveries.prioritised = prioritised
  -- Liquid depots, on one road (loading zones at y -35): a liquid request depot with 3 freighters
  -- asks for 1200 water from a liquid provider holding 2000, 500 a freighter.
  local liquid = {
    request = depot(surface, "liquid-request", 20.5, -36.5),
    provider = depot(surface, "liquid-provider", 30.5, -36.5),
  }
  lay_road(surface, 20, -35, 30, -35)
  assert(liquid.provider.insert_fluid({ name = "water", amount = 2000 }) == 2000, "water: cannot stock")
  assert(remote.call("jatz-distribution", "add_freighters", liquid.request, 3) == 3, "liquid: no freighters")
  result.liquid_refuses_items = remote.call("jatz-distribution", "set_request", liquid.request, "iron-plate", 10)
  result.item_depot_refuses_fluids = remote.call("jatz-distribution", "set_request", prioritised.request, "water", 10)
  assert(remote.call("jatz-distribution", "set_request", liquid.request, "water", 1200), "water: refused")
  result.truck_chests = #surface.find_entities_filtered({ name = "jatz-truck-chest", position = { 20.5, -36.5 } })
  result.provider_truck_chests =
    #surface.find_entities_filtered({ name = "jatz-truck-chest", position = { 30.5, -36.5 } })
  deliveries.liquid = liquid
  -- Liquid buffers (loading zones at y -45): a liquid request depot set to request from buffer
  -- depots asks for 300 steam; a liquid provider 10 tiles away holds 1000 at 165 degrees, a liquid
  -- buffer 30 tiles away 1000 at 500 degrees. The steam comes from the buffer, still at 500.
  local steam = {
    request = depot(surface, "liquid-request", 20.5, -46.5),
    provider = depot(surface, "liquid-provider", 30.5, -46.5),
    buffer = depot(surface, "liquid-buffer", 50.5, -46.5),
  }
  lay_road(surface, 20, -45, 50, -45)
  assert(steam.provider.insert_fluid({ name = "steam", amount = 1000, temperature = 165 }) == 1000, "steam")
  assert(steam.buffer.insert_fluid({ name = "steam", amount = 1000, temperature = 500 }) == 1000, "hot steam")
  assert(remote.call("jatz-distribution", "add_freighters", steam.request, 1) == 1, "steam: no freighters")
  assert(remote.call("jatz-distribution", "set_from_buffers", steam.request, true), "steam: from buffers refused")
  assert(remote.call("jatz-distribution", "set_request", steam.request, "steam", 300), "steam: refused")
  deliveries.steam = steam
  -- Liquid fallback (loading zones at y -15): a liquid request depot NOT set to request from
  -- buffer depots asks for 300 crude oil; the liquid provider 10 tiles away is empty, and a liquid
  -- buffer 30 tiles away holds 1000. With no provider able to supply it, the oil comes from the
  -- buffer.
  local fallback = {
    request = depot(surface, "liquid-request", 20.5, -16.5),
    provider = depot(surface, "liquid-provider", 30.5, -16.5),
    buffer = depot(surface, "liquid-buffer", 50.5, -16.5),
  }
  lay_road(surface, 20, -15, 50, -15)
  assert(fallback.buffer.insert_fluid({ name = "crude-oil", amount = 1000 }) == 1000, "oil: cannot stock buffer")
  assert(remote.call("jatz-distribution", "add_freighters", fallback.request, 1) == 1, "oil: no freighters")
  result.fallback_from_buffers = remote.call("jatz-distribution", "get_from_buffers", fallback.request)
  assert(remote.call("jatz-distribution", "set_request", fallback.request, "crude-oil", 300), "oil: refused")
  deliveries.fallback = fallback
  -- Fuel (loading zones at y 66). Each request depot has one freighter, its tank set low.
  -- * fuelled: fuel for 10 tiles and a provider 20 tiles east: it first drives 4 tiles west to a
  --   Fuel depot holding coal, fills up (5 coal for 20 MJ), then fetches 10 iron ore.
  -- * liquid_fuelled: the same with a Fuel depot holding 100 petroleum gas, which the mod makes
  --   burn at 0.4 MJ (data-final-fixes.lua): it takes 50, and fetches 10 copper ore.
  -- * dry: an empty tank, and the only Fuel depot on its road holds stone. The freighter can't
  --   reach the provider and stays home (status no-fuel), until coal is put in that Fuel depot
  --   (tick 300): then it sets off at once (delivering by tick 420), crawls there, fills up, and
  --   fetches 10 sulfur.
  local fuelled = {
    fuel = depot(surface, "fuel", -70.5, 64.5),
    request = depot(surface, "request", -66.5, 64.5, 1),
    provider = depot(surface, "provider", -46.5, 64.5),
  }
  lay_road(surface, -71, 66, -47, 66)
  assert(fuelled.fuel.insert({ name = "coal", count = 10 }) == 10, "fuel: cannot stock coal")
  assert(fuelled.provider.insert({ name = "iron-ore", count = 20 }) == 20, "ore: cannot stock")
  assert(remote.call("jatz-distribution", "set_freighter_fuel", fuelled.request, 100000) == 1, "fuel: not set")
  assert(remote.call("jatz-distribution", "set_request", fuelled.request, "iron-ore", 10), "ore: refused")
  deliveries.fuelled = fuelled
  local liquid_fuelled = {
    fuel = depot(surface, "fuel", -40.5, 64.5),
    request = depot(surface, "request", -34.5, 64.5, 1),
    provider = depot(surface, "provider", -24.5, 64.5),
  }
  lay_road(surface, -41, 66, -25, 66)
  liquid_fuelled.tank = surface.find_entity(FUEL_TANK, liquid_fuelled.fuel.position)
  assert(liquid_fuelled.tank.insert_fluid({ name = "petroleum-gas", amount = 100 }) == 100, "fuel: no gas")
  assert(liquid_fuelled.provider.insert({ name = "copper-ore", count = 20 }) == 20, "copper ore: cannot stock")
  assert(remote.call("jatz-distribution", "set_freighter_fuel", liquid_fuelled.request, 100000) == 1, "not set")
  assert(remote.call("jatz-distribution", "set_request", liquid_fuelled.request, "copper-ore", 10), "refused")
  deliveries.liquid_fuelled = liquid_fuelled
  local dry = {
    request = depot(surface, "request", -14.5, 64.5, 1),
    fuel = depot(surface, "fuel", -10.5, 64.5),
    provider = depot(surface, "provider", 5.5, 64.5),
  }
  lay_road(surface, -15, 66, 5, 66)
  assert(dry.fuel.insert({ name = "stone", count = 10 }) == 10, "dry: cannot stock stone")
  assert(dry.provider.insert({ name = "sulfur", count = 20 }) == 20, "sulfur: cannot stock")
  assert(remote.call("jatz-distribution", "set_freighter_fuel", dry.request, 0) == 1, "dry: not set")
  assert(remote.call("jatz-distribution", "set_request", dry.request, "sulfur", 10), "sulfur: refused")
  deliveries.dry = dry
  -- Freighters, one after another, from more than one provider: a request depot with 5 freighters
  -- asks for 60 iron sticks; the provider 10 tiles away has 30, the one 30 tiles away 40.
  local multi = {
    request = depot(surface, "request", -66.5, 28.5, 5),
    near = depot(surface, "provider", -56.5, 28.5),
    far = depot(surface, "provider", -36.5, 28.5),
    seen = {},
  }
  lay_road(surface, -67, 30, -37, 30)
  assert(multi.near.insert({ name = "iron-stick", count = 30 }) == 30, "sticks: cannot stock")
  assert(multi.far.insert({ name = "iron-stick", count = 40 }) == 40, "sticks: cannot stock")
  assert(remote.call("jatz-distribution", "set_request", multi.request, "iron-stick", 60), "sticks: refused")
  deliveries.multi = multi
  -- No freighters: nothing is sent, and the depot says so.
  -- Circuit conditions and the road network monitor (loading zones at y 39). On one road: a
  -- request depot for 10 stone walls, a provider holding 20 switched off by a combinator until
  -- tick 300 (signal-A > 0), a liquid provider holding 1000 water, and a monitor beside the road.
  -- On another: a request depot for 10 small lamps, switched off by a combinator until tick 300
  -- (signal-B > 0), and a provider holding them.
  local function combinator(x, y, target)
    local entity = surface.create_entity({ name = "constant-combinator", position = { x, y }, force = "player" })
    local red = defines.wire_connector_id.circuit_red
    assert(target.get_wire_connector(red, true).connect_to(entity.get_wire_connector(red, true), false), "no wire")
    entity.get_or_create_control_behavior().add_section()
    return entity
  end
  local circuit = {
    request = depot(surface, "request", 0.5, 37.5, 1),
    gated = depot(surface, "provider", 10.5, 37.5),
    water = depot(surface, "liquid-provider", 20.5, 37.5),
    lamps = depot(surface, "request", 30.5, 37.5, 1),
    lamp_provider = depot(surface, "provider", 40.5, 37.5),
  }
  lay_road(surface, 0, 39, 20, 39)
  lay_road(surface, 30, 39, 40, 39)
  assert(circuit.gated.insert({ name = "stone-wall", count = 20 }) == 20, "walls: cannot stock")
  assert(circuit.water.insert_fluid({ name = "water", amount = 1000 }) == 1000, "water: cannot stock")
  assert(circuit.lamp_provider.insert({ name = "small-lamp", count = 10 }) == 10, "lamps: cannot stock")
  circuit.switch_a = combinator(13.5, 40.5, circuit.gated)
  circuit.switch_b = combinator(33.5, 40.5, circuit.lamps)
  local function signal(name)
    return { type = "virtual", name = name }
  end
  assert(
    remote.call(
      "jatz-distribution",
      "set_circuit",
      circuit.gated,
      true,
      { first_signal = signal("signal-A"), comparator = ">", constant = 0 }
    ),
    "provider condition refused"
  )
  assert(
    remote.call(
      "jatz-distribution",
      "set_circuit",
      circuit.lamps,
      true,
      { first_signal = signal("signal-B"), comparator = ">", constant = 0 }
    ),
    "request condition refused"
  )
  result.circuit_refused_elsewhere = remote.call("jatz-distribution", "set_circuit", circuit.switch_a, true, {})
  assert(remote.call("jatz-distribution", "set_request", circuit.request, "stone-wall", 10), "walls: refused")
  assert(remote.call("jatz-distribution", "set_request", circuit.lamps, "small-lamp", 10), "lamps: refused")
  -- The monitor, beside the first road, wired to a pole so its signals can be read.
  circuit.monitor =
    surface.create_entity({ name = MONITOR, position = { 5.5, 40.5 }, force = "player", raise_built = true })
  local pole = surface.create_entity({ name = "medium-electric-pole", position = { 7.5, 41.5 }, force = "player" })
  local red = defines.wire_connector_id.circuit_red
  assert(
    circuit.monitor.get_wire_connector(red, true).connect_to(pole.get_wire_connector(red, true), false),
    "monitor: no wire"
  )
  result.monitor_operable = circuit.monitor.operable
  -- Two more monitors on the same road, reading what request depots hold and what they still need.
  circuit.readings = {}
  for reading, x in pairs({ requests = 9.5, needs = 11.5 }) do
    local monitor =
      surface.create_entity({ name = MONITOR, position = { x, 40.5 }, force = "player", raise_built = true })
    assert(remote.call("jatz-distribution", "set_monitor_reading", monitor, reading), reading .. ": refused")
    circuit.readings[reading] = monitor
  end
  -- Copy and Paste settings from a constant combinator switched off, whose section is multiplied by
  -- 3 and belongs to a named group another combinator shares (signal-A = 123), onto a monitor on
  -- the same road: the monitor must show its own reading, and the group must stay as it is.
  circuit.pasted =
    surface.create_entity({ name = MONITOR, position = { 17.5, 40.5 }, force = "player", raise_built = true })
  circuit.grouped = {}
  for index, x in ipairs({ 17.5, 19.5 }) do
    local grouped = surface.create_entity({ name = "constant-combinator", position = { x, 43.5 }, force = "player" })
    local behavior = grouped.get_or_create_control_behavior()
    local section = behavior.get_section(1) or behavior.add_section()
    section.group = "jatz-check shared"
    if index == 1 then
      section.filters = {
        { value = { type = "virtual", name = "signal-A", quality = "normal", comparator = "=" }, min = 123 },
      }
      section.multiplier = 3
      behavior.enabled = false
    end
    circuit.grouped[index] = grouped
  end
  circuit.pasted.copy_settings(circuit.grouped[1])
  result.monitor_readings_refused = remote.call("jatz-distribution", "set_monitor_reading", circuit.monitor, "all")
  result.monitor_reading_default = remote.call("jatz-distribution", "get_monitor_reading", circuit.monitor)
  deliveries.circuit = circuit
  -- What a condition reads (loading zones at y 39, x 50 to 62). On one road, three providers:
  -- "wired" holding 300 wood, wired red to "remote" holding 2800; and "monitored" holding 300,
  -- wired green to a road network monitor beside the road. Both read the circuit network for
  -- wood > 3000, which must not hold: their own wood is on their wire (a depot sends its contents,
  -- and the monitor counts the depots switched on), and is left out. Off the road, "own" holding
  -- 200 wood reads its own contents, with no wire.
  local modes = {
    wired = depot(surface, "provider", 50.5, 37.5),
    remote = depot(surface, "provider", 56.5, 37.5),
    monitored = depot(surface, "provider", 62.5, 37.5),
    own = depot(surface, "provider", 55.5, 33.5),
  }
  lay_road(surface, 50, 39, 62, 39)
  for name, count in pairs({ wired = 300, remote = 2800, monitored = 300, own = 200 }) do
    assert(modes[name].insert({ name = "wood", count = count }) == count, name .. ": cannot stock wood")
  end
  modes.monitor =
    surface.create_entity({ name = MONITOR, position = { 59.5, 40.5 }, force = "player", raise_built = true })
  local green = defines.wire_connector_id.circuit_green
  assert(modes.wired.get_wire_connector(red, true).connect_to(modes.remote.get_wire_connector(red, true), false))
  assert(
    modes.monitored.get_wire_connector(green, true).connect_to(modes.monitor.get_wire_connector(green, true), false)
  )
  local wood = { type = "item", name = "wood" }
  for _, name in ipairs({ "wired", "monitored" }) do
    assert(
      remote.call(
        "jatz-distribution",
        "set_circuit",
        modes[name],
        true,
        { first_signal = wood, comparator = ">", constant = 3000 },
        "network"
      ),
      name .. ": condition refused"
    )
  end
  assert(
    remote.call(
      "jatz-distribution",
      "set_circuit",
      modes.own,
      true,
      { first_signal = wood, comparator = ">", constant = 100 },
      "contents"
    ),
    "own: condition refused"
  )
  result.circuit_mode_refused = remote.call("jatz-distribution", "set_circuit", modes.own, true, nil, "both")
  deliveries.modes = modes
  -- Another force's provider holding 50 copper plates on the same road: left out, until its force
  -- merges into the player's at tick 299, with no road or depot changing (Pullfrog's review of
  -- 08bed57).
  -- A provider holding 100 iron plates and a monitor beside its road, wired red (x -62 to -54, y
  -- 34 to 39). At tick 301, after the monitor counted it at 300, the provider reads the network
  -- for iron plate > 0, and the monitor is cloned, the clone wired to it too. Before any update,
  -- the clone must put nothing on the wire: the provider's own 100 and the monitor's count of it
  -- are all there is (Pullfrog's review of 99acef3).
  deliveries.cloning = { provider = depot(surface, "provider", -60.5, 35.5) }
  lay_road(surface, -61, 37, -55, 37)
  assert(deliveries.cloning.provider.insert({ name = "iron-plate", count = 100 }) == 100, "cloning: cannot stock")
  deliveries.cloning.monitor =
    surface.create_entity({ name = MONITOR, position = { -57.5, 38.5 }, force = "player", raise_built = true })
  assert(
    deliveries.cloning.provider
      .get_wire_connector(defines.wire_connector_id.circuit_red, true)
      .connect_to(deliveries.cloning.monitor.get_wire_connector(defines.wire_connector_id.circuit_red, true), false),
    "cloning: no wire"
  )
  local other = game.forces["jatz-check-other"] or game.create_force("jatz-check-other")
  modes.foreign = surface.create_entity({
    name = "jatz-provider-depot",
    position = { 53.5, 37.5 },
    force = other,
    raise_built = true,
  })
  assert(modes.foreign.insert({ name = "copper-plate", count = 50 }) == 50, "foreign: cannot stock copper")
  -- Conditions the game's own entities evaluate (x -30 to -15, y 34 to 41): for each case a red and
  -- a green constant combinator, wired to a powered lamp and to a provider depot, both given the
  -- same condition. A wildcard compared with a signal leaves that signal out, and red and green add
  -- up as signed 32-bit values (Pullfrog's review of bef0020).
  local virtual = function(name)
    return { type = "virtual", name = name }
  end
  local MAX = 2147483647
  local cases = {
    anything_ge_b = { green = { ["signal-B"] = 1 }, first = "signal-anything", comparator = "≥", second = "signal-B" },
    everything_gt_b = {
      green = { ["signal-B"] = 1 },
      first = "signal-everything",
      comparator = ">",
      second = "signal-B",
    },
    overflow = { red = { ["signal-A"] = MAX }, green = { ["signal-A"] = 1 }, first = "signal-A", comparator = ">" },
    wildcard_wrap = {
      red = { ["signal-A"] = MAX },
      green = { ["signal-A"] = MAX },
      first = "signal-anything",
      comparator = "<",
    },
  }
  surface.create_entity({ name = "substation", position = { -24, 32 }, force = "player" })
  surface.create_entity({ name = "electric-energy-interface", position = { -27, 31 }, force = "player" })
  deliveries.parity = {}
  local x = -30
  for _, name in ipairs({ "anything_ge_b", "everything_gt_b", "overflow", "wildcard_wrap" }) do
    local case = cases[name]
    local lamp = surface.create_entity({ name = "small-lamp", position = { x + 0.5, 36.5 }, force = "player" })
    local target = depot(surface, "provider", x + 1.5, 39.5)
    for offset, colour in ipairs({ "red", "green" }) do
      local wire = defines.wire_connector_id["circuit_" .. colour]
      local source =
        surface.create_entity({ name = "constant-combinator", position = { x + offset - 0.5, 34.5 }, force = "player" })
      local filters = {}
      for signal_name, count in pairs(case[colour] or {}) do
        filters[#filters + 1] =
          { value = { type = "virtual", name = signal_name, quality = "normal", comparator = "=" }, min = count }
      end
      local behavior = source.get_or_create_control_behavior();
      (behavior.get_section(1) or behavior.add_section()).filters = filters
      assert(source.get_wire_connector(wire, true).connect_to(lamp.get_wire_connector(wire, true), false))
      assert(lamp.get_wire_connector(wire, true).connect_to(target.get_wire_connector(wire, true), false))
    end
    local condition = {
      first_signal = virtual(case.first),
      comparator = case.comparator,
      second_signal = case.second and virtual(case.second) or nil,
      constant = 0,
    }
    local behavior = lamp.get_or_create_control_behavior()
    behavior.circuit_enable_disable = true
    behavior.circuit_condition = condition
    assert(remote.call("jatz-distribution", "set_circuit", target, true, condition, "network"), name)
    deliveries.parity[name] = { lamp = lamp, depot = target }
    x = x + 4
  end
  deliveries.no_trucks = depot(surface, "request", -20.5, 28.5, 0)
  assert(remote.call("jatz-distribution", "set_request", deliveries.no_trucks, "wood", 5), "wood: refused")
  -- Freighters put in a request depot's chest move into its slot.
  deliveries.absorbing = depot(surface, "request", -12.5, 28.5, 0)
  assert(deliveries.absorbing.insert({ name = FREIGHTER, count = 2 }) == 2, "cannot put freighters in the chest")
  -- A request depot destroyed leaves its freighters on the ground: a full slot (3, plus 97 added),
  -- and 2 put in its chest that can't move into the full slot.
  deliveries.dying = depot(surface, "request", 60.5, 28.5, 3)
  assert(deliveries.dying.insert({ name = FREIGHTER, count = 2 }) == 2, "cannot put freighters in the chest")
  -- Freighters requested as from remote view: construction robots bring them from storage into the
  -- depot's chest, and they move into its slot. A powered roboport with robots, a storage chest
  -- with 5 freighters, and a request depot holding 1.
  local port = surface.create_entity({ name = "roboport", position = { 20, 30 }, force = "player" })
  port.get_inventory(defines.inventory.roboport_robot).insert({ name = "construction-robot", count = 10 })
  surface.create_entity({ name = "electric-energy-interface", position = { 26, 30 }, force = "player" })
  surface.create_entity({ name = "medium-electric-pole", position = { 23.5, 30.5 }, force = "player" })
  deliveries.store = surface.create_entity({ name = "storage-chest", position = { 20.5, 26.5 }, force = "player" })
  -- 5 for the request depot below, 2 for the liquid one, and 2 to replace the freighters
  -- destroyed on the road (deliveries.destroyed and deliveries.ambush, both within reach).
  -- 3 more for the unloaded request depot below.
  deliveries.store.insert({ name = FREIGHTER, count = 12 })
  -- A request depot emptied by an inserter, as players unload them onto belts: the freighters
  -- robots bring it still reach its slot, none taken out by the inserter.
  deliveries.unloaded = depot(surface, "request", 38.5, 28.5, 0)
  local unloader = surface.create_entity({
    name = "burner-inserter",
    position = { 38.5, 26.5 },
    direction = defines.direction.south,
    force = "player",
  })
  -- It picks up from the depot (south of it) and drops into the chest north of it.
  if unloader.pickup_position.y < 26.5 then
    unloader.direction = defines.direction.north
  end
  assert(unloader.pickup_position.y > 27, "the unloader doesn't take from the depot")
  unloader.get_fuel_inventory().insert({ name = "coal", count = 5 })
  deliveries.unloaded_into =
    surface.create_entity({ name = "wooden-chest", position = { 38.5, 25.5 }, force = "player" })
  assert(remote.call("jatz-distribution", "request_freighters", deliveries.unloaded, 3) == 3, "unloaded: not requested")
  local remote_depot = depot(surface, "request", 30.5, 28.5, 1)
  deliveries.remote = remote_depot
  result.requested = remote.call("jatz-distribution", "request_freighters", remote_depot, 4)
  -- Never more than fits: 1 in the slot and 4 requested leave room for 95 of the 100 a depot holds.
  result.requested_beyond_limit = remote.call("jatz-distribution", "request_freighters", remote_depot, 200)
  result.cancelled = remote.call("jatz-distribution", "cancel_freighter_requests", remote_depot)
  result.requested_again = remote.call("jatz-distribution", "request_freighters", remote_depot, 3)
  -- Taking freighters away is cancellable too: the one marked goes back into the slot.
  result.removal_marked = remote.call("jatz-distribution", "remove_freighters", remote_depot, 1)
  result.removal_cancelled = remote.call("jatz-distribution", "cancel_freighter_removal", remote_depot)
  -- A liquid request depot (a storage tank, no chest): robots bring its 2 freighters into its
  -- truck chest, and they move into its slot.
  deliveries.liquid_remote = depot(surface, "liquid-request", 45.5, 28.5)
  result.liquid_requested = remote.call("jatz-distribution", "request_freighters", deliveries.liquid_remote, 2)
  -- Blueprints (and copy and paste) keep a request depot's request and freighters. Out of the
  -- roboport's reach, so requests stay pending to be counted. A depot asking for 7 wood, with 3
  -- freighters, is blueprinted, and a ghost from the blueprint is built.
  local source = depot(surface, "request", -66.5, -66.5, 3)
  assert(remote.call("jatz-distribution", "set_request", source, "wood", 7), "wood: refused")
  local holder = game.create_inventory(1)
  holder.insert({ name = "blueprint" })
  local blueprint = holder[1]
  local mapping =
    blueprint.create_blueprint({ surface = surface, force = "player", area = { { -68, -68 }, { -65, -65 } } })
  result.blueprinted = remote.call("jatz-distribution", "setup_blueprint", blueprint, mapping)
  local planned = blueprint.get_blueprint_entities()[1]
  result.blueprint_tag = planned.tags and planned.tags.jatz_request and planned.tags.jatz_request.item
  result.blueprint_freighters = planned.items and planned.items[1].items.in_inventory[1].count
  local revived
  for _, ghost in pairs(blueprint.build_blueprint({ surface = surface, force = "player", position = { -56.5, -66.5 } })) do
    local _, entity = ghost.revive({ raise_revive = true })
    revived = entity or revived
  end
  local copied = revived and remote.call("jatz-distribution", "get_request", revived)
  result.built_request = copied and (copied.item .. " x" .. copied.count) or "none"
  result.built_freighters_requested = revived and remote.call("jatz-distribution", "requested_freighters", revived)
  -- Then filled by hand: the ghost's request for them goes away.
  remote.call("jatz-distribution", "add_freighters", revived, 3)
  deliveries.built = revived
  -- Setting a blueprint up keeps other items' insert plans, stays off their chest stacks, and drops
  -- settings the depot no longer has. Here the blueprint already asks for 5 iron plates in chest
  -- stack 0.
  local entities = blueprint.get_blueprint_entities()
  entities[1].items = {
    {
      id = { name = "iron-plate", quality = "normal" },
      items = { in_inventory = { { inventory = defines.inventory.chest, stack = 0, count = 5 } } },
    },
  }
  blueprint.set_blueprint_entities(entities)
  remote.call("jatz-distribution", "setup_blueprint", blueprint, mapping)
  local kept_iron, freighter_stack = false, nil
  for _, plan in pairs(blueprint.get_blueprint_entities()[1].items) do
    local name = type(plan.id.name) == "string" and plan.id.name or plan.id.name.name
    kept_iron = kept_iron or name == "iron-plate"
    if name == FREIGHTER then
      freighter_stack = plan.items.in_inventory[1].stack
    end
  end
  result.blueprint_kept_other_items = kept_iron
  result.blueprint_freighters_first_stack = freighter_stack
  -- The same blueprint set up from a depot with no request and no freighters drops both.
  local plain = depot(surface, "request", -66.5, -56.5, 0)
  remote.call("jatz-distribution", "setup_blueprint", blueprint, { [1] = plain })
  local stale = blueprint.get_blueprint_entities()[1]
  result.blueprint_cleared = not (stale.tags and (stale.tags.jatz_request or stale.tags.jatz_freighters))
  -- Freighters still in the source's chest count: 2 in its slot and 3 in its chest make 5.
  local chested = depot(surface, "request", -56.5, -56.5, 2)
  chested.insert({ name = FREIGHTER, count = 3 })
  remote.call("jatz-distribution", "setup_blueprint", blueprint, { [1] = chested })
  local counted = blueprint.get_blueprint_entities()[1]
  result.blueprint_counts_chest = counted.tags and counted.tags.jatz_freighters
  -- A depot built over a blueprint ghost by hand gets no tags (the game passes none on), only the
  -- ghost's request for 5 freighters: it must still remember those 5 when a player fills it partly.
  depot(surface, "request", -6.5, -46.5, 5)
  local five_mapping =
    blueprint.create_blueprint({ surface = surface, force = "player", area = { { -8, -48 }, { -5, -45 } } })
  remote.call("jatz-distribution", "setup_blueprint", blueprint, five_mapping)
  for _, ghost in pairs(blueprint.build_blueprint({ surface = surface, force = "player", position = { -66.5, -36.5 } })) do
    ghost.tags = nil
    local _, built = ghost.revive({ raise_revive = true })
    deliveries.untagged = built or deliveries.untagged
  end
  -- /jatz-freighters describes it (real request proxies, plans and counts).
  local described = remote.call("jatz-distribution", "describe_freighters", deliveries.untagged)
  assert(
    described
      and described:find("coming 5", 1, true)
      and described:find("insert jatz-quinityn-freighter [0:5]", 1, true),
    "describe: " .. tostring(described)
  )
  result.described = true
  holder.destroy()
  -- A ghost with malformed tags (from an edited blueprint string, say) still builds, untouched.
  local odd = surface.create_entity({
    name = "entity-ghost",
    inner_name = "jatz-request-depot",
    position = { -46.5, -56.5 },
    force = "player",
    tags = { jatz_request = 5, jatz_freighters = "many" },
  })
  local _, odd_depot = odd.revive({ raise_revive = true })
  result.malformed_tags_built = odd_depot ~= nil and remote.call("jatz-distribution", "get_request", odd_depot) == nil
  -- Pasting onto a depot asking for more than the source has: requests beyond it are cancelled.
  local over = depot(surface, "request", -36.5, -56.5, 0)
  remote.call("jatz-distribution", "request_freighters", over, 8)
  remote.call("jatz-distribution", "match_freighters", over, 3)
  result.matched_down = remote.call("jatz-distribution", "requested_freighters", over)
  -- Freighters put in by hand cancel requests at once, before robots could bring more.
  local at_once = depot(surface, "request", -26.5, -56.5, 0)
  remote.call("jatz-distribution", "request_freighters", at_once, 5)
  remote.call("jatz-distribution", "add_freighters", at_once, 5)
  result.trimmed_at_once = remote.call("jatz-distribution", "requested_freighters", at_once)
  -- Ctrl+click of freighters into a request depot's window drops them in its chest: they fill the
  -- slot at once, and the rest go back to the player. 95 in the slot, 15 dropped in: 5 taken, 10
  -- back.
  local nearly_full = depot(surface, "request", -16.5, -56.5, 95)
  nearly_full.insert({ name = FREIGHTER, count = 15 })
  -- Other items ctrl+clicked in alongside stay in the chest, as in any container.
  nearly_full.insert({ name = "iron-plate", count = 20 })
  local pockets = game.create_inventory(20)
  local taken, returned = remote.call("jatz-distribution", "take_in_freighters", nearly_full, pockets, 15)
  result.ctrl_click_taken, result.ctrl_click_returned = taken, returned
  result.ctrl_click_slot = remote.call("jatz-distribution", "freighter_counts", nearly_full)
  result.ctrl_click_left_in_chest = nearly_full.get_inventory(defines.inventory.chest).get_item_count(FREIGHTER)
  result.ctrl_click_pockets = pockets.get_item_count(FREIGHTER)
  result.ctrl_click_other_items_kept = nearly_full.get_inventory(defines.inventory.chest).get_item_count("iron-plate")
  result.ctrl_click_other_items_returned = pockets.get_item_count("iron-plate")
  -- Only freighters the player just moved: 3 already in a full depot's chest (an inserter's, say)
  -- stay through an unrelated inventory change, and when 2 more are moved in, those 2 go back.
  local full = depot(surface, "request", -66.5, -46.5, 100)
  full.insert({ name = FREIGHTER, count = 3 })
  remote.call("jatz-distribution", "take_in_freighters", full, pockets, 0)
  pockets.clear()
  full.insert({ name = FREIGHTER, count = 2 })
  local _, back = remote.call("jatz-distribution", "take_in_freighters", full, pockets, 2)
  result.ctrl_click_only_new_returned = back
  result.ctrl_click_existing_kept = full.get_inventory(defines.inventory.chest).get_item_count(FREIGHTER)
  -- Freighters put in while 5 wait in the depot's truck chest for robots to take them away: the
  -- newcomers go to the slot, the 5 waiting stay.
  local marked = depot(surface, "request", -56.5, -46.5, 5)
  remote.call("jatz-distribution", "remove_freighters", marked, 5)
  marked.insert({ name = FREIGHTER, count = 3 })
  result.ctrl_click_merged_taken = remote.call("jatz-distribution", "take_in_freighters", marked, pockets, 3)
  local waiting = surface.find_entities_filtered({ name = "jatz-truck-chest", position = marked.position })[1]
  result.ctrl_click_marked_left = waiting and waiting.get_inventory(defines.inventory.chest).get_item_count(FREIGHTER)
  -- Freighters of any quality fill the slot (Space Age has other qualities).
  if prototypes.quality.uncommon then
    local fine = depot(surface, "request", -46.5, -46.5, 0)
    fine.insert({ name = FREIGHTER, quality = "uncommon", count = 2 })
    local fine_taken = remote.call("jatz-distribution", "take_in_freighters", fine, pockets, 2)
    assert(fine_taken == 2, "uncommon freighters stayed out of the slot")
    result.ctrl_click_any_quality = fine_taken
  end
  -- A freighter put by hand onto a requested slot, then moved to the slot: the depot's request is
  -- lowered in place (the same request proxy, now for 4), so an open window keeps showing it.
  local kept_proxy = depot(surface, "request", -16.5, -36.5, 0)
  remote.call("jatz-distribution", "match_freighters", kept_proxy, 5)
  local function proxy_of(entity)
    return surface.find_entities_filtered({ name = "item-request-proxy", position = entity.position })[1]
  end
  local before_proxy = proxy_of(kept_proxy)
  kept_proxy.get_inventory(defines.inventory.chest)[1].set_stack({ name = FREIGHTER, count = 1 })
  remote.call("jatz-distribution", "take_in_freighters", kept_proxy, pockets, 1)
  local after_proxy = proxy_of(kept_proxy)
  result.hand_fill_same_proxy = before_proxy ~= nil and after_proxy == before_proxy
  result.hand_fill_requested = remote.call("jatz-distribution", "requested_freighters", kept_proxy)
  pockets.destroy()
  -- A pasted depot asking for 5 gets 1 by hand, and Factorio drops the request (it does when a player
  -- fills one by hand, even partly): the other 4 are requested again.
  deliveries.dropped = depot(surface, "request", -36.5, -46.5, 0)
  remote.call("jatz-distribution", "match_freighters", deliveries.dropped, 5)
  deliveries.dropped.insert({ name = FREIGHTER, count = 1 })
  for _, proxy in pairs(surface.find_entities_filtered({ name = "item-request-proxy", position = { -36.5, -46.5 } })) do
    proxy.destroy()
  end
  -- Taking freighters away on purpose stops topping up: asked for 5, given 2, then those 2 sent
  -- away by robots: only the 3 still requested stay requested.
  deliveries.sent_away = depot(surface, "request", -26.5, -46.5, 0)
  remote.call("jatz-distribution", "match_freighters", deliveries.sent_away, 5)
  remote.call("jatz-distribution", "add_freighters", deliveries.sent_away, 2)
  remote.call("jatz-distribution", "remove_freighters", deliveries.sent_away, 2)
  -- Copy and Paste settings asks robots for the freighters the destination lacks: with 1, to match 3.
  local pasted = depot(surface, "request", -46.5, -66.5, 1)
  result.matched = remote.call("jatz-distribution", "match_freighters", pasted, 3)
  -- Freighters put in by hand count towards what was requested; requests beyond it go: asked for
  -- 6, given 7, nothing is left to request.
  deliveries.trimmed = depot(surface, "request", -36.5, -66.5, 0)
  remote.call("jatz-distribution", "request_freighters", deliveries.trimmed, 6)
  remote.call("jatz-distribution", "add_freighters", deliveries.trimmed, 7)
  -- A pasted depot asking for 5 freighters, filled with 5 by hand: its request clears.
  deliveries.filled = depot(surface, "request", -26.5, -66.5, 0)
  remote.call("jatz-distribution", "match_freighters", deliveries.filled, 5)
  remote.call("jatz-distribution", "add_freighters", deliveries.filled, 5)
  -- Given only 2 by hand: it still asks for the other 3.
  deliveries.partly = depot(surface, "request", -16.5, -66.5, 0)
  remote.call("jatz-distribution", "match_freighters", deliveries.partly, 5)
  remote.call("jatz-distribution", "add_freighters", deliveries.partly, 2)
  -- Several item request proxies on one depot: freighters asked of its own chest by one, and an
  -- iron plate by another, which `item_request_proxy` names. The freighters are asked of its truck
  -- chest instead, the iron plate's plan stays. Out of the roboport's reach, so both stay pending.
  local two = depot(surface, "request", -6.5, -36.5, 0)
  local function ask(item, stack, count)
    surface.create_entity({
      name = "item-request-proxy",
      position = two.position,
      force = "player",
      target = two,
      modules = {
        {
          id = { name = item, quality = "normal" },
          items = { in_inventory = { { inventory = defines.inventory.chest, stack = stack, count = count } } },
        },
      },
    })
  end
  ask(FREIGHTER, 1, 5)
  ask("iron-plate", 0, 1)
  local named = two.item_request_proxy and two.item_request_proxy.insert_plan[1]
  result.two_proxies_named = named and (type(named.id.name) == "string" and named.id.name or named.id.name.name)
  deliveries.two_proxies = two
  -- The freighter slot can't be overfilled through the remote interface: 97 more fill it to 100.
  result.add_beyond_limit = remote.call("jatz-distribution", "add_freighters", deliveries.dying, 200)
  -- More than a stack (freighters stack to 10) is requested and taken away a stack at a time: 25
  -- requested spread over 3 chest stacks; 25 in the slot all marked for robots to take away.
  local many = depot(surface, "request", -6.5, -66.5, 0)
  result.requested_many = remote.call("jatz-distribution", "request_freighters", many, 25)
  result.requested_many_pending = remote.call("jatz-distribution", "requested_freighters", many)
  local leaving = depot(surface, "request", 6.5, -66.5, 25)
  result.removing_many = remote.call("jatz-distribution", "remove_freighters", leaving, 25)
  result.removing_many_pending = select(2, remote.call("jatz-distribution", "requested_freighters", leaving))
  result.removing_many_left = remote.call("jatz-distribution", "freighter_counts", leaving)

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

  -- A cloned Fuel depot keeps its fuel, items and liquid: cloned alone (LuaEntity::clone) it gets the
  -- original's fluid in a tank of its own; cloned with its hidden tank (LuaSurface::clone_entities)
  -- it keeps that tank. The original keeps its own. Water, which needs no fuel value to be held.
  local fuel_source = depot(surface, "fuel", 64.5, -6.5)
  local source_tank = surface.find_entity(FUEL_TANK, fuel_source.position)
  assert(fuel_source.insert({ name = "coal", count = 10 }) == 10, "clone: cannot stock coal")
  assert(source_tank.insert_fluid({ name = "water", amount = 1234 }) == 1234, "clone: cannot fill the tank")
  local function fuel_held(entity)
    if not (entity and entity.valid) then
      return "missing"
    end
    local contents = remote.call("jatz-distribution", "fuel_contents", entity)
    local tanks = surface.find_entities_filtered({ name = FUEL_TANK, position = entity.position, radius = 0.5 })
    return string.format(
      "%s %d, %d coal, %d tank(s)",
      contents.fluid or "none",
      math.floor(contents.amount + 0.5),
      entity.get_item_count("coal"),
      #tanks
    )
  end
  result.fuel_clone_alone = fuel_held(fuel_source.clone({ position = { 64.5, 2.5 } }))
  surface.clone_entities({ entities = { fuel_source, source_tank }, destination_offset = { -10, 0 } })
  result.fuel_clone_with_tank = fuel_held(surface.find_entity("jatz-fuel-depot", { 54.5, -6.5 }))
  result.fuel_clone_source = fuel_held(fuel_source)
end

-- The sprites the mod draws on a freighter (its alt-mode cargo icon), in drawing order.
local function cargo_icons(drone)
  local sprites = {}
  for _, object in pairs(rendering.get_all_objects("jatz-distribution")) do
    if object.type == "sprite" and object.target.entity == drone then
      assert(object.only_in_alt_mode, "a freighter's cargo icon shows outside alt mode")
      sprites[#sprites + 1] = object.sprite
    end
  end
  return table.concat(sprites, " ")
end

-- Every freighter on the way must stand wholly on road.
local function check_freighters_on_road(surface)
  local deliveries = storage.deliveries
  for _, drone in pairs(surface.find_entities_filtered({ name = DRONES })) do
    local icons = cargo_icons(drone)
    if icons ~= "" then
      deliveries.cargo_icons[icons] = true
    end
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
    -- The connected pair's U (its bottom row at y 57), not the fuel checks' road at y 66.
    if drone.position.x < -30 and drone.position.y > 40 and drone.position.y < 62 then
      deliveries.deepest = math.max(deliveries.deepest, drone.position.y)
    end
  end
end

local function count(entity, item)
  return entity.get_inventory(defines.inventory.chest).get_item_count(item or "iron-plate")
end

-- The researched force's freighter: its speed as it sets off, then undo a speed level (the
-- fourth, so the infinite levels after it no longer count either: 1.6 times) and read it again on
-- the road; and the first load it brings.
local function watch_researched(surface)
  local researched = storage.deliveries.researched
  local base = prototypes.entity[DRONE].speed
  if not researched.reversed_speed then
    local drone = surface.find_entities_filtered({ name = DRONES, force = "jatz-researched" })[1]
    if drone then
      researched.first_speed = drone.speed / base
      game.forces["jatz-researched"].technologies[research.speed .. "-" .. research.speed_levels].researched = false
      researched.reversed_speed = drone.speed / base
    end
  end
  if not researched.first_load and count(researched.request) > 0 then
    researched.first_load = count(researched.request)
  end
end

-- With one of the Mining Drones mods (tools/test_mod.py --mod): a mining depot is a provider of
-- what its drones mine, which collects in its output inventory. Facing north it mines to the north
-- and loads from the tile behind its southern end; a request depot for 30 of its 40 iron ore stands
-- 12 tiles along a straight road from there. North of everything else, by the map's edge.
local function setup_mining(surface)
  if not prototypes.entity["mining-depot"] then
    return
  end
  local mine =
    surface.create_entity({ name = "mining-depot", position = { 4.5, -66 }, force = "player", raise_built = true })
  mine.set_recipe("mine-iron-ore")
  assert(mine.get_output_inventory().insert({ name = "iron-ore", count = 40 }) == 40, "mining: cannot stock")
  local request = depot(surface, "request", 16.5, -63.5)
  lay_road(surface, 5, -62, 16, -62)
  assert(remote.call("jatz-distribution", "set_request", request, "iron-ore", 30), "mining: request refused")
  storage.deliveries.mining = { mine = mine, request = request, zone = surface.get_tile(4, -62).name }
end

-- Our Milestones preset addon (control.lua) must name only real items, as "name xquantity":
-- Milestones drops unknown names without a word. tools/test_mod.py --mod with Milestones checks
-- that Milestones loads the addon (it tracks only forces with players, so nothing is reached here).
local function check_milestones(result)
  result.milestones = {}
  local addons = remote.call("jatz-distribution-milestones", "milestones_preset_addons")
  for _, milestone in ipairs(addons["Jat'z Distribution"].milestones) do
    if milestone.type == "item" then
      local known = prototypes.item[milestone.name] and "" or "unknown "
      result.milestones[#result.milestones + 1] = known .. milestone.name .. " x" .. milestone.quantity
    end
  end
end

local function status(entity)
  return remote.call("jatz-distribution", "get_status", entity)
end

-- What a road network monitor puts on its red wire: stone walls, water and small lamps.
-- What each of the reading monitors shows, by reading: "name=count" for each of its signals (from
-- its sections), sorted and comma-separated ("" for none).
local function readings_shown(monitors)
  local shown = {}
  for reading, monitor in pairs(monitors) do
    local signals = {}
    local behavior = monitor.get_control_behavior()
    for index = 1, behavior and behavior.sections_count or 0 do
      for _, filter in pairs(behavior.get_section(index).filters) do
        if filter.value then
          signals[#signals + 1] = filter.value.name .. "=" .. filter.min
        end
      end
    end
    table.sort(signals)
    shown[reading] = table.concat(signals, ",")
  end
  return shown
end

local function monitor_reading(monitor)
  local network = monitor.get_circuit_network(defines.wire_connector_id.circuit_red)
  return {
    walls = network.get_signal({ type = "item", name = "stone-wall", quality = "normal" }),
    water = network.get_signal({ type = "fluid", name = "water" }),
    lamps = network.get_signal({ type = "item", name = "small-lamp", quality = "normal" }),
  }
end

-- Interfere with trips as they happen: destroy one freighter, change one request, cut one road.
local function interfere(surface)
  if game.tick == 65 then
    -- After the first dispatch, a player puts 1 of the 5 freighters in by hand, and Factorio drops
    -- the request.
    local untagged = storage.deliveries.untagged
    untagged.insert({ name = FREIGHTER, count = 1 })
    for _, proxy in pairs(surface.find_entities_filtered({ name = "item-request-proxy", position = untagged.position })) do
      proxy.destroy()
    end
  end
  local roads = storage.depot_roads
  if game.tick == 30 then
    -- The first of two depots sharing a loading tile went at tick 0: the road is still there.
    roads.shared_kept = surface.get_tile(40, 11).name
    roads.shared_b.destroy()
  end
  local deliveries = storage.deliveries
  local circuit = deliveries.circuit
  local cloning = deliveries.cloning
  if game.tick == 301 then
    local red = defines.wire_connector_id.circuit_red
    local iron = { type = "item", name = "iron-plate" }
    assert(
      remote.call(
        "jatz-distribution",
        "set_circuit",
        cloning.provider,
        true,
        { first_signal = iron, comparator = ">", constant = 0 },
        "network"
      ),
      "cloning: condition refused"
    )
    cloning.before = {
      wire = cloning.provider.get_circuit_network(red).get_signal(iron),
      fulfilled = remote.call("jatz-distribution", "get_circuit", cloning.provider).fulfilled,
      monitor = readings_shown({ shown = cloning.monitor }).shown,
    }
    cloning.clone = cloning.monitor.clone({ position = { -55.5, 38.5 } })
    assert(
      cloning.clone.get_wire_connector(red, true).connect_to(cloning.provider.get_wire_connector(red, true), false),
      "cloning: no wire to the clone"
    )
    cloning.clone_shows = readings_shown({ shown = cloning.clone }).shown
  elseif game.tick == 302 then
    local red = defines.wire_connector_id.circuit_red
    local iron = { type = "item", name = "iron-plate" }
    cloning.after = {
      wire = cloning.provider.get_circuit_network(red).get_signal(iron),
      fulfilled = remote.call("jatz-distribution", "get_circuit", cloning.provider).fulfilled,
      clone_shows = cloning.clone_shows,
    }
  end
  if game.tick == 299 then
    -- Before the combinators switch them on: nothing moved, and the monitor left out the
    -- switched-off provider and the other road.
    circuit.before = {
      walls = count(circuit.request, "stone-wall"),
      lamps = count(circuit.lamps, "small-lamp"),
      walls_status = status(circuit.request),
      lamps_status = status(circuit.lamps),
      monitor = monitor_reading(circuit.monitor),
      readings = readings_shown(circuit.readings),
      -- The hover panel of the provider switched off, and of the request depot on its road.
      gated_status = circuit.gated.custom_status and {
        red = circuit.gated.custom_status.diode == defines.entity_status_diode.red,
        label = circuit.gated.custom_status.label[1],
      },
      request_status = circuit.request.custom_status ~= nil,
      -- The modes road's monitor, before the other force merges into the player's.
      merged_monitor = readings_shown({ shown = deliveries.modes.monitor }).shown,
    }
    game.merge_forces("jatz-check-other", "player")
    for _, switch in ipairs({ circuit.switch_a, circuit.switch_b }) do
      switch.get_control_behavior().get_section(1).set_slot(1, {
        value = { type = "virtual", name = switch == circuit.switch_a and "signal-A" or "signal-B", quality = "normal" },
        min = 1,
      })
    end
  end
  -- The connected pair's freighter stops at each loading zone before its cargo moves.
  local stops = deliveries.stops
  local function standing_at(x, y)
    for _, drone in pairs(surface.find_entities_filtered({ name = DRONES, position = { x, y }, radius = 3 })) do
      -- It stops about a tile short of the loading zone's centre.
      if (drone.position.x - x) ^ 2 + (drone.position.y - y) ^ 2 <= 1.25 ^ 2 then
        return drone
      end
    end
  end
  if not stops.at_provider then
    stops.drone = standing_at(-60.5, 47.5)
    if stops.drone then
      stops.at_provider = game.tick
      stops.empty_paint = stops.drone.name
      stops.empty_icons = cargo_icons(stops.drone)
    end
  end
  if stops.at_provider and not stops.loaded and count(deliveries.provider) < 50 then
    stops.loaded = game.tick
    -- It came empty, and loading put it in its cargo's paint: a new freighter where it stood (seen
    -- a tick later, so it may have moved off at 0.2 tiles a tick).
    stops.swapped = not stops.drone.valid
    local painted = standing_at(-60.5, 47.5)
    assert(
      painted and (painted.position.x - stops.standing.x) ^ 2 + (painted.position.y - stops.standing.y) ^ 2 < 0.3 ^ 2,
      "the loaded freighter is not the one that stood at the provider"
    )
    stops.drone = painted
    stops.home_paint = painted.name
  end
  -- A freighter with something stuck to it (here a sticker like fire) loads without being swapped,
  -- so the sticker and its damage go on exactly as they would, and takes its cargo's paint on the
  -- way home once the sticker has worn off.
  local sticky = deliveries.sticky
  if not sticky.drone then
    sticky.drone = standing_at(sticky.provider.position.x, sticky.provider.position.y + 2)
    if sticky.drone then
      sticky.sticker =
        surface.create_entity({ name = STICKER, position = sticky.drone.position, target = sticky.drone })
      assert(sticky.sticker and sticky.sticker.sticked_to == sticky.drone, "the test sticker did not stick")
      sticky.sticker.time_to_live = STICKER_TICKS
    end
  end
  if sticky.drone and not sticky.loaded and count(sticky.provider, sticky.item) < 10 then
    sticky.loaded = game.tick
    sticky.kept = sticky.drone.valid
      and sticky.drone.name == DRONE
      and sticky.sticker.valid
      and sticky.sticker.sticked_to == sticky.drone
    sticky.loaded_icons = cargo_icons(sticky.drone)
  end
  if sticky.loaded and not sticky.painted then
    for _, drone in pairs(surface.find_entities_filtered({ name = IRON_PAINT, area = sticky.road })) do
      sticky.painted = game.tick
      -- Painted where the old one was, after the sticker wore off, still on its way home.
      sticky.painted_after_sticker = not sticky.sticker.valid and not sticky.drone.valid
      sticky.painted_on_road = drone.position.x < sticky.request.position.x - 1
      sticky.painted_icons = cargo_icons(drone)
    end
  end
  if stops.at_provider and not stops.loaded then
    stops.standing = stops.drone.position
  end
  if stops.loaded and not stops.at_home and standing_at(-40.5, 47.5) then
    stops.at_home = game.tick
    stops.loaded_icons = cargo_icons(stops.drone)
  end
  if stops.at_home and not stops.unloaded and count(deliveries.connected) > 0 then
    stops.unloaded = game.tick
  end
  if stops.loaded and not stops.unloaded then
    assert(stops.drone and stops.drone.valid, "the freighter disappeared before unloading at home")
    if stops.at_home then
      assert(standing_at(-40.5, 47.5) == stops.drone, "a different freighter came home")
    end
  end
  -- Fuel: the low freighter stops at the Fuel depot before it loads at the provider; the dry one
  -- waits at home until there is fuel.
  local fuelled = deliveries.fuelled
  local at_fuel = not fuelled.at_fuel and standing_at(-70.5, 66.5)
  if at_fuel then
    fuelled.at_fuel = game.tick
    -- Its fuel on hover (its status), as the game reads it back: low, before it fills up.
    local hover = at_fuel.custom_status
    if hover then
      fuelled.hover = hover.label[1]
      for name, value in pairs(defines.entity_status_diode) do
        if hover.diode == value then
          fuelled.hover_diode = name
        end
      end
    end
  end
  if not fuelled.loaded and count(fuelled.provider, "iron-ore") < 20 then
    fuelled.loaded = game.tick
  end
  local dry = deliveries.dry
  if game.tick == 300 then
    dry.waiting_status = status(dry.request)
    dry.waiting_received = count(dry.request, "sulfur")
    assert(dry.fuel.insert({ name = "coal", count = 5 }) == 5, "dry: cannot add coal")
  elseif game.tick == 420 then
    -- Its depot looks every second for fuel to get, not after its 10-second wait.
    dry.after_coal_status = status(dry.request)
  end
  -- Once robots have brought the 3 requested freighters, have them take 2 away again.
  if not deliveries.removal_started then
    local in_slot = remote.call("jatz-distribution", "freighter_counts", deliveries.remote)
    local requested = remote.call("jatz-distribution", "requested_freighters", deliveries.remote)
    if in_slot == 4 and requested == 0 then
      deliveries.robots_delivered = in_slot
      deliveries.removal_started = remote.call("jatz-distribution", "remove_freighters", deliveries.remote, 2)
    end
  end
  local multi = deliveries.multi
  -- Freighters setting off, so still empty: loaded ones coming home are other, painted freighters.
  for _, drone in pairs(surface.find_entities_filtered({ name = DRONE, position = { -66.5, 30.5 }, radius = 1 })) do
    multi.seen[drone.unit_number] = multi.seen[drone.unit_number] or game.tick
  end
  if game.tick == 10 and deliveries.dying.valid then
    deliveries.dying.die()
  end
  local destroyed = deliveries.destroyed
  if not destroyed.done and status(destroyed.request) == "delivering" then
    local drones = surface.find_entities_filtered({ name = DRONES, position = { 32.5, 4.5 }, radius = 3 })
    if #drones == 1 then
      drones[1].destroy()
      destroyed.done = true
    end
  end
  local ambush = deliveries.ambush
  if not ambush.drone then
    -- Its freighter, a few tiles out on the road (loading zones at y 56.5, request at x 11.5).
    local drone = surface.find_entities_filtered({ name = DRONES, area = { { -10, 55 }, { 8, 58 } } })[1]
    if drone then
      ambush.drone, ambush.drone_id = drone, drone.unit_number
      ambush.biters = {}
      for _, offset in ipairs({ { 0, -2 }, { 0, 2 }, { -2, -2 } }) do
        local behemoth = surface.create_entity({
          name = "behemoth-biter",
          position = { drone.position.x + offset[1], drone.position.y + offset[2] },
          force = "enemy",
        })
        behemoth.commandable.set_command({ type = defines.command.attack, target = drone })
        ambush.biters[#ambush.biters + 1] = behemoth
      end
    end
  elseif not ambush.killed and ambush.drone.valid then
    ambush.position = ambush.drone.position
  elseif not ambush.killed then
    ambush.killed = game.tick
    -- Where it died: an explosion, and the wreck it leaves.
    local around = { position = ambush.position, radius = 3 }
    around.name = "car-explosion"
    ambush.exploded = #surface.find_entities_filtered(around) > 0
    around.name = "car-remnants"
    ambush.wrecks = #surface.find_entities_filtered(around)
    ambush.requested = remote.call("jatz-distribution", "requested_freighters", ambush.request)
    for _, behemoth in ipairs(ambush.biters) do
      if behemoth.valid then
        behemoth.destroy()
      end
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
      name = DRONES,
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
  if
    rerouted.done
    and not rerouted.freighter.valid
    and count(rerouted.request, "stone-brick") < 10
    and count(rerouted.provider, "stone-brick") == 10
  then
    -- The freighter gave up instead of going on to the other provider (it is repainted, so
    -- replaced, once it loads there).
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
  -- A depot's status updates at its next dispatch, up to a second after the last unload.
  local done = count(deliveries.connected) >= 30
    and status(deliveries.connected) ~= "delivering"
    and count(deliveries.sticky.request, "iron-plate") == 10
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
    and count(deliveries.multi.request, "iron-stick") == 60
    and count(deliveries.researched.request) == 2000
    and count(deliveries.runover.request, "iron-ore") == 10
    and deliveries.ambush.killed
    and count(deliveries.ambush.request, "copper-ore") == 10
    and remote.call("jatz-distribution", "freighter_counts", destroyed.request) == 3
    and remote.call("jatz-distribution", "freighter_counts", deliveries.ambush.request) == 3
    and count(deliveries.buffering.request, "copper-cable") == 20
    and count(deliveries.buffering.filling, "copper-cable") == 15
    and count(deliveries.prioritised.request, "stone") == 10
    and (not deliveries.mining or count(deliveries.mining.request, "iron-ore") == 30)
    and count(deliveries.circuit.request, "stone-wall") == 10
    and count(deliveries.circuit.lamps, "small-lamp") == 10
    and deliveries.liquid.request.get_fluid_count("water") == 1200
    and deliveries.steam.request.get_fluid_count("steam") == 300
    and deliveries.fallback.request.get_fluid_count("crude-oil") == 300
    and remote.call("jatz-distribution", "freighter_counts", deliveries.liquid_remote) == 2
    and count(deliveries.fuelled.request, "iron-ore") == 10
    and count(deliveries.liquid_fuelled.request, "copper-ore") == 10
    and count(deliveries.dry.request, "sulfur") == 10
    and deliveries.removal_started
    and select(2, remote.call("jatz-distribution", "requested_freighters", deliveries.remote)) == 0
    and deliveries.store.get_item_count(FREIGHTER) == 4
    and #surface.find_entities_filtered({ name = DRONES }) == 0
  if not done or tick < DELIVERY_SETTLE then
    if tick >= DELIVERY_DEADLINE then
      error(
        string.format(
          "deliveries did not finish in time: fuel ore %d (%s), liquid fuel ore %d (%s), dry sulfur %d (%s), iron %d (%s), armor %d, steel %d (destroyed %s), plastic change %s, gears back %d (cut %s, %s), pipes after mending %d (%s), bricks rerouted %d, buffered request %d (%s), buffer filled %d (%s), prioritised %d (%s), water %d (%s), steam %d (%s), oil fallback %d (%s), liquid robots %d, run over %d (%s), ambushed %d (%s, killed %s), unloaded depot %d in slot (%d taken out, %d in storage), %d freighter(s) out",
          count(deliveries.fuelled.request, "iron-ore"),
          tostring(status(deliveries.fuelled.request)),
          count(deliveries.liquid_fuelled.request, "copper-ore"),
          tostring(status(deliveries.liquid_fuelled.request)),
          count(deliveries.dry.request, "sulfur"),
          tostring(status(deliveries.dry.request)),
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
          count(deliveries.buffering.request, "copper-cable"),
          tostring(status(deliveries.buffering.request)),
          count(deliveries.buffering.filling, "copper-cable"),
          tostring(status(deliveries.buffering.filling)),
          count(deliveries.prioritised.request, "stone"),
          tostring(status(deliveries.prioritised.request)),
          deliveries.liquid.request.get_fluid_count("water"),
          tostring(status(deliveries.liquid.request)),
          deliveries.steam.request.get_fluid_count("steam"),
          tostring(status(deliveries.steam.request)),
          deliveries.fallback.request.get_fluid_count("crude-oil"),
          tostring(status(deliveries.fallback.request)),
          remote.call("jatz-distribution", "freighter_counts", deliveries.liquid_remote),
          count(deliveries.runover.request, "iron-ore"),
          tostring(status(deliveries.runover.request)),
          count(deliveries.ambush.request, "copper-ore"),
          tostring(status(deliveries.ambush.request)),
          tostring(deliveries.ambush.killed),
          remote.call("jatz-distribution", "freighter_counts", deliveries.unloaded),
          count(deliveries.unloaded_into, FREIGHTER),
          deliveries.store.get_item_count(FREIGHTER),
          #surface.find_entities_filtered({ name = DRONES })
        )
      )
    end
    return false
  end
  result.delivered = count(deliveries.connected)
  local researched = deliveries.researched
  result.researched_speed = math.floor(researched.first_speed * 100 + 0.5) / 100
  result.researched_speed_reversed = math.floor(researched.reversed_speed * 100 + 0.5) / 100
  result.researched_first_load = researched.first_load
  result.researched_received = count(researched.request)
  if deliveries.mining then
    result.mining = {
      zone = deliveries.mining.zone,
      delivered = count(deliveries.mining.request, "iron-ore"),
      left = deliveries.mining.mine.get_output_inventory().get_item_count("iron-ore"),
    }
  end
  result.provider_left = count(deliveries.provider)
  result.island_received = count(deliveries.island)
  result.request_status = status(deliveries.connected)
  result.island_status = status(deliveries.island)
  result.unpaved_status = status(deliveries.unpaved)
  result.road_samples = deliveries.road_samples
  -- The road's south edge is the tile row at y 57; the straight route stays at y 47.
  result.detour = deliveries.deepest - 47.5
  assert(result.road_samples > 0, "no freighter was ever seen driving")
  -- It stands one second at each loading zone before loading, and before unloading.
  local stops = deliveries.stops
  result.loading_stop = stops.loaded - stops.at_provider
  result.unloading_stop = stops.unloaded - stops.at_home
  for _, stop in ipairs({ result.loading_stop, result.unloading_stop }) do
    assert(stop >= 50 and stop <= 70, "a freighter stood " .. stop .. " ticks to load or unload, not 60")
  end
  -- In alt mode a loaded freighter shows its cargo's icon, an empty one nothing.
  result.empty_icons = stops.empty_icons
  result.loaded_icons = stops.loaded_icons
  assert(stops.empty_icons == "", "an empty freighter shows a cargo icon: " .. stops.empty_icons)
  assert(
    stops.loaded_icons == "utility/entity_info_dark_background item/iron-plate",
    "a freighter loaded with iron plates shows: " .. stops.loaded_icons
  )
  -- Kept unswapped while the sticker lasts, it shows the icon; painted after, the new one does.
  for _, icons in ipairs({ deliveries.sticky.loaded_icons or "", deliveries.sticky.painted_icons or "" }) do
    assert(icons == "utility/entity_info_dark_background item/iron-plate", "the sticky freighter shows: " .. icons)
  end
  assert(
    deliveries.cargo_icons["utility/entity_info_dark_background fluid/water"],
    "no freighter carrying water showed its icon"
  )
  local home, out = remote.call("jatz-distribution", "freighter_counts", deliveries.connected)
  assert(home == 3 and out == 0, "the delivered freighter was not returned to its slot")
  assert(not stops.drone.valid, "the unloaded freighter did not park")
  -- Grey on the way out, iron plates' paint on the way home.
  result.paint_out = stops.empty_paint
  result.paint_home = stops.home_paint
  result.paint_swapped = stops.swapped
  local sticky = deliveries.sticky
  result.sticker_kept = sticky.kept == true
  result.sticker_then_painted = sticky.painted_after_sticker == true and sticky.painted_on_road == true
  result.sticky_received = count(sticky.request, sticky.item)
  local paints = prototypes.mod_data["jatz-freighter-colors"].data
  result.paint_iron_plate = paints.items["iron-plate"] == IRON_PAINT
  result.paint_water = paints.fluids.water == WATER_PAINT
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
  -- Robots replaced the destroyed freighter: its depot has its 3 again.
  result.destroyed_restocked = remote.call("jatz-distribution", "freighter_counts", destroyed.request)
  -- Enemies: the biter on the road was run over by the freighter (impact damage), which delivered
  -- anyway; the player beside it was unhurt. Biters destroyed the ambushed freighter; its depot
  -- asked for a replacement at once, its other freighters filled the request, and robots brought
  -- the replacement.
  local runover, ambush, killed = deliveries.runover, deliveries.ambush, storage.killed or {}
  result.runover_received = count(runover.request, runover.item)
  result.runover_biter = killed[runover.biter_id] or "alive"
  result.bystander_unhurt = runover.bystander.health == runover.bystander.max_health
  result.ambush_killed_by = killed[ambush.drone_id] or "unknown"
  result.ambush_exploded = ambush.exploded
  result.ambush_wrecks = ambush.wrecks
  result.ambush_replacement_requested = ambush.requested
  result.ambush_received = count(ambush.request, ambush.item)
  result.ambush_freighters_home = remote.call("jatz-distribution", "freighter_counts", ambush.request)
  -- Freighters out pollute a little, credited to them in the pollution statistics.
  result.freighters_polluted = game.get_pollution_statistics(surface).get_input_count(DRONE) > 0
  result.changed_provider_left = count(changed.provider, changed.item)
  result.changed_received = count(changed.request, changed.item)
  result.changed_status = status(changed.request)
  result.cut_returned = count(cut.provider, cut.item)
  result.cut_received = count(cut.request, cut.item)
  result.cut_status = status(cut.request)
  -- Without re-planning, a freighter stands stuck about six seconds before giving up.
  result.cut_turnaround = cut.returned - cut.done
  assert(result.cut_turnaround < 240, "the cut was noticed late: " .. result.cut_turnaround .. " ticks")
  -- Without a retry on road changes, the 10 s cooldown would hold this one back. The trip includes
  -- its two 1 s stops to load and unload, and the 12-tile drive there and back at the drone's speed.
  result.mended_delay = deliveries.mended.delivered - deliveries.mended.done
  local mended_trip = 2 * 12 / prototypes.entity[DRONE].speed + 2 * 60
  assert(result.mended_delay < mended_trip + 280, "the mended road was used late: " .. result.mended_delay .. " ticks")
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
  -- Several freighters, sent one after another, from both providers, all back in the slot.
  local multi = deliveries.multi
  local departures = {}
  for _, departed in pairs(multi.seen) do
    departures[#departures + 1] = departed
  end
  table.sort(departures)
  result.multi_freighters_sent = #departures
  result.multi_spacing = departures[2] and departures[2] - departures[1] or 0
  -- At least a second between departures; the drone is sampled each tick near the zone.
  assert(result.multi_spacing >= 60, "freighters left too close together: " .. result.multi_spacing .. " ticks apart")
  result.multi_received = count(multi.request, "iron-stick")
  result.multi_from_near = 30 - count(multi.near, "iron-stick")
  result.multi_from_far = 40 - count(multi.far, "iron-stick")
  result.multi_freighters_home = remote.call("jatz-distribution", "freighter_counts", multi.request)
  result.no_trucks_status = status(deliveries.no_trucks)
  local buffering = deliveries.buffering
  result.buffered_request = count(buffering.request, "copper-cable")
  result.buffer_taken_from = 30 - count(buffering.stocked, "copper-cable")
  result.buffer_filled = count(buffering.filling, "copper-cable")
  result.buffer_provider_left = count(buffering.provider, "copper-cable")
  local circuit = deliveries.circuit
  result.circuit_before = circuit.before
  result.circuit_walls = count(circuit.request, "stone-wall")
  result.circuit_lamps = count(circuit.lamps, "small-lamp")
  result.circuit_after = monitor_reading(circuit.monitor)
  result.circuit_status_after = circuit.gated.custom_status == nil
  result.circuit_readings_after = readings_shown(circuit.readings)
  -- The pasted monitor took its output back; the shared group kept its signal.
  local pasted = circuit.pasted.get_control_behavior()
  local first = pasted.get_section(1)
  result.monitor_pasted = {
    shows = readings_shown({ pasted = circuit.pasted }).pasted,
    own = pasted.enabled
      and pasted.sections_count == 1
      and first.group == ""
      and first.active
      and first.multiplier == 1,
    group = readings_shown({ source = circuit.grouped[1], other = circuit.grouped[2] }),
  }
  -- Each depot condition against a lamp's, the game's own, on the same wires.
  result.condition_parity = {}
  for name, case in pairs(deliveries.parity) do
    result.condition_parity[name] = {
      native = not case.lamp.get_control_behavior().disabled,
      depot = remote.call("jatz-distribution", "get_circuit", case.depot).fulfilled,
    }
  end
  -- What each condition reads, long after the monitor first counted: the circuit network without
  -- the depot's own wood, or its own wood.
  local modes = deliveries.modes
  local function holds(name, constant)
    if constant then
      local condition = { first_signal = { type = "item", name = "wood" }, comparator = ">", constant = constant }
      remote.call("jatz-distribution", "set_circuit", modes[name], true, condition)
    end
    return remote.call("jatz-distribution", "get_circuit", modes[name]).fulfilled
  end
  result.circuit_modes = {
    -- What the wires carry: 300 + 2800 on the red one; on the green one, the monitor's 2800 (the
    -- remote provider: the other two are switched off) and the monitored depot's own 300.
    wired_wire = modes.wired
      .get_circuit_network(defines.wire_connector_id.circuit_red)
      .get_signal({ type = "item", name = "wood" }),
    monitored_wire = modes.monitored
      .get_circuit_network(defines.wire_connector_id.circuit_green)
      .get_signal({ type = "item", name = "wood" }),
    wired = holds("wired"),
    monitored = holds("monitored"),
    own = holds("own"),
    own_mode = remote.call("jatz-distribution", "get_circuit", modes.own).mode,
    wired_2700 = holds("wired", 2700),
    monitored_2700 = holds("monitored", 2700),
    own_300 = holds("own", 300),
  }
  -- Wood taken out of a depot reading the circuit network this tick, after the mod sampled it (its
  -- on_tick runs first): the wire still carries its 300, so 300 is what it takes back out
  -- (Pullfrog's review of 08bed57). 2800 elsewhere is not more than 2900, before or after.
  local before_transfer = holds("wired", 2900)
  modes.wired.remove_item({ name = "wood", count = 200 })
  result.circuit_transfer = {
    before = before_transfer,
    after = holds("wired"),
    wire = modes.wired
      .get_circuit_network(defines.wire_connector_id.circuit_red)
      .get_signal({ type = "item", name = "wood" }),
    held = modes.wired.get_item_count("wood"),
  }
  -- A cloned monitor put none of the original's count on the wire before its first update.
  result.monitor_clone = { before = deliveries.cloning.before, after = deliveries.cloning.after }
  -- The other force's provider, merged into the player's at tick 299, now counts.
  result.monitor_after_merge = readings_shown({ shown = modes.monitor }).shown
  local prioritised = deliveries.prioritised
  result.priority_from_far = 20 - count(prioritised.far, "stone")
  result.priority_from_near = 20 - count(prioritised.near, "stone")
  local liquid = deliveries.liquid
  result.water_delivered = liquid.request.get_fluid_count("water")
  result.water_provider_left = liquid.provider.get_fluid_count("water")
  local steam = deliveries.steam
  result.steam_delivered = steam.request.get_fluid_count("steam")
  result.steam_temperature = math.floor(steam.request.get_fluid(1).temperature + 0.5)
  result.steam_buffer_left = steam.buffer.get_fluid_count("steam")
  result.steam_provider_left = steam.provider.get_fluid_count("steam")
  local fallback = deliveries.fallback
  result.fallback_delivered = fallback.request.get_fluid_count("crude-oil")
  result.fallback_buffer_left = fallback.buffer.get_fluid_count("crude-oil")
  result.liquid_robots_delivered = remote.call("jatz-distribution", "freighter_counts", deliveries.liquid_remote)
  result.trimmed_requests = remote.call("jatz-distribution", "requested_freighters", deliveries.trimmed)
  result.dropped_requested_again = remote.call("jatz-distribution", "requested_freighters", deliveries.dropped)
  result.dropped_slot = remote.call("jatz-distribution", "freighter_counts", deliveries.dropped)
  result.sent_away_requested = remote.call("jatz-distribution", "requested_freighters", deliveries.sent_away)
  result.untagged_requested_again = remote.call("jatz-distribution", "requested_freighters", deliveries.untagged)
  result.filled_by_hand_requests = remote.call("jatz-distribution", "requested_freighters", deliveries.filled)
  result.partly_filled_requests = remote.call("jatz-distribution", "requested_freighters", deliveries.partly)
  result.built_filled_requests = remote.call("jatz-distribution", "requested_freighters", deliveries.built)
  result.robots_delivered = deliveries.robots_delivered
  result.robots_removal_marked = deliveries.removal_started
  result.slot_after_removal = remote.call("jatz-distribution", "freighter_counts", deliveries.remote)
  result.storage_after_removal = deliveries.store.get_item_count(FREIGHTER)
  result.absorbed = remote.call("jatz-distribution", "freighter_counts", deliveries.absorbing)
  result.absorbed_left_in_chest = count(deliveries.absorbing, FREIGHTER)
  local on_depot, other_kept = 0, 0
  for _, proxy in
    pairs(surface.find_entities_filtered({ name = "item-request-proxy", position = deliveries.two_proxies.position }))
  do
    if proxy.proxy_target == deliveries.two_proxies then
      for _, plan in pairs(proxy.insert_plan) do
        local name = type(plan.id.name) == "string" and plan.id.name or plan.id.name.name
        for _, position in pairs(plan.items.in_inventory) do
          if name == FREIGHTER then
            on_depot = on_depot + (position.count or 1)
          elseif name == "iron-plate" then
            other_kept = other_kept + (position.count or 1)
          end
        end
      end
    end
  end
  result.two_proxies_left_on_depot = on_depot
  result.two_proxies_other_kept = other_kept
  result.two_proxies_requested = remote.call("jatz-distribution", "requested_freighters", deliveries.two_proxies)
  result.unloaded_slot = remote.call("jatz-distribution", "freighter_counts", deliveries.unloaded)
  result.unloaded_taken = count(deliveries.unloaded_into, FREIGHTER)
  -- Request depots removed by script or destroyed leave their freighters where they stood: the
  -- orphaned one (2 in its slot, 1 out) and the dying one (100 in its slot, 2 in its chest).
  result.orphaned_freighters_dropped = on_ground(surface, { { 60, 18 }, { 66, 24 } })
  result.destroyed_freighters_dropped = on_ground(surface, { { 57, 25 }, { 64, 32 } })
  -- No cargo was left on the ground anywhere.
  local _, other = on_ground(surface, { { -80, -80 }, { 80, 80 } })
  result.spilled = other
  -- Fuel: filled up before loading, 5 of 10 coal (20 MJ) or 50 of 100 petroleum gas taken, the
  -- freighter home with a full tank less the 44 tiles it drove after; the dry one stayed home
  -- until there was fuel. A Fuel depot turned by script turned its tank too.
  local fuelled, liquid_fuelled, dry = deliveries.fuelled, deliveries.liquid_fuelled, deliveries.dry
  result.fuel_stop_first = fuelled.at_fuel ~= nil and fuelled.loaded ~= nil and fuelled.at_fuel < fuelled.loaded
  result.fuel_delivered = count(fuelled.request, "iron-ore")
  result.fuel_coal_left = count(fuelled.fuel, "coal")
  result.fuel_hover, result.fuel_hover_diode = fuelled.hover, fuelled.hover_diode
  result.fuel_left_mj =
    math.floor(remote.call("jatz-distribution", "freighter_fuel", fuelled.request).home[1] / 1000000)
  result.liquid_fuel_delivered = count(liquid_fuelled.request, "copper-ore")
  result.liquid_fuel_taken = math.floor(100 - liquid_fuelled.tank.get_fluid_count("petroleum-gas") + 0.5)
  result.no_fuel_status = dry.waiting_status
  result.no_fuel_received_before = dry.waiting_received
  result.no_fuel_status_after_coal = dry.after_coal_status
  result.no_fuel_received_after = count(dry.request, "sulfur")
  result.no_fuel_coal_left = count(dry.fuel, "coal")
  local turned = storage.turned_fuel
  result.fuel_tank_turned = turned.tank.valid
    and turned.tank.direction == turned.depot.direction
    and turned.depot.direction ~= turned.from
  return true
end

script.on_init(function()
  -- The undo scenario (scenarios/undo) runs alone: no check world beside it.
  if script.level.mod_name == "jatz-distribution-check" then
    return
  end
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
    recipes = {},
    ghosts = 0,
    placed = 0,
    rotations = 0,
    pipe_connections = 0,
    localised_names = {},
    cleared_zones = 0,
    tank_sizes = {},
    wired_depots = 0,
  }
  check_research(result)
  for row, role in ipairs(ROLES) do
    check_depot(surface, role, row - 1, result)
  end
  check_loading_zone_clearing(surface, result)

  -- Players place the freighter as a car only with the jatz-freighter-drivable startup setting,
  -- off by default (as here); the car stays defined, so a script-made one still drives below.
  result.freighter_placeable = settings.startup["jatz-freighter-drivable"].value
  check_recipe(FREIGHTER, result, not result.freighter_placeable)
  -- Drawn at 60% of the artwork's scale, with the boxes scaled to match.
  local box = prototypes.entity[FREIGHTER].collision_box
  result.freighter_box = { box.right_bottom.x - box.left_top.x, box.right_bottom.y - box.left_top.y }
  check_road(result)
  check_recipe(MONITOR, result)
  -- With Space Age, the freighter fuelled with carbon.
  if prototypes.recipe[FREIGHTER_CARBON] then
    record_recipe(FREIGHTER_CARBON, FREIGHTER, result)
    result.localised_names[FREIGHTER_CARBON] =
      { recipe = locale_key(prototypes.recipe[FREIGHTER_CARBON].localised_name) }
  end
  check_road_placement(surface, result)
  -- The request panel's status light uses the game's own status indicators.
  result.status_lights = 0
  for _, sprite in ipairs({
    "utility/status_working",
    "utility/status_yellow",
    "utility/status_not_working",
    "utility/status_inactive",
  }) do
    assert(helpers.is_valid_sprite_path(sprite), sprite .. " is not a sprite")
    result.status_lights = result.status_lights + 1
  end
  setup_depot_roads(surface, result)
  check_menu_placement(result)
  setup_deliveries(surface, result)
  setup_mining(surface)
  check_milestones(result)
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

-- What killed the entities the enemy checks watch, as "killer/damage type", by unit_number.
script.on_event(defines.events.on_entity_died, function(event)
  storage.killed = storage.killed or {}
  storage.killed[event.entity.unit_number] = string.format(
    "%s/%s",
    event.cause and event.cause.name or "none",
    event.damage_type and event.damage_type.name or "none"
  )
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
  watch_researched(surface)
  interfere(surface)
  lay_road_under(surface, result)
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
