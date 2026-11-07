-- SPDX-License-Identifier: LGPL-3.0-only
-- Builds the benchmark map (layout.lua) for whichever logistics mod is loaded, Jat'z Distribution
-- or Transport Drones, and keeps it busy: providers and fuel depots are topped up and request depots
-- emptied, each depot once a second, spread over the ticks so no tick carries all of it. Both mods
-- get exactly the same map, stock and demand; only Jat'z Distribution builds the fuel depots, since
-- Transport Drones keeps its drones' fuel in each request depot. tools/benchmark_ups.py runs the save with `--benchmark` and reads the
-- per-tick timings; this mod writes what was built and how busy it was to
-- script-output/ups-benchmark.json.
local layout = require("layout")
local presets = require("presets")
local preset_name = require("selected-preset")

-- Every depot is serviced once per this many ticks, a 1/PERIOD share of them each tick.
local PERIOD = 60
-- Vehicles on the road are counted this often.
local SAMPLE_TICKS = 600
local CHEST_SLOTS = 48

local adapters = {}

-- Jat'z Distribution: road tile, depots and freighters through its remote interface. Freighters
-- fill up at the fuel depots by themselves.
adapters["jatz-distribution"] = {
  road = "jatz-road",
  entity = { provider = "jatz-provider-depot", request = "jatz-request-depot", fuel = "jatz-fuel-depot" },
  -- Unrotated, a depot loads to the south (prototypes/orientation.lua): the direction to face for
  -- a road on each side, and where the loading tile then is from the depot's centre.
  direction = {
    south = defines.direction.north,
    north = defines.direction.south,
    west = defines.direction.east,
    east = defines.direction.west,
  },
  shift = { north = { 0, -2 }, south = { 0, 2 }, east = { 2, 0 }, west = { -2, 0 } },
  setup = function() end,
  request = function(entity, depot)
    local count = prototypes.item[depot.item].stack_size * CHEST_SLOTS
    assert(remote.call("jatz-distribution", "set_request", entity, depot.item, count), "request refused")
    local added = remote.call("jatz-distribution", "add_freighters", entity, depot.freighters)
    -- Versions from before fuel (benchmarked with --compare) have neither.
    if remote.interfaces["jatz-distribution"].set_freighter_fuel then
      local tank = settings.global["jatz-freighter-fuel-capacity"].value * 1000000
      remote.call("jatz-distribution", "set_freighter_fuel", entity, depot.fuel * tank)
    end
    return added
  end,
  output = function(entity)
    return entity.get_inventory(defines.inventory.chest)
  end,
  refuel = function() end,
  -- A provider keeping a minimum (layout.lua): switched on only while its own contents hold more
  -- than that share of a full chest. Returns whether it has the condition (versions without
  -- conditions on a depot's own contents, benchmarked with --compare, don't).
  provider = function(entity, depot)
    local count = math.floor(prototypes.item[depot.item].stack_size * CHEST_SLOTS * depot.minimum)
    return remote.call("jatz-distribution", "set_circuit", entity, true, {
      first_signal = { type = "item", name = depot.item },
      comparator = ">",
      constant = count,
    }, "contents") == true
  end,
}

-- Transport Drones: request depots are crafting machines whose recipe is the request, holding
-- drones and the drones' fuel. Fuel is kept topped up here rather than by fuel depots, so the
-- drones' fuel bookkeeping runs but no fuel deliveries do. It has no depot for the map's fuel
-- depots (nil), so they aren't built.
local function td_fuel()
  return prototypes.recipe["fuel-depots"].products[1].name
end
adapters["Transport_Drones"] = {
  road = "transport-drone-road",
  entity = { provider = "supply-depot", request = "request-depot" },
  -- A depot's road node is two tiles out in the direction it faces
  -- (script/depots/request_depot.lua corpse_offsets).
  direction = {
    north = defines.direction.north,
    south = defines.direction.south,
    east = defines.direction.east,
    west = defines.direction.west,
  },
  shift = { north = { 0, -2 }, south = { 0, 2 }, east = { 2, 0 }, west = { -2, 0 } },
  setup = function(force)
    for _, item in ipairs(layout.items) do
      force.recipes["request-" .. item].enabled = true
    end
  end,
  request = function(entity, depot)
    entity.set_recipe("request-" .. depot.item)
    entity.insert_fluid({ name = td_fuel(), amount = 100000 })
    return entity
      .get_inventory(defines.inventory.crafter_input)
      .insert({ name = "transport-drone", count = depot.freighters })
  end,
  output = function(entity)
    return entity.get_output_inventory()
  end,
  refuel = function(entity)
    entity.insert_fluid({ name = td_fuel(), amount = 100000 })
  end,
  -- Transport Drones' supply depots have no circuit condition: those keeping a minimum stay plain.
  provider = function()
    return false
  end,
}

