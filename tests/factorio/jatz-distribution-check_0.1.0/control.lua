-- SPDX-License-Identifier: LGPL-3.0-only
-- Checks that every Jat'z Distribution item is free to craft and can be placed, that every
-- depot works in all four directions with its pipe ports, and that the freighter can be driven.
-- Writes script-output/jatz-distribution-check.json; tools/test_mod.py runs it headless.

local FREIGHTER = "jatz-quinityn-freighter"
local ROLES = { "provider", "request", "buffer", "fuel", "liquid-provider", "liquid-request", "liquid-buffer" }
local HEADINGS = { defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west }
local VECTORS = { [0] = { 0, -1 }, [4] = { 1, 0 }, [8] = { 0, 1 }, [12] = { -1, 0 } }
local DRIVE_TICKS = 120
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

  local result = {
    engine = script.active_mods.base,
    mod = script.active_mods["jatz-distribution"],
    free_recipes = 0,
    ghosts = 0,
    placed = 0,
    rotations = 0,
    pipe_connections = 0,
    localised_names = {},
  }
  for row, role in ipairs(ROLES) do
    check_depot(surface, role, row - 1, result)
  end

  check_recipe(FREIGHTER, result)
  check_menu_placement(result)
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
  if not storage.result or storage.result.driven_tiles or event.tick < DRIVE_TICKS then
    return
  end
  local freighter, result = storage.freighter, storage.result
  local dx, dy = freighter.position.x - storage.start.x, freighter.position.y - storage.start.y
  result.driven_tiles = math.sqrt(dx * dx + dy * dy)
  result.speed = freighter.speed
  assert(result.driven_tiles > 1, "freighter: did not drive")
  helpers.write_file("jatz-distribution-check.json", helpers.table_to_json(result), false)
  log("JATZ_DISTRIBUTION_CHECK passed")
end)