local function target()
  for name in pairs(adapters) do
    if script.active_mods[name] then
      return name
    end
  end
  error("ups-benchmark: neither jatz-distribution nor Transport_Drones is loaded")
end

local function make_surface(name, extent)
  local surface = game.create_surface(name)
  surface.generate_with_lab_tiles = true
  surface.always_day = true
  local radius = math.ceil(math.max(math.abs(extent[1]), math.abs(extent[2])) / 32) + 1
  surface.request_to_generate_chunks({ 0, 0 }, radius)
  surface.force_generate_chunk_requests()
  return surface
end

local function build_depot(adapter, surface, force, depot)
  local shift = adapter.shift[depot.side]
  local entity = surface.create_entity({
    name = adapter.entity[depot.role],
    position = { depot.x + 0.5 - shift[1], depot.y + 0.5 - shift[2] },
    direction = adapter.direction[depot.side],
    force = force,
    raise_built = true,
  })
  assert(entity, "ups-benchmark: cannot place " .. depot.role .. " depot at " .. depot.x .. "," .. depot.y)
  return entity
end

local function build()
  local name = target()
  local adapter = adapters[name]
  local preset = presets[preset_name]
  local map = layout.generate(preset)
  local force = game.forces.player
  adapter.setup(force)
  local summary = layout.summary(map)
  summary.target, summary.target_version, summary.preset = name, script.active_mods[name], preset_name
  summary.freighters_placed = 0
  summary.fuel = 0
  -- Providers that got their minimum's condition (layout's `minimums` is how many were planned).
  summary.minimums_set = 0
  local depots = {}
  for _, plan in ipairs(map.surfaces) do
    local surface = make_surface(plan.name, plan.extent)
    local tiles = {}
    for _, rect in ipairs(plan.roads) do
      for x = rect[1], rect[3] do
        for y = rect[2], rect[4] do
          tiles[#tiles + 1] = { name = adapter.road, position = { x, y } }
        end
      end
    end
    surface.set_tiles(tiles, true, true, true, true)
    for _, depot in ipairs(plan.depots) do
      -- Fuel depots only where the mod has them (not Transport Drones, nor versions before fuel).
      local entity_name = adapter.entity[depot.role]
      if depot.role ~= "fuel" or (entity_name and prototypes.entity[entity_name]) then
        local entity = build_depot(adapter, surface, force, depot)
        if depot.role == "request" then
          summary.freighters_placed = summary.freighters_placed + adapter.request(entity, depot)
        elseif depot.role == "fuel" then
          summary.fuel = summary.fuel + 1
        elseif depot.minimum and adapter.provider(entity, depot) then
          summary.minimums_set = summary.minimums_set + 1
        end
        depots[#depots + 1] = { entity = entity, role = depot.role, item = depot.item }
      end
    end
  end
  storage.depots = depots
  storage.summary = summary
  storage.samples = {}
  storage.delivered = 0
end

-- One share of the depots: providers and fuel depots filled up, request depots emptied (counted as
-- delivered).
local function service(tick)
  local adapter = adapters[storage.summary.target]
  local depots = storage.depots
  for index = tick % PERIOD + 1, #depots, PERIOD do
    local depot = depots[index]
    local entity = depot.entity
    if entity.valid then
      if depot.role == "provider" or depot.role == "fuel" then
        entity.insert({ name = depot.item, count = prototypes.item[depot.item].stack_size * CHEST_SLOTS })
      else
        local output = adapter.output(entity)
        storage.delivered = storage.delivered + output.get_item_count(depot.item)
        output.remove({ name = depot.item, count = 1000000 })
        adapter.refuel(entity)
      end
    end
  end
end

local function sample(tick)
  local vehicles = 0
  for _, surface in pairs(game.surfaces) do
    if surface.name:find("^ups%-benchmark%-") then
      vehicles = vehicles + surface.count_entities_filtered({ type = "unit" })
    end
  end
  local samples = storage.samples
  samples[#samples + 1] = { tick = tick, vehicles = vehicles, delivered = storage.delivered }
  helpers.write_file(
    "ups-benchmark.json",
    helpers.table_to_json({ summary = storage.summary, samples = samples }),
    false
  )
end

script.on_init(build)

script.on_event(defines.events.on_tick, function(event)
  service(event.tick)
  if event.tick % SAMPLE_TICKS == 0 then
    sample(event.tick)
  end
end)
