-- SPDX-License-Identifier: LGPL-3.0-only
-- Deliveries between provider and request depots.
--
-- A request depot asks to keep at least `count` of one item (normal quality), and holds the
-- freighters that fetch it: up to 100 of them, in its freighter slot. Once a second, while what it
-- still needs (less what freighters are already bringing) is more than nothing, it sends one more
-- freighter, so freighters leave one after another rather than all at once. Each goes from the
-- depot's loading zone to the provider depot with the highest priority (1 to 10), nearest by road
-- among equals, that has some of the item not already promised to another freighter, and promises
-- itself what it will load there (up to ten stacks); once one provider's stock is all promised,
-- the next freighter goes to the next provider, so a large request is gathered from several. Road distance comes from the engine's pathfinder (surface.request_path, with the
-- freighter's own size and collision mask), asked one provider at a time in order of straight-line
-- distance until no remaining provider could be nearer by road than the best found; a provider
-- with no road route at all is skipped for a while, and no freighter is sent towards it. The freighter
-- loads what is needed (no more than fits at the request depot, and at most ten stacks), drives
-- back, unloads and leaves the map. Freighters are units whose only collision layer is on every
-- tile except roads (prototypes/off-road.lua), so the engine's pathfinder keeps them on roads;
-- both loading zones must be road for a trip to start.
--
-- Cargo travels as real item stacks in a script inventory, so item data (equipment in armor,
-- spoilage, health) arrives intact. If the way back is lost, the freighter returns its cargo to
-- the provider; only when that fails too is the cargo left on the ground, marked for
-- deconstruction. A freighter destroyed on the way is lost with its cargo, like any destroyed
-- vehicle, and its depot asks construction robots for a replacement (a player can put one in by
-- hand instead); otherwise every freighter goes back into its depot's slot when its trip ends.
--
-- Enemies can attack freighters, which never fight back or turn aside: they drive on until they
-- arrive or are destroyed. A moving freighter runs over the enemy units it drives through, as a
-- train does, but never harms players or other freighters, and collides with none of them. Every
-- freighter out pollutes a little, as Transport Drones' drones do.
--
-- Depots are registered when built or cloned (control.lua), found again on load, and forgotten
-- when destroyed. A request depot mined by a player or robot hands over all its freighters, in the
-- slot and out on trips; one destroyed leaves them on the ground where it stood.
--
-- A freighter's cargo paint shows its load: light grey while empty, then the color of the item or
-- fluid it loaded (scripts/freighter-paint.lua) until its trip ends. Units have no runtime color,
-- so loading swaps the freighter for the drone prototype in that paint (`repaint`), and its trip
-- moves to the new unit_number.
--
-- Freighters need fuel. Each carries its own (as energy), starts with a full tank, burns it by the
-- tile as it drives, and fills up at Fuel depots by itself: from any burnable item in the depot,
-- or any burnable fluid piped into it. Before each leg (setting off from home, leaving a provider,
-- heading for a new provider) a freighter checks its tank against the leg's road length; short,
-- it first drives to the Fuel depot nearest by road, fills up, then goes on where it was going. One
-- whose tank runs dry crawls on to a Fuel depot, or to where it was going if there is none. One that
-- can't reach the provider on what it has, with no Fuel depot to fill up at, stays home.
--
-- Every delivery depot (provider, request or buffer; not the Fuel depot) can have an
-- enable/disable circuit condition, like a logistic chest's (scripts/depot-circuit.lua), on the
-- circuit network without its own contents or on its own contents. While it is in effect and
-- doesn't hold, the depot is disabled: it sends no freighters, and none are sent to fetch from it.
-- Freighters already on their way finish their trips.
local loading_zone = require("scripts.loading-zone")
local paint = require("scripts.freighter-paint")
local depot_circuit = require("scripts.depot-circuit")

local logistics = {}

local PROVIDER = "jatz-provider-depot"
local REQUEST = "jatz-request-depot"
-- Buffer depots request like request depots (their own request, freighters and panel), but their
-- freighters only fetch from provider depots. Request depots fetch from them too: first if set to
-- "request from buffer depots", otherwise only for what no provider can supply.
local BUFFER = "jatz-buffer-depot"
-- Provider and buffer depots have a priority from 1 to 10: a requesting depot fetches from the
-- highest it can reach by road, nearest first among equals. Priority only orders depots of one
-- kind: buffer depots all still come before providers for request depots that request from them,
-- and after them for the rest.
local PRIORITY_MIN, PRIORITY_MAX, PRIORITY_DEFAULT = 1, 10, 5
logistics.priority = { min = PRIORITY_MIN, max = PRIORITY_MAX, default = PRIORITY_DEFAULT }
local ROAD = "jatz-road"
-- The road a depot lays under its own loading zone (scripts/depot-road.lua).
local DEPOT_ROAD = "jatz-depot-road"
-- The empty freighter; painted ones are paint.names() (scripts/freighter-paint.lua).
local DRONE = paint.empty
-- The freighter item: what a request depot's freighter slot holds.
local FREIGHTER = "jatz-quinityn-freighter"
-- A request depot holds up to this many freighters (in its slot and out on trips together). The
-- freighter item stacks to 10, so the slot is that many stacks, shown as one slot in the panel.
local FREIGHTER_CAPACITY = 100
-- Liquid depots work like the item depots of the same role, for fluids: a liquid request depot
-- keeps a fluid in stock, fetched from liquid provider depots and liquid buffer depots (buffers
-- first if set to, last otherwise); a liquid buffer depot fetches from liquid providers only.
-- Items and fluids never meet: item depots deal only with item depots, liquid depots only with
-- liquid depots.
local LIQUID_PROVIDER = "jatz-liquid-provider-depot"
local LIQUID_REQUEST = "jatz-liquid-request-depot"
local LIQUID_BUFFER = "jatz-liquid-buffer-depot"
logistics.depots = {
  [PROVIDER] = "provider",
  [REQUEST] = "request",
  [BUFFER] = "buffer",
  [LIQUID_PROVIDER] = "provider",
  [LIQUID_REQUEST] = "request",
  [LIQUID_BUFFER] = "buffer",
}
-- Mining Drones' mining depot, with one of its mods installed, is an item provider depot of what
-- its drones mine: that collects in its output inventory, which freighters load from.
local MINING_DEPOT = loading_zone.mining_depot
if loading_zone.depots[MINING_DEPOT] then
  logistics.depots[MINING_DEPOT] = "provider"
end
-- The Fuel depot: a container for fuel items with a hidden storage tank under it for liquid fuel
-- (prototypes/depots.lua). Freighters fill up there; it takes no part in deliveries.
local FUEL = "jatz-fuel-depot"
local FUEL_TANK = "jatz-fuel-depot-tank"
logistics.depots[FUEL] = "fuel"
logistics.fuel_depot = FUEL
logistics.fuel_tank = FUEL_TANK
local LIQUID = { [LIQUID_PROVIDER] = true, [LIQUID_REQUEST] = true, [LIQUID_BUFFER] = true }
logistics.liquid = LIQUID
-- Depots that request (send freighters out for an item or fluid): request and buffer depots.
local REQUESTING = { request = true, buffer = true }
logistics.requesting = { [REQUEST] = true, [BUFFER] = true, [LIQUID_REQUEST] = true, [LIQUID_BUFFER] = true }
logistics.drone = DRONE
logistics.drones = paint.names()
logistics.freighter = FREIGHTER
-- Liquid depots are storage tanks, with no item inventory: robots bring their freighters into
-- this invisible chest under them instead (prototypes/truck-chest.lua).
local TRUCK_CHEST = "jatz-truck-chest"
logistics.truck_chest = TRUCK_CHEST

-- Request depots are checked this often (control.lua calls logistics.on_tick).
local DISPATCH_INTERVAL = 60
logistics.dispatch_interval = DISPATCH_INTERVAL
-- A request depot sends at most one freighter this often, so they leave one after another.
local SEND_SPACING = 60
-- A freighter carries at most this many stacks, or this much fluid (Transport Drones' default
-- drone fluid capacity).
local CAPACITY_STACKS = 10
local FLUID_CAPACITY = 500
logistics.fluid_capacity = FLUID_CAPACITY
-- After a provider can't be reached, a request depot ignores it for this long; after a freighter
-- can't be created, the depot waits this long before trying again. Laying road, or building or
-- turning a depot, ends every wait on that surface at once (logistics.on_roads_changed and
-- logistics.on_depot_changed), so this only matters for changes the game doesn't report.
local RETRY_TICKS = 10 * 60
-- How close a freighter must get to a loading zone's centre to load or unload there.
local ARRIVAL_RADIUS = 0.5
-- How long a freighter stands at a loading zone to load or unload before it moves on.
local LOADING_TICKS = 60
-- A search for the nearest provider by road that hasn't answered in this long (a save loaded
-- mid-search, say) is started again.
local SEARCH_TIMEOUT = 10 * 60
-- Requests are for normal-quality items.
local QUALITY = "normal"
-- Pollution each freighter out makes a second: Transport Drones' default for its drones.
local POLLUTION_PER_SECOND = 0.005
-- How often moving freighters look for enemy units they are driving through, and the impact
-- damage each one hit takes, at most once a second from the same freighter. Freighters never
-- attack; this is them running enemies over, as trains do. 200 kills small and medium biters
-- outright and hurts bigger ones.
local IMPACT_INTERVAL = 10
local IMPACT_DAMAGE = 200
local IMPACT_COOLDOWN = 60
-- What a freighter runs over: enemy units only, never players (characters), buildings or other
-- freighters.
local IMPACT_TYPES = { "unit", "spider-unit", "segmented-unit" }
-- A freighter fills up before a leg unless its tank holds what the leg's road length takes, times
-- this (its path may differ from the road measured), plus this share of a full tank in reserve.
local FUEL_MARGIN = 1.25
local FUEL_RESERVE = 0.1
-- A freighter whose tank is dry crawls at this share of its speed.
local DRY_SPEED = 0.1

-- Status of a request depot, shown in its window: a key in the [jatz-request-status] locale section.
logistics.status = {
  none = "none",
  satisfied = "satisfied",
  full = "full",
  no_road = "no-road",
  no_provider = "no-provider",
  unreachable = "unreachable",
  no_freighter = "no-freighter",
  no_trucks = "no-trucks",
  searching = "searching",
  delivering = "delivering",
  -- A liquid depot's tank holds another fluid than the one requested.
  other_fluid = "other-fluid",
  -- Its freighters can't reach the provider on the fuel they have, and the Fuel depots their road
  -- reaches have no fuel: they go once one has some.
  no_fuel = "no-fuel",
  -- Its freighters can't reach the provider on the fuel they have, and their road reaches no Fuel
  -- depot at all: red.
  no_fuel_depot = "no-fuel-depot",
  -- Its circuit condition doesn't hold.
  disabled = "disabled",
}

-- Trip states: driving out to the provider, bringing cargo to the request depot, or taking cargo
-- back to the provider after the way to the request depot was lost.
local TO_PROVIDER, TO_REQUEST, RETURNING = "to-provider", "to-request", "returning"

-- Defined further down; dispatch, the search and on_tick need them first.
local end_trip, load, freighter_requests, load_fluid, unload_fluid, set_off, target, upgrade

local function init_storage()
  storage.depots = storage.depots or {}
  storage.trips = storage.trips or {}
  -- Provider searches waiting for the pathfinder, by path request id.
  storage.searches = storage.searches or {}
end

-- Drop a request depot's current search; the next dispatch, within a second, starts a fresh one.
local function cancel_search(depot)
  depot.search_token = nil
  depot.searching = nil
end

-- A depot's item inventory: its chest, or a mining depot's output.
local function inventory(entity)
  if entity.name == MINING_DEPOT then
    return entity.get_output_inventory()
  end
  return entity.get_inventory(defines.inventory.chest)
end
logistics.inventory = inventory

-- Where a requesting depot's freighters arrive as items, and robots bring them: its own chest, or
-- for a liquid depot the truck chest under it (made if missing: a save from before liquid depots
-- delivered, or one removed by another mod).
local function truck_chest(entity)
  if not LIQUID[entity.name] then
    return entity
  end
  local depot = storage.depots and storage.depots[entity.unit_number]
  if not depot then
    return entity
  end
  if not (depot.chest and depot.chest.valid) then
    depot.chest = entity.surface.create_entity({
      name = TRUCK_CHEST,
      position = entity.position,
      force = entity.force,
      create_build_effect_smoke = false,
    })
    if depot.chest then
      depot.chest.destructible = false
    end
  end
  return depot.chest or entity
end

-- The inventory a requesting depot's freighters arrive in (see truck_chest).
local function freighter_chest(entity)
  return inventory(truck_chest(entity))
end

-- The hidden tank holding a Fuel depot's liquid fuel, facing and flipped as the depot is (made if
-- missing: a depot built before fuel, or the tank removed by another mod). Nil for anything else.
local function tank_owner(tank)
  for _, depot in pairs(storage.depots or {}) do
    if depot.tank == tank then
      return depot
    end
  end
end

-- A Fuel depot's hidden tank lying where `entity` stands that no depot owns: one cloned along with
-- the depot (it keeps its fluid, as a cloned storage tank does), or nil.
local function stray_tank(entity)
  local here = entity.position
  for _, tank in pairs(entity.surface.find_entities_filtered({ name = FUEL_TANK, position = here, radius = 0.1 })) do
    if tank.position.x == here.x and tank.position.y == here.y and not tank_owner(tank) then
      return tank
    end
  end
end

local function fuel_tank(entity)
  local depot = entity.name == FUEL and storage.depots and storage.depots[entity.unit_number]
  if not depot then
    return nil
  end
  local tank = depot.tank
  if not (tank and tank.valid) then
    tank = stray_tank(entity)
  end
  if not (tank and tank.valid) then
    tank = entity.surface.create_entity({
      name = FUEL_TANK,
      position = entity.position,
      direction = entity.direction,
      force = entity.force,
      create_build_effect_smoke = false,
    })
  end
  if tank and depot.tank ~= tank then
    tank.destructible = false
    depot.tank = tank
  end
  if tank then
    -- Scripts can turn a depot without any event: keep the port where the depot's is.
    if tank.direction ~= entity.direction then
      tank.direction = entity.direction
    end
    if tank.mirroring ~= entity.mirroring then
      tank.mirroring = entity.mirroring
    end
  end
  return tank
end
logistics.fuel_tank_of = fuel_tank

-- Fuel: a full tank and what a tile of driving burns, in joules (runtime settings, settings.lua).
local function fuel_capacity()
  return settings.global["jatz-freighter-fuel-capacity"].value * 1000000
end

-- Below this share of a full tank, a freighter's fuel shows yellow on hover.
local LOW_FUEL = 0.25

-- An amount of fuel (joules) as text: MJ, or GJ from 1,000 MJ (a mod's item can hold far more
-- than a tank).
function logistics.energy_caption(joules)
  if joules >= 1e9 then
    return { "jatz-gui.energy-gj", string.format("%.1f", joules / 1e9) }
  end
  return { "jatz-gui.energy-mj", string.format("%.1f", joules / 1e6) }
end

local function fuel_per_tile()
  return settings.global["jatz-freighter-fuel-per-tile"].value * 1000
end

-- The prototype of an item or fluid that burns, from game data (any mod's), or nil.
local function burnable_item(name)
  local item = prototypes.item[name]
  return item and item.fuel_value > 0 and item or nil
end

local function burnable_fluid(name)
  local fluid = prototypes.fluid[name]
  return fluid and fluid.fuel_value > 0 and fluid or nil
end

-- Whether a Fuel depot holds anything a freighter can fill up with: a burnable fluid in its tank,
-- or a burnable item in its chest.
local function has_fuel(depot)
  local tank = fuel_tank(depot.entity)
  local held = tank and tank.get_fluid(1)
  if held and held.amount > 0 and burnable_fluid(held.name) then
    return true
  end
  local chest = inventory(depot.entity)
  for _, item in pairs(chest.get_contents()) do
    local fuel = burnable_item(item.name)
    -- One that burns into another counts only while the depot has room for what it leaves.
    local burnt = fuel and fuel.burnt_result
    if fuel and (not burnt or chest.get_insertable_count({ name = burnt.name, quality = item.quality }) > 0) then
      return true
    end
  end
  return false
end

-- Fill a freighter's tank at a Fuel depot: burnable fluid first, then burnable items, a whole item
-- at a time (the last may fill it past full, as a burner holds the item it is burning). An item
-- that burns into another (a fuel cell into a used one) leaves that in the depot, so only as many
-- are taken as the depot has room for what they leave.
local function refuel(trip, depot)
  local capacity = fuel_capacity()
  local tank = fuel_tank(depot.entity)
  local held = tank and tank.get_fluid(1)
  local fluid = held and burnable_fluid(held.name)
  if fluid and trip.energy < capacity then
    local removed = tank.remove_fluid(1, math.min(held.amount, (capacity - trip.energy) / fluid.fuel_value))
    trip.energy = trip.energy + (removed and removed.amount or 0) * fluid.fuel_value
  end
  local chest = inventory(depot.entity)
  for index = 1, #chest do
    if trip.energy >= capacity then
      break
    end
    local stack = chest[index]
    local item = stack.valid_for_read and burnable_item(stack.name)
    if item then
      local quality = stack.quality.name
      local count = math.min(stack.count, math.ceil((capacity - trip.energy) / item.fuel_value))
      local burnt = item.burnt_result
      if burnt then
        count = math.min(count, chest.get_insertable_count({ name = burnt.name, quality = quality }))
      end
      if count > 0 then
        if count >= stack.count then
          stack.clear()
        else
          stack.count = stack.count - count
        end
        if burnt then
          chest.insert({ name = burnt.name, count = count, quality = quality })
        end
        trip.energy = trip.energy + count * item.fuel_value
      end
    end
  end
end

local function item_id(item)
  return { name = item, quality = QUALITY }
end

-- Freighters of every quality in an inventory: any freighter can be sent out.
local function count_freighters(inventory_)
  local total = 0
  for index = 1, #inventory_ do
    local stack = inventory_[index]
    if stack.valid_for_read and stack.name == FREIGHTER then
      total = total + stack.count
    end
  end
  return total
end

-- The loading zone tile's centre, and whether it is road.
local function loading_tile(entity)
  local x, y = loading_zone.tile_centre(entity)
  local tile = entity.surface.get_tile(math.floor(x), math.floor(y))
  return { x = x, y = y }, tile.valid and (tile.name == ROAD or tile.name == DEPOT_ROAD)
end

-- Remember a depot (provider, request, buffer or fuel). Safe to call again for one already known.
function logistics.add(entity)
  local role = logistics.depots[entity.name]
  if not role or not entity.unit_number then
    return
  end
  init_storage()
  local depot = storage.depots[entity.unit_number]
  if depot then
    depot.entity = entity
    fuel_tank(entity)
    return
  end
  storage.depots[entity.unit_number] = {
    entity = entity,
    role = role,
    -- Where it stands, for handing back freighters once the entity is gone.
    position = entity.position,
    surface_index = entity.surface_index,
    -- Request depots only: { item = name, count = n }, retry cooldowns per provider, the tick
    -- before which no freighter is sent, the freighters out (trip ids), the freighter slot (a
    -- one-slot script inventory, made on first use), and the status shown.
    request = nil,
    cooldowns = {},
    retry_at = 0,
    trips = {},
    trucks = nil,
    status = logistics.status.none,
    -- Liquid depots deal in fluids, with liquid depots only.
    fluid = LIQUID[entity.name] or nil,
  }
  script.register_on_object_destroyed(entity)
  if LIQUID[entity.name] and REQUESTING[role] then
    truck_chest(entity)
  end
  fuel_tank(entity)
end

-- A request depot's freighter slot: room for FREIGHTER_CAPACITY freighters, as real items, in as
-- many stacks as that takes. Slots from saves when it held one stack are made bigger.
local function trucks_of(depot)
  local stacks = math.ceil(FREIGHTER_CAPACITY / prototypes.item[FREIGHTER].stack_size)
  if not (depot.trucks and depot.trucks.valid) then
    depot.trucks = game.create_inventory(stacks)
  elseif #depot.trucks < stacks then
    depot.trucks.resize(stacks)
  end
  return depot.trucks
end

-- The first stack of freighters in a depot's slot, or nil.
local function a_freighter(depot)
  local slot = trucks_of(depot)
  for index = 1, #slot do
    if slot[index].valid_for_read then
      return slot[index]
    end
  end
end

-- The fuel of the freighters parked in a requesting depot's slot whose tank isn't exactly full, in
-- joules, lowest first: less than a tank, or more (a fuel item worth more than a tank goes in
-- whole); the others have a full tank (new freighters come with one). Freighters taken out of the
-- slot (by hand, by robots, or with the depot) take the full ones first, then the fullest entries.
local function parked_fuel(depot)
  local parked = depot.fuel or {}
  depot.fuel = parked
  table.sort(parked)
  local count = trucks_of(depot).get_item_count()
  while #parked > count do
    table.remove(parked)
  end
  return parked
end

-- The ids of a request depot's trips. Saves from before depots sent several freighters kept one.
local function trips_of(depot)
  if not depot.trips then
    depot.trips = {}
    if depot.trip then
      depot.trips[depot.trip] = true
      depot.trip = nil
    end
  end
  return depot.trips
end

-- A trip's cargo: item stacks in a script inventory (`trip.cargo`), or for a liquid depot's trip a
-- fluid (`trip.fluid`: { amount, temperature }; fluids have no item data to keep).
local function cargo_amount(trip)
  if trip.fluid then
    return trip.fluid.amount
  end
  return trip.cargo and trip.cargo.valid and trip.cargo.get_item_count(item_id(trip.item)) or 0
end

local function cargo_empty(trip)
  if trip.fluid then
    return trip.fluid.amount <= 0
  end
  return not (trip.cargo and trip.cargo.valid) or trip.cargo.is_empty()
end

-- The paint for what a trip's freighter carries.
local function paint_of(trip)
  return cargo_empty(trip) and DRONE or paint.drone_for_cargo(trip.fluid ~= nil, trip.item)
end

-- Put trip `id`'s freighter in the paint for what it carries: the same freighter, where it stands,
-- facing the same way and as damaged, as the drone prototype in that paint, and the trip moves to
-- the new unit_number. Only between commands: the new unit has none. Returns whether its paint is
-- right now.
-- Not while anything is stuck to it (fire, acid, slowdown): stickers are entities of their own,
-- stuck to this unit for good, and one made anew on another unit would restart its damage cycle,
-- adding or skipping a hit. A paint is only a look, so the freighter keeps its old one until they
-- wear off, and logistics.on_tick paints it then (`repaint_pending`).
-- Show a freighter's fuel on hover, as its status: green, yellow below LOW_FUEL of a tank, red
-- once dry. Nothing while fuel is turned off.
local function show_fuel(trip)
  local drone = trip.drone
  if not drone.valid then
    return
  end
  if fuel_per_tile() <= 0 then
    drone.custom_status = nil
    return
  end
  local capacity = fuel_capacity()
  local energy = trip.energy or capacity
  local diode = energy <= 0 and "red" or energy < capacity * LOW_FUEL and "yellow" or "green"
  drone.custom_status = {
    diode = defines.entity_status_diode[diode],
    label = { "jatz-gui.freighter-fuel", logistics.energy_caption(energy), logistics.energy_caption(capacity) },
  }
end

local function repaint(id, trip)
  local old = trip.drone
  local name = paint_of(trip)
  if not old.valid or old.name == name then
    return true
  end
  if next(old.stickers or {}) then
    return false
  end
  local drone = old.surface.create_entity({ name = name, position = old.position, force = old.force })
  if not drone then
    return false
  end
  drone.orientation = old.orientation
  drone.health = old.health
  -- A dry freighter crawls (DRY_SPEED): the new one must too.
  drone.speed = old.speed
  local new = drone.unit_number
  storage.trips[id], storage.trips[new] = nil, trip
  local depot = storage.depots[trip.request]
  if depot then
    local trips = trips_of(depot)
    trips[id], trips[new] = nil, true
  end
  script.register_on_object_destroyed(drone)
  trip.drone = drone
  show_fuel(trip)
  -- Its on_object_destroyed finds no trip under the old number, so nothing else happens.
  old.destroy()
  return true
end

-- In alt mode a loaded freighter shows what it carries, as machines show their recipe: the item's
-- or fluid's icon over the dark entity info background. Both are drawn on the freighter, so they
-- move with it and go when it leaves the map, or is swapped for another paint (`repaint`): call
-- this after repainting. An empty freighter shows nothing.
local function show_cargo(trip)
  if cargo_empty(trip) or not trip.drone.valid then
    return
  end
  for _, sprite in ipairs({ "utility/entity_info_dark_background", (trip.fluid and "fluid/" or "item/") .. trip.item }) do
    rendering.draw_sprite({
      sprite = sprite,
      target = trip.drone,
      surface = trip.drone.surface,
      only_in_alt_mode = true,
      render_layer = "entity-info-icon",
      x_scale = 0.6,
      y_scale = 0.6,
    })
  end
end

-- What a trip will bring: what it promised to load while on its way out, its cargo on the way back.
local function bringing(trip)
  if trip.state == TO_PROVIDER then
    return trip.planned or 0
  elseif trip.state == TO_REQUEST then
    return cargo_amount(trip)
  end
  return 0
end

-- What a request depot's freighters, except trip `except`, are bringing.
local function committed(depot, except)
  local total = 0
  local item = depot.request and depot.request.item
  for id in pairs(trips_of(depot)) do
    local trip = storage.trips[id]
    -- Trips for an item the depot no longer asks for bring nothing it needs.
    if trip and id ~= except and trip.item == item then
      total = total + bringing(trip)
    end
  end
  return total
end

-- How much of an item, or fluid, a depot holds.
local function stock(entity, item, fluid)
  if fluid then
    return entity.get_fluid_count(item)
  end
  return inventory(entity).get_item_count(item_id(item))
end

-- How much of `item` a provider has that no freighter on its way there has promised to load.
local function available(provider, item)
  local count = stock(provider.entity, item, provider.fluid)
  for _, trip in pairs(storage.trips) do
    if trip.provider == provider.entity.unit_number and trip.item == item and trip.state == TO_PROVIDER then
      count = count - (trip.planned or 0)
    end
  end
  return count
end

local function request_depot(entity)
  local depot = entity and entity.valid and entity.unit_number and storage.depots[entity.unit_number]
  return depot and REQUESTING[depot.role] and depot or nil
end

-- The request of a request depot: { item = name, count = n }, or nil.
function logistics.get_request(entity)
  local depot = request_depot(entity)
  return depot and depot.request and { item = depot.request.item, count = depot.request.count }
end

-- Drop the searches under way for a requesting depot, which were for the old set or order of depots
-- to fetch from: its own, and those of its freighters being rerouted. Both start afresh at the next
-- once-a-second check.
local function restart_depot_searches(depot)
  cancel_search(depot)
  for id in pairs(trips_of(depot)) do
    local trip = storage.trips[id]
    if trip and trip.searching then
      trip.search_token, trip.searching = nil, game.tick - SEARCH_TIMEOUT
    end
  end
end

-- Whether a request depot fetches from buffer depots first, like a requester chest's "request from
-- buffer chests" (without it, buffers come after providers, for what no provider can supply). Only
-- request depots have it: buffer depots fetch from providers alone.
function logistics.get_from_buffers(entity)
  local depot = request_depot(entity)
  return depot and depot.role == "request" and depot.from_buffers == true or false
end

-- Returns false, changing nothing, for anything but a request depot.
function logistics.set_from_buffers(entity, from_buffers)
  local depot = request_depot(entity)
  if not depot or depot.role ~= "request" then
    return false
  end
  depot.from_buffers = from_buffers == true
  depot.cooldowns = {}
  depot.retry_at = 0
  restart_depot_searches(depot)
  return true
end

-- The depots with a priority: provider and buffer depots, which freighters fetch from.
local function supplying_depot(entity)
  local depot = entity and entity.valid and entity.unit_number and storage.depots[entity.unit_number]
  return depot and (depot.role == "provider" or depot.role == "buffer") and depot or nil
end

-- A provider or buffer depot's priority (1 to 10, PRIORITY_DEFAULT if never set), or nil.
function logistics.get_priority(entity)
  local depot = supplying_depot(entity)
  return depot and (depot.priority or PRIORITY_DEFAULT) or nil
end

-- What a depot holds, as circuit signal counts by key (depot_circuit.key): its items by quality,
-- or its fluids in whole units, as a container or storage tank sends them.
local function own_signals(depot)
  local counts = {}
  local entity = depot.entity
  if depot.fluid then
    for name, amount in pairs(entity.get_fluid_contents()) do
      local key = depot_circuit.key({ type = "fluid", name = name })
      counts[key] = (counts[key] or 0) + math.floor(amount)
    end
    return counts
  end
  local contents = inventory(entity)
  for _, item in ipairs(contents and contents.get_contents() or {}) do
    local key = depot_circuit.key({ type = "item", name = item.name, quality = item.quality })
    counts[key] = (counts[key] or 0) + item.count
  end
  return counts
end

-- Set by scripts/road-monitor.lua: what the road network monitors on a circuit network counted for
-- a depot (counted(unit_number, network) gives a list of counts by key), for its condition to
-- leave out.
logistics.monitor_counts = nil

-- Whether a depot takes part in deliveries now: its circuit condition holds, or isn't in effect.
local function enabled(depot)
  local counted = logistics.monitor_counts
  return depot_circuit.allows(
    depot.entity,
    depot.circuit_enabled,
    depot.circuit_condition,
    depot.circuit_mode,
    function()
      return own_signals(depot)
    end,
    counted and function(network)
      return counted(depot.entity.unit_number, network)
    end
  )
end
logistics.enabled = enabled

-- A provider, request or buffer depot (item or liquid) by its entity, or nil: the depots that have
-- a circuit condition. Fuel depots are registered too, but freighters refuel there whatever its
-- wires say, so they have none.
local function delivery_depot(entity)
  local depot = entity and entity.valid and entity.unit_number and storage.depots and storage.depots[entity.unit_number]
  return depot and depot.role ~= "fuel" and depot or nil
end

-- A delivery depot's circuit settings: { enabled, condition, mode, connected, fulfilled }, where
-- `enabled` says the condition is ticked, `mode` what it reads ("network" or "contents"),
-- `connected` that a red or green wire reaches the depot, and `fulfilled` that it takes part in
-- deliveries now. Nil for anything else.
function logistics.get_circuit(entity)
  local depot = delivery_depot(entity)
  if not depot then
    return nil
  end
  return {
    enabled = depot.circuit_enabled == true,
    condition = depot_circuit.condition(depot.circuit_condition or {}),
    mode = depot.circuit_mode or depot_circuit.network,
    connected = depot_circuit.connected(entity),
    fulfilled = enabled(depot),
  }
end

-- Set whether a delivery depot's circuit condition is in effect, and (unless nil) the condition
-- and what it reads ("network" or "contents"). Returns false, changing nothing, for anything else,
-- a condition that isn't a table or another mode.
function logistics.set_circuit(entity, enable, condition, mode)
  local depot = delivery_depot(entity)
  local stored = depot_circuit.mode(mode)
  if not depot or (condition ~= nil and type(condition) ~= "table") or stored == false then
    return false
  end
  depot.circuit_enabled = enable == true
  if condition ~= nil then
    depot.circuit_condition = depot_circuit.condition(condition)
  end
  if mode ~= nil then
    depot.circuit_mode = stored
  end
  return true
end

-- Set a request depot's request, or clear it with a nil item. Returns false, changing nothing,
-- for anything but a request depot, an item that doesn't exist, or a count that isn't a number.
function logistics.set_request(entity, item, count)
  local depot = request_depot(entity)
  if not depot then
    return false
  end
  if item == nil then
    depot.request = nil
  else
    count = tonumber(count or 0)
    -- An item for an item depot, a fluid for a liquid depot.
    local kinds = depot.fluid and prototypes.fluid or prototypes.item
    if type(item) ~= "string" or not kinds[item] or not count then
      return false
    end
    depot.request = { item = item, count = math.max(0, math.floor(count)) }
  end
  depot.cooldowns = {}
  depot.retry_at = 0
  -- A search under way was for the old request.
  cancel_search(depot)
  -- Freighters on their way out for another item will load nothing (arrived_at_provider checks
  -- the request), so their promises no longer hold that provider's stock.
  for id in pairs(trips_of(depot)) do
    local trip = storage.trips[id]
    if trip and trip.state == TO_PROVIDER and trip.item ~= (depot.request and depot.request.item) then
      trip.planned = 0
    end
  end
  return true
end

function logistics.get_status(entity)
  local depot = request_depot(entity)
  return depot and depot.status
end

-- How many of the requested item a request depot still wants, and how many of those it has room
-- for, counting what its freighters (except trip `except`) are already bringing. Requests above
-- what the depot can hold are filled as far as it can hold.
local function need(depot, except)
  local request = depot.request
  if not request or request.count <= 0 or not (depot.fluid and prototypes.fluid or prototypes.item)[request.item] then
    return 0, 0
  end
  if depot.fluid then
    local tank = depot.entity
    local coming = committed(depot, except)
    local wanted = request.count - tank.get_fluid_count(request.item) - coming
    if wanted <= 0 then
      return 0, 0
    end
    local held = 0
    for name, amount in pairs(tank.get_fluid_contents()) do
      if name ~= request.item and amount > 0 then
        -- Another fluid fills the tank: nothing can go in until it is gone.
        return wanted, 0, true
      end
      held = held + amount
    end
    return wanted, math.max(0, math.min(wanted, tank.get_fluid_capacity(1) - held - coming))
  end
  local chest, id = inventory(depot.entity), item_id(request.item)
  local coming = committed(depot, except)
  local wanted = request.count - chest.get_item_count(id) - coming
  if wanted <= 0 then
    return 0, 0
  end
  return wanted, math.max(0, math.min(wanted, chest.get_insertable_count(id) - coming))
end

-- Every depot that could serve a requesting depot: provider depots, and for a request depot,
-- buffer depots too (a buffer depot itself fetches only from providers). A request depot set to
-- request from buffer depots ranks buffers first, however near a provider is; one not set to ranks
-- them last, so it falls back to a buffer only for what no provider can supply. All on the same
-- surface and force, with road at its loading zone, holding the item and not on cooldown for this
-- request. Within each kind, the highest priority first; within each priority, nearest first in a
-- straight line from `from`. Also says whether one was skipped for cooldown.
local function candidates(depot, from)
  local entity = depot.entity
  local found, waiting = {}, false
  local buffers = depot.role == "request"
  -- The kind of depot asked about first.
  local first = buffers and depot.from_buffers and "buffer" or "provider"
  for unit_number, provider in pairs(storage.depots) do
    local candidate = provider.entity
    if
      (provider.role == "provider" or (buffers and provider.role == "buffer" and candidate ~= entity))
      -- Items from item depots, fluids from liquid depots.
      and provider.fluid == depot.fluid
      and candidate.valid
      and candidate.surface == entity.surface
      and candidate.force == entity.force
      and available(provider, depot.request.item) > 0
      and enabled(provider)
    then
      local position, on_road = loading_tile(candidate)
      if on_road then
        if (depot.cooldowns[unit_number] or 0) > game.tick then
          waiting = true
        else
          local dx, dy = position.x - from.x, position.y - from.y
          found[#found + 1] = {
            id = unit_number,
            position = position,
            distance = math.sqrt(dx * dx + dy * dy),
            -- With "request from buffer depots", buffer depots come first, nearer providers or not,
            -- whatever either's priority; without it, providers come first. Then the higher
            -- priority, nearer or not.
            rank = (provider.role == first and 0 or PRIORITY_MAX)
              + PRIORITY_MAX
              - (provider.priority or PRIORITY_DEFAULT),
          }
        end
      end
    end
  end
  table.sort(found, function(a, b)
    if a.rank ~= b.rank then
      return a.rank < b.rank
    end
    return a.distance < b.distance or (a.distance == b.distance and a.id < b.id)
  end)
  return found, waiting
end

local function drive(trip, destination)
  trip.destination = destination
  trip.loading = nil
  -- On the road now: no longer standing at home deciding whether it can go.
  trip.departing = nil
  trip.drone.commandable.set_command({
    type = defines.command.go_to_location,
    destination = destination,
    radius = ARRIVAL_RADIUS,
    distraction = defines.distraction.none,
    pathfind_flags = { no_break = true },
  })
end

-- Send one of a request depot's freighters, the one with the most fuel, to `provider` (`length`
-- tiles away by road), to load `planned` of the item. Returns whether it set off: one that can't
-- reach the provider on its fuel, with no Fuel depot to fill up at, goes back into the slot.
local function start_trip(depot, provider, from, planned, length)
  local slot = a_freighter(depot)
  if not slot then
    return false
  end
  local drone = depot.entity.surface.create_entity({
    name = DRONE,
    position = from,
    force = depot.entity.force,
  })
  if not drone then
    return false
  end
  local parked = parked_fuel(depot)
  local energy
  if #parked > 0 and (trucks_of(depot).get_item_count() <= #parked or parked[#parked] > fuel_capacity()) then
    -- The fullest parked one: more than a tank, or (with none full) the most short of one.
    energy = table.remove(parked)
  else
    -- One with a full tank.
    energy = fuel_capacity()
  end
  local trip = {
    drone = drone,
    request = depot.entity.unit_number,
    provider = provider.entity.unit_number,
    item = depot.request.item,
    cargo = not depot.fluid and game.create_inventory(CAPACITY_STACKS) or nil,
    fluid = depot.fluid and { amount = 0 } or nil,
    -- The freighter item it was, taken from the depot's slot; it goes back there afterwards.
    truck = game.create_inventory(1),
    planned = planned,
    state = TO_PROVIDER,
    -- Fuel in joules; where it stood when last burned; the road length to its provider.
    energy = energy,
    at = from,
    leg = length,
    departing = true,
    -- Where it is going, should the provider go before it sets off (see target).
    destination = (loading_tile(provider.entity)),
  }
  trip.truck[1].transfer_stack(slot, 1)
  -- on_object_destroyed reports an entity's unit_number as its useful_id, the key used here.
  storage.trips[drone.unit_number] = trip
  script.register_on_object_destroyed(drone)
  trips_of(depot)[drone.unit_number] = true
  depot.next_send = game.tick + SEND_SPACING
  if energy <= 0 and fuel_per_tile() > 0 then
    trip.dry = true
    drone.speed = prototypes.entity[DRONE].speed * DRY_SPEED
  end
  show_fuel(trip)
  set_off(drone.unit_number, trip, length)
  return storage.trips[drone.unit_number] ~= nil
end

-- Searches belong to a request depot (finding a provider to send a freighter to) or to a trip (a
-- freighter whose provider was removed). Each search has a token, and its owner keeps the token of
-- its one current search. Whatever makes a search stale (road or depot changes, a new request, a
-- busy pathfinder, a timeout) takes the owner's token away or replaces it, so the old search's
-- answers are ignored: they neither put providers on cooldown nor send freighters, and the old
-- search asks the pathfinder nothing more.
local function new_token()
  storage.search_count = (storage.search_count or 0) + 1
  return storage.search_count
end

-- The depot or trip a search belongs to, if it is still that owner's current search.
local function owner_of(search)
  if search.trip then
    local trip = storage.trips[search.trip]
    return trip and trip.search_token == search.token and trip or nil
  end
  local depot = storage.depots[search.request]
  return depot and depot.search_token == search.token and depot or nil
end

-- Ask the pathfinder for the road route from the search's start to its current candidate, as the
-- freighter would drive it.
local function ask_route(search, surface, force)
  local drone = prototypes.entity[DRONE]
  local id = surface.request_path({
    bounding_box = drone.collision_box,
    collision_mask = drone.collision_mask,
    start = search.from,
    goal = search.candidates[search.index].position,
    force = force,
    radius = ARRIVAL_RADIUS,
    pathfind_flags = { no_break = true },
  })
  -- Saves from before searches existed have no table yet, and their mod version is the same.
  storage.searches = storage.searches or {}
  storage.searches[id] = search
end

-- Start looking for the provider nearest by road. With `trip`, the search is for a freighter
-- already out (its provider was removed) and starts where it stands. Returns false, with whether
-- a provider was skipped for cooldown, if there is nothing to look for.
local function search_providers(depot, from, trip)
  local found, waiting = candidates(depot, from)
  if #found == 0 then
    return false, waiting
  end
  local search = {
    token = new_token(),
    request = depot.entity.unit_number,
    item = depot.request.item,
    from = from,
    candidates = found,
    index = 1,
    trip = trip,
  }
  local owner = trip and storage.trips[trip] or depot
  owner.search_token = search.token
  owner.searching = game.tick
  ask_route(search, depot.entity.surface, depot.entity.force)
  return true
end

-- Find a new provider, nearest by road from where it stands, for a freighter whose provider is
-- gone or no longer suitable. It waits while the search runs, and leaves if there is none.
local function reroute(id, trip)
  local depot = storage.depots[trip.request]
  local request = depot and depot.entity.valid and depot.request
  -- A Fuel depot it was heading for, or looking for, waits: set_off decides again for the new leg.
  trip.search_token, trip.searching, trip.fuel_search, trip.refuel = nil, nil, nil, nil
  if
    trip.drone.valid
    and request
    and request.item == trip.item
    and search_providers(depot, trip.drone.position, id)
  then
    trip.drone.commandable.set_command({ type = defines.command.stop, distraction = defines.distraction.none })
  elseif trip.drone.valid and depot and depot.entity.valid then
    -- No provider for it any more: home empty, to park.
    trip.planned = nil
    trip.state = TO_REQUEST
    drive(trip, (loading_tile(depot.entity)))
  else
    end_trip(id, trip)
  end
end

-- Fuel depots a freighter of `depot` could fill up at: same surface and force, road at the loading
-- zone, holding fuel, not on cooldown for this depot (no road route lately), nearest first in a
-- straight line from `from`. With `empty`, Fuel depots without fuel come too, ranked after all
-- those with fuel (rank 1): a search reaches one only when none with fuel has a road, and tells a
-- freighter at home that its road has Fuel depots, empty ones, from none at all.
local function fuel_candidates(depot, from, empty)
  local entity = depot.entity
  local found = {}
  for unit_number, fuel in pairs(storage.depots) do
    local candidate = fuel.entity
    if
      fuel.role == "fuel"
      and candidate.valid
      and candidate.surface == entity.surface
      and candidate.force == entity.force
      and (depot.cooldowns[unit_number] or 0) <= game.tick
    then
      local stocked = has_fuel(fuel)
      local position, on_road = loading_tile(candidate)
      if on_road and (stocked or empty) then
        local dx, dy = position.x - from.x, position.y - from.y
        found[#found + 1] = {
          id = unit_number,
          position = position,
          distance = math.sqrt(dx * dx + dy * dy),
          rank = stocked and 0 or 1,
        }
      end
    end
  end
  table.sort(found, function(a, b)
    if a.rank ~= b.rank then
      return a.rank < b.rank
    end
    return a.distance < b.distance or (a.distance == b.distance and a.id < b.id)
  end)
  return found
end

-- Start looking for the Fuel depot nearest by road from where a freighter stands; it waits while
-- the search runs. Returns false if there is none to look for.
local function seek_fuel(id, trip)
  trip.search_token, trip.searching, trip.fuel_search, trip.refuel = nil, nil, nil, nil
  local depot = storage.depots[trip.request]
  if not (trip.drone.valid and depot and depot.entity.valid) then
    return false
  end
  local from = trip.drone.position
  -- One still at home also looks for empty ones, so its depot can say which it is waiting for.
  local found = fuel_candidates(depot, from, trip.departing)
  if #found == 0 then
    return false
  end
  local search = {
    token = new_token(),
    request = trip.request,
    item = trip.item,
    from = from,
    candidates = found,
    index = 1,
    trip = id,
    fuel = true,
  }
  trip.search_token, trip.searching, trip.fuel_search = search.token, game.tick, true
  trip.drone.commandable.set_command({ type = defines.command.stop, distraction = defines.distraction.none })
  ask_route(search, depot.entity.surface, depot.entity.force)
  return true
end

-- Nowhere to fill up for this leg: go on where it was going on what it has. One that hasn't left
-- home yet and can't reach the provider on that stays home, never sent to wait at an empty Fuel
-- depot. Its depot waits for fuel in one if a road reaches an empty one (`empty_reachable`;
-- dispatch looks every second), and otherwise shows red, no Fuel depot connected by road, until
-- one is built or connected (or RETRY_TICKS pass).
local function go_without_fuel(id, trip, empty_reachable)
  trip.fuel_search, trip.refueled = nil, true
  if not trip.drone.valid then
    return end_trip(id, trip)
  end
  if trip.departing and trip.energy < (trip.leg or 0) * fuel_per_tile() then
    local depot = storage.depots[trip.request]
    if depot then
      local status = empty_reachable and logistics.status.no_fuel or logistics.status.no_fuel_depot
      depot.retry_at = game.tick + RETRY_TICKS
      depot.retry_status = status
      depot.status = status
    end
    return end_trip(id, trip)
  end
  drive(trip, target(trip))
end

-- Find a Fuel depot to fill up at, or go on without.
local function look_for_fuel(id, trip)
  if not seek_fuel(id, trip) then
    go_without_fuel(id, trip)
  end
end

-- Whether a freighter should fill up before a leg `length` tiles long by road: its tank holds
-- less than the leg takes (with FUEL_MARGIN) plus FUEL_RESERVE, or than a full tank if that is
-- less. Once a leg: after filling up, or finding nowhere to, it goes.
local function short_of_fuel(trip, length)
  local per_tile = fuel_per_tile()
  if trip.refueled or not length or per_tile <= 0 then
    return false
  end
  local capacity = fuel_capacity()
  return trip.energy < math.min(length * per_tile * FUEL_MARGIN + capacity * FUEL_RESERVE, capacity)
end

-- Set off on a leg of `length` tiles by road towards the trip's target, by way of a Fuel depot if
-- the tank is short for it.
function set_off(id, trip, length)
  upgrade(trip)
  trip.refueled = nil
  if short_of_fuel(trip, length) then
    return look_for_fuel(id, trip)
  end
  drive(trip, target(trip))
end

-- Drop a trip's search and start again: for fuel, or for a new provider.
local function search_again(id, trip)
  if trip.fuel_search then
    look_for_fuel(id, trip)
  else
    reroute(id, trip)
  end
end

local function path_length(from, path)
  local length, x, y = 0, from.x, from.y
  for _, waypoint in ipairs(path) do
    local position = waypoint.position
    length = length + math.sqrt((position.x - x) ^ 2 + (position.y - y) ^ 2)
    x, y = position.x, position.y
  end
  return length
end

-- Freighters put into a request depot's chest (by hand, inserters or robots) go into its slot, as
-- far as it has room, unless freighters are what it requests.
local function absorb_freighters(depot)
  if depot.request and depot.request.item == FREIGHTER then
    return
  end
  local chest = freighter_chest(depot.entity)
  if count_freighters(chest) == 0 then
    depot.chest_seen = 0
    return
  end
  local slot = trucks_of(depot)
  local out = 0
  for id in pairs(trips_of(depot)) do
    local trip = storage.trips[id]
    if trip and trip.truck and trip.truck.valid and not trip.truck.is_empty() then
      out = out + 1
    end
  end
  local room = FREIGHTER_CAPACITY - slot.get_item_count() - out
  if room > 0 then
    -- Freighters waiting in the chest for robots to take them away stay there.
    load(chest, slot, FREIGHTER, room, logistics.leaving(depot.entity), true)
  end
  -- What the chest holds now, so freighters a player puts in later can be told apart.
  depot.chest_seen = count_freighters(chest)
end

local function dispatch(depot)
  absorb_freighters(depot)
  logistics.trim_freighter_requests(depot.entity)
  if not enabled(depot) then
    -- Disabled by its circuit condition: no search, no freighter. One under way is dropped.
    cancel_search(depot)
    depot.status = logistics.status.disabled
    return
  end
  -- "On its way" only while a freighter is bringing some of the requested item: not one taking
  -- cargo back to its provider, nor one driving home empty.
  local out = committed(depot) > 0
  local wanted, room, other_fluid = need(depot)
  if wanted <= 0 then
    depot.status = out and logistics.status.delivering
      or (depot.request and logistics.status.satisfied or logistics.status.none)
    return
  end
  if room <= 0 then
    depot.status = out and logistics.status.delivering
      or (other_fluid and logistics.status.other_fluid or logistics.status.full)
    return
  end
  local from, on_road = loading_tile(depot.entity)
  if not on_road then
    depot.status = logistics.status.no_road
    return
  end
  if
    (depot.retry_at or 0) > game.tick
    and (depot.retry_status == logistics.status.no_fuel or depot.retry_status == logistics.status.no_fuel_depot)
    and #fuel_candidates(depot, from) > 0
  then
    -- Its freighters were waiting for fuel, and a Fuel depot has some now: they go at once.
    depot.retry_at = 0
  end
  if (depot.retry_at or 0) > game.tick then
    depot.status = depot.retry_status or logistics.status.no_freighter
    return
  end
  if trucks_of(depot).is_empty() then
    depot.status = out and logistics.status.delivering or logistics.status.no_trucks
    return
  end
  if (depot.next_send or 0) > game.tick then
    -- The last freighter left less than SEND_SPACING ago.
    return
  end
  if depot.searching and game.tick - depot.searching < SEARCH_TIMEOUT then
    return
  end
  local started, waiting = search_providers(depot, from)
  if started then
    depot.status = out and logistics.status.delivering or logistics.status.searching
  else
    cancel_search(depot)
    depot.status = out and logistics.status.delivering
      or (waiting and logistics.status.unreachable or logistics.status.no_provider)
  end
end

-- Burn the fuel a freighter used driving since last time: what the tiles it covered take.
local function burn(trip)
  local drone = trip.drone
  if not drone.valid then
    return
  end
  local position = drone.position
  local last = trip.at or position
  trip.at = { x = position.x, y = position.y }
  upgrade(trip)
  local per_tile = fuel_per_tile()
  local dx, dy = position.x - last.x, position.y - last.y
  trip.energy = math.max(0, trip.energy - math.sqrt(dx * dx + dy * dy) * per_tile)
  if trip.dry and per_tile <= 0 then
    -- Fuel was turned off: nothing to crawl for.
    trip.dry = nil
    drone.speed = prototypes.entity[DRONE].speed
  end
end

function logistics.on_tick()
  -- A freighter whose search never answered (or met a busy pathfinder) searches again.
  -- One driving in the wrong paint (something was stuck to it when it loaded) is painted once
  -- nothing is, and drives on from where it stands. Painting changes trip ids, so after the loop.
  local repaint_pending = {}
  for id, trip in pairs(storage.trips) do
    burn(trip)
    show_fuel(trip)
    -- Every freighter out pollutes a little, standing or driving.
    if trip.drone.valid then
      trip.drone.surface.pollute(trip.drone.position, POLLUTION_PER_SECOND * DISPATCH_INTERVAL / 60, DRONE)
    end
    if trip.searching and game.tick - trip.searching >= SEARCH_TIMEOUT then
      search_again(id, trip)
    elseif trip.drone.valid and trip.energy <= 0 and not trip.dry and fuel_per_tile() > 0 then
      -- Its tank just ran dry: it crawls, to a Fuel depot if it can find one.
      trip.dry = true
      trip.drone.speed = prototypes.entity[DRONE].speed * DRY_SPEED
      if not (trip.refuel or trip.searching or trip.loading) then
        look_for_fuel(id, trip)
      end
    elseif
      trip.drone.valid
      and trip.destination
      and not trip.searching
      and not trip.loading
      and trip.drone.name ~= paint_of(trip)
    then
      repaint_pending[#repaint_pending + 1] = id
    end
  end
  for _, id in ipairs(repaint_pending) do
    local trip = storage.trips[id]
    if trip and trip.drone.valid and repaint(id, trip) then
      show_cargo(trip)
      drive(trip, target(trip))
    end
  end
  for id, depot in pairs(storage.depots) do
    if not depot.entity.valid then
      -- Gone before on_object_destroyed reached it: a Fuel depot's tank goes too.
      if depot.tank and depot.tank.valid then
        depot.tank.destroy()
      end
      storage.depots[id] = nil
    elseif REQUESTING[depot.role] then
      dispatch(depot)
    elseif depot.role == "fuel" then
      fuel_tank(depot.entity)
    end
  end
end

-- Move up to `limit` items of `item` (normal quality) from one inventory into another, stack by
-- stack, keeping each stack's data. Returns how many moved.
-- `leave`, if given, maps `from` stack indices to how many items to leave in that stack. With
-- `any_quality`, items of every quality move (freighters do), not only normal quality (cargo).
function load(from, to, item, limit, leave, any_quality)
  local moved = 0
  for index = 1, #from do
    local stack = from[index]
    if moved >= limit then
      break
    end
    if stack.valid_for_read and stack.name == item and (any_quality or stack.quality.name == QUALITY) then
      local kept = leave and leave[index] or 0
      for slot = 1, #to do
        local into = to[slot]
        local movable = (stack.valid_for_read and stack.count or 0) - kept
        if moved >= limit or movable <= 0 then
          break
        end
        if not into.valid_for_read or into.name == item then
          local before = stack.count
          into.transfer_stack(stack, math.min(movable, limit - moved))
          moved = moved + before - (stack.valid_for_read and stack.count or 0)
        end
      end
    end
  end
  return moved
end

-- Insert all cargo into an inventory, keeping each stack's data; what doesn't fit stays aboard.
local function unload(cargo, into)
  for index = 1, #cargo do
    local stack = cargo[index]
    if stack.valid_for_read then
      local inserted = into.insert(stack)
      if inserted >= stack.count then
        stack.clear()
      elseif inserted > 0 then
        stack.count = stack.count - inserted
      end
    end
  end
end

-- Pump up to `limit` of a fluid trip's fluid out of a liquid depot's tank (its one fluid storage),
-- at the tank's temperature.
function load_fluid(entity, trip, limit)
  local held = entity.get_fluid(1)
  if limit <= 0 or not held or held.name ~= trip.item then
    return 0
  end
  local removed = entity.remove_fluid(1, limit)
  local taken = removed and removed.amount or 0
  if taken > 0 then
    local had = trip.fluid.amount
    local temperature = trip.fluid.temperature or removed.temperature
    trip.fluid.temperature = (temperature * had + removed.temperature * taken) / (had + taken)
    trip.fluid.amount = had + taken
  end
  return taken
end

-- Pump a fluid trip's fluid into a liquid depot's tank, as far as it fits; the rest stays aboard.
function unload_fluid(trip, entity)
  if trip.fluid.amount <= 0 then
    return 0
  end
  local put =
    entity.insert_fluid({ name = trip.item, amount = trip.fluid.amount, temperature = trip.fluid.temperature })
  trip.fluid.amount = trip.fluid.amount - put
  return put
end

-- Leave anything still aboard on the ground, marked for deconstruction so construction robots
-- can collect it.
local function spill(trip, position)
  if trip.fluid then
    -- Fluid can't be left on the ground: it is lost.
    trip.fluid.amount = 0
    return
  end
  if not (trip.cargo and trip.cargo.valid) then
    return
  end
  local surface, force = trip.drone.surface, trip.drone.force
  for index = 1, #trip.cargo do
    local stack = trip.cargo[index]
    if stack.valid_for_read then
      surface.spill_item_stack({
        position = position or trip.drone.position,
        stack = stack,
        enable_looted = true,
        force = force,
        allow_belts = false,
      })
      stack.clear()
    end
  end
end

-- Saves from this PR's first version carried cargo as a plain count, and the mod version didn't
-- change, so no configuration change converts them: carry such cargo as stacks from here on.
function upgrade(trip)
  -- Trips from before fuel set off with a full tank.
  trip.energy = trip.energy or fuel_capacity()
  if type(trip.cargo) == "number" then
    local count = trip.cargo
    trip.cargo = game.create_inventory(CAPACITY_STACKS)
    if count > 0 and prototypes.item[trip.item] then
      trip.cargo.insert({ name = trip.item, count = count })
    end
  end
  return trip
end

-- End a trip: its freighter leaves the map and goes back into its depot's slot as an item, unless
-- it was `lost` (destroyed on the way). If the depot is gone it has already handed its freighters
-- over; one somehow still aboard is left where the freighter stands.
function end_trip(id, trip, lost)
  storage.trips[id] = nil
  local depot = storage.depots[trip.request]
  if depot and depot.trips then
    depot.trips[id] = nil
  end
  local truck = trip.truck and trip.truck.valid and trip.truck[1]
  if truck and truck.valid_for_read and not lost then
    if depot and depot.entity.valid then
      local inserted = trucks_of(depot).insert(truck)
      if inserted >= truck.count then
        truck.clear()
      else
        truck.count = truck.count - inserted
      end
      -- It parks with what is left in its tank, more than a tank's worth too.
      if inserted > 0 and trip.energy and trip.energy ~= fuel_capacity() then
        local parked = depot.fuel or {}
        parked[#parked + 1] = trip.energy
        depot.fuel = parked
        parked_fuel(depot)
      end
    end
    if truck.valid_for_read and trip.drone.valid then
      trip.drone.surface.spill_item_stack({
        position = trip.drone.position,
        stack = truck,
        enable_looted = true,
        force = trip.drone.force,
        allow_belts = false,
      })
    end
  end
  if trip.truck and trip.truck.valid then
    trip.truck.destroy()
  end
  if trip.cargo and trip.cargo.valid then
    trip.cargo.destroy()
  end
  if trip.drone.valid then
    trip.drone.destroy()
  end
end

-- A freighter destroyed on the way (by enemies, say): it is lost, with its cargo. Its depot is
-- now one short of the freighters it had (or was being topped up to), so it asks robots for a
-- replacement; one put in by hand counts too.
local function lose(id, trip)
  local home = storage.depots[trip.request]
  local entity = home and home.entity.valid and home.entity
  local had = entity and math.max(logistics.freighter_total(entity), home.freighter_target or 0)
  end_trip(id, trip, true)
  if entity then
    logistics.match_freighters(entity, had)
  end
end

local function depot_entity(unit_number)
  local depot = storage.depots[unit_number]
  return depot and depot.entity.valid and depot.entity or nil
end

local function arrived_at_provider(id, trip, depot)
  local provider = depot_entity(trip.provider)
  local request = depot and depot.entity.valid and depot.request
  -- Load only what the request depot still asks for, and has room for: the request may have
  -- changed to another item, or been filled some other way, since the freighter set off.
  if provider and request and request.item == trip.item then
    -- What it promised, as far as the depot (counting its other freighters) still needs it.
    local _, room = need(depot, id)
    local limit = math.min(trip.planned or room, room)
    if trip.fluid then
      load_fluid(provider, trip, math.min(limit, FLUID_CAPACITY))
    else
      load(inventory(provider), trip.cargo, trip.item, limit)
    end
  end
  trip.planned = nil
  if not (depot and depot.entity.valid) then
    return end_trip(id, trip)
  end
  -- Home, loaded or (if there was nothing to load) empty, to unload and park, painted for its load:
  -- as far by road as it came (when it came from home), and never less than the straight line.
  trip.state = TO_REQUEST
  repaint(id, trip)
  show_cargo(trip)
  -- Painting moves the trip to its new freighter's unit_number.
  id = trip.drone.unit_number
  local home, here = loading_tile(depot.entity), trip.drone.position
  set_off(id, trip, math.max(trip.leg or 0, math.sqrt((home.x - here.x) ^ 2 + (home.y - here.y) ^ 2)))
end

-- Filled up at a Fuel depot (as far as it had fuel): on to where it was going.
local function arrived_at_fuel(id, trip)
  local fuel = storage.depots[trip.refuel]
  trip.refuel, trip.refueled = nil, true
  if fuel and fuel.entity.valid then
    refuel(trip, fuel)
  end
  if trip.dry and trip.energy > 0 then
    trip.dry = nil
    trip.drone.speed = prototypes.entity[DRONE].speed
  end
  show_fuel(trip)
  if storage.trips[id] then
    drive(trip, target(trip))
  end
end

local function arrived_at_request(id, trip, depot)
  local entity = depot and depot.entity.valid and depot.entity
  if trip.fluid then
    if entity then
      unload_fluid(trip, entity)
    end
    -- Fluid that didn't fit (another fluid got into the tank meanwhile, say) goes back.
    local provider = depot_entity(trip.provider)
    if trip.fluid.amount > 0 and provider then
      trip.state = RETURNING
      return drive(trip, (loading_tile(provider)))
    end
    return end_trip(id, trip)
  end
  if entity then
    unload(trip.cargo, inventory(entity))
  end
  spill(trip, entity and (loading_tile(entity)) or nil)
  end_trip(id, trip)
end

local function returned_to_provider(id, trip)
  local provider = depot_entity(trip.provider)
  if provider then
    if trip.fluid then
      unload_fluid(trip, provider)
    else
      unload(trip.cargo, inventory(provider))
    end
  end
  spill(trip, provider and (loading_tile(provider)) or nil)
  end_trip(id, trip)
end

-- The way was lost (no road route, or road removed on the way): don't try this provider again
-- for a while, and bring any cargo back to it, or leave it where the freighter stands.
local function route_failed(id, trip, depot)
  if depot then
    depot.cooldowns[trip.provider] = game.tick + RETRY_TICKS
  end
  local provider = depot_entity(trip.provider)
  if trip.state == TO_REQUEST and provider and not cargo_empty(trip) then
    trip.state = RETURNING
    return drive(trip, (loading_tile(provider)))
  end
  spill(trip)
  end_trip(id, trip)
end

-- No road route to the Fuel depot it was heading for: don't try that one again for a while, and
-- look for another, or go on without.
local function fuel_route_failed(id, trip, depot)
  if depot then
    depot.cooldowns[trip.refuel] = game.tick + RETRY_TICKS
  end
  look_for_fuel(id, trip)
end

function logistics.on_ai_command_completed(event)
  local id = event.unit_number
  local trip = storage.trips and storage.trips[id]
  -- A command replaced by a newer one (see replan) is not the end of anything, and a freighter
  -- waiting for a reroute search has nowhere to arrive.
  if not trip or event.result == defines.behavior_result.deleted or trip.searching then
    return
  end
  upgrade(trip)
  -- A freighter killed on the way (by enemies, say) fails its command as it dies, at 0 health: it
  -- is lost, with its cargo, once it is gone (on_object_destroyed), not back from a failed route.
  if not trip.drone.valid then
    return lose(id, trip)
  elseif trip.drone.health <= 0 then
    return
  end
  local depot = storage.depots[trip.request]
  if event.result ~= defines.behavior_result.success then
    if trip.refuel then
      fuel_route_failed(id, trip, depot)
    else
      route_failed(id, trip, depot)
    end
  elseif trip.refuel and not trip.loading then
    -- At the Fuel depot: it stands there LOADING_TICKS to fill up too.
    trip.loading = true
    trip.drone.commandable.set_command({
      type = defines.command.stop,
      distraction = defines.distraction.none,
      ticks_to_wait = LOADING_TICKS,
    })
  elseif trip.refuel then
    arrived_at_fuel(id, trip)
  elseif not trip.loading and not (trip.state == TO_REQUEST and cargo_empty(trip)) then
    -- Arrived to load or unload: stand there LOADING_TICKS first. The stop command's completion
    -- comes back here, and the freighter loads or unloads then. One coming home empty just parks.
    trip.loading = true
    trip.drone.commandable.set_command({
      type = defines.command.stop,
      distraction = defines.distraction.none,
      ticks_to_wait = LOADING_TICKS,
    })
  elseif trip.state == TO_PROVIDER then
    arrived_at_provider(id, trip, depot)
  elseif trip.state == TO_REQUEST then
    arrived_at_request(id, trip, depot)
  else
    returned_to_provider(id, trip)
  end
end

-- Where a trip is heading: a Fuel depot's loading zone while it goes to fill up, otherwise the
-- provider's, or the request depot's with cargo.
function target(trip)
  local fuel = trip.refuel and depot_entity(trip.refuel)
  if fuel then
    return (loading_tile(fuel))
  end
  local depot = depot_entity(trip.state == TO_REQUEST and trip.request or trip.provider)
  return depot and (loading_tile(depot)) or trip.destination
end

-- Plan a freighter's route again from where it stands. A route that no longer exists fails at
-- once (on_ai_command_completed), instead of after the freighter stands stuck for seconds.
local function replan(trip)
  -- A freighter waiting for a reroute search stays put; the search decides where it goes. One
  -- loading or unloading finishes first, then plans its next route afresh.
  if trip.drone.valid and trip.destination and not trip.searching and not trip.loading then
    drive(trip, target(trip))
  end
end

-- Forget cooldowns of the request depots on a surface: their routes may exist now.
local function retry_now(surface_index)
  for _, depot in pairs(storage.depots) do
    if REQUESTING[depot.role] and depot.entity.valid and depot.entity.surface_index == surface_index then
      depot.cooldowns = {}
      depot.retry_at = 0
    end
  end
end

-- Searches on a surface may have used roads or depots that changed since: start them again.
local function restart_searches(surface_index)
  for _, depot in pairs(storage.depots) do
    if depot.search_token and depot.entity.valid and depot.entity.surface_index == surface_index then
      cancel_search(depot)
    end
  end
  for id, trip in pairs(storage.trips) do
    if trip.search_token and trip.drone.valid and trip.drone.surface_index == surface_index then
      search_again(id, trip)
    end
  end
end

-- Set a provider or buffer depot's priority, a whole number from 1 to 10 (others are rounded and
-- clamped). Returns false, changing nothing, for anything else or a priority that isn't a number.
function logistics.set_priority(entity, priority)
  local depot = supplying_depot(entity)
  -- A number, not text that reads as one (remote callers and blueprint tags can pass anything).
  if not depot or type(priority) ~= "number" or priority ~= priority then
    return false
  end
  priority = math.max(PRIORITY_MIN, math.min(PRIORITY_MAX, math.floor(priority + 0.5)))
  if priority == (depot.priority or PRIORITY_DEFAULT) then
    return true
  end
  depot.priority = priority
  -- Searches under way on its surface ranked depots by the old priority.
  restart_searches(depot.entity.surface_index)
  return true
end

-- Road was laid (`added`) or removed or covered (`removed`) on a surface.
function logistics.on_roads_changed(surface_index, added, removed)
  if not storage.depots then
    return
  end
  restart_searches(surface_index)
  if added then
    retry_now(surface_index)
  end
  if removed then
    for _, trip in pairs(storage.trips) do
      if trip.drone.valid and trip.drone.surface_index == surface_index then
        replan(upgrade(trip))
      end
    end
  end
end

-- A depot was built, turned or flipped: routes to and from it changed.
function logistics.on_depot_changed(entity)
  if not storage.depots or not logistics.depots[entity.name] then
    return
  end
  -- A Fuel depot's port turns with it.
  fuel_tank(entity)
  retry_now(entity.surface_index)
  restart_searches(entity.surface_index)
  for _, trip in pairs(storage.trips) do
    if
      trip.provider == entity.unit_number
      or trip.request == entity.unit_number
      or trip.refuel == entity.unit_number
    then
      replan(upgrade(trip))
    end
  end
end

-- A depot was removed: trips to it go elsewhere now, rather than finding it gone on arrival.
local function depot_removed(id)
  for trip_id, trip in pairs(storage.trips) do
    upgrade(trip)
    if not trip.drone.valid then
      end_trip(trip_id, trip)
    elseif trip.request == id then
      -- Nobody to deliver to: cargo goes back to the provider, an empty freighter just leaves.
      if trip.state == TO_REQUEST and depot_entity(trip.provider) then
        -- One standing there to unload leaves at once too.
        trip.state, trip.loading = RETURNING, nil
        replan(trip)
      elseif trip.state == TO_PROVIDER or cargo_empty(trip) then
        end_trip(trip_id, trip)
      end
    elseif trip.provider == id and trip.state == RETURNING then
      -- Bringing cargo back to a provider that is gone: try the request depot again.
      if depot_entity(trip.request) then
        trip.state, trip.loading = TO_REQUEST, nil
        replan(trip)
      else
        spill(trip)
        end_trip(trip_id, trip)
      end
    elseif trip.provider == id and trip.state == TO_PROVIDER then
      reroute(trip_id, trip)
    elseif trip.refuel == id then
      -- The Fuel depot it was heading for is gone (one standing there leaves at once): another.
      trip.refuel, trip.loading = nil, nil
      look_for_fuel(trip_id, trip)
    end
  end
end

-- The search is over: send a freighter to the provider nearest by road (or redirect the freighter
-- the search was for), if the request still wants the item.
local function finish_search(depot, search, owner)
  if search.fuel then
    -- A freighter's search for a Fuel depot: fill up at the nearest by road, if it still has fuel.
    owner.search_token, owner.searching, owner.fuel_search = nil, nil, nil
    local fuel = search.best and storage.depots[search.best]
    if fuel and fuel.entity.valid and has_fuel(fuel) then
      owner.refuel = search.best
      drive(owner, (loading_tile(fuel.entity)))
    elseif search.best and search.best_rank == 0 then
      -- The one found was emptied or removed meanwhile: look again among the rest.
      look_for_fuel(search.trip, owner)
    else
      -- None with fuel has a road; one without fuel may (rank 1).
      go_without_fuel(search.trip, owner, search.best ~= nil)
    end
    return
  end
  local provider = search.best and storage.depots[search.best]
  local still = depot.request
    and depot.request.item == search.item
    and provider
    and provider.entity.valid
    and available(provider, search.item) > 0
    and enabled(provider)
  if search.trip then
    if still then
      owner.search_token, owner.searching = nil, nil
      -- Promise only what the new provider has unpromised (this trip's old promise was at the
      -- removed provider, so `available` doesn't count it).
      owner.planned = math.min(owner.planned or 0, available(provider, search.item))
      owner.provider = search.best
      owner.leg = search.best_length
      set_off(search.trip, owner, search.best_length)
    else
      -- The provider found was emptied or removed meanwhile: look again among the rest.
      reroute(search.trip, owner)
    end
    return
  end
  cancel_search(depot)
  if not enabled(depot) then
    return
  end
  if not search.best then
    -- No provider with the item has a road route: each is on cooldown now.
    depot.status = logistics.status.unreachable
    return
  end
  local from, on_road = loading_tile(depot.entity)
  local _, room = need(depot)
  if not still or not on_road or room <= 0 then
    -- Something changed while searching; the next dispatch looks again.
    return
  end
  -- This freighter promises to load what the depot still needs, as far as the provider has it
  -- unpromised and it can carry; the next freighter covers the rest, from here or elsewhere.
  local capacity = depot.fluid and FLUID_CAPACITY or CAPACITY_STACKS * prototypes.item[search.item].stack_size
  local planned = math.min(room, available(provider, search.item), capacity)
  depot.retry_status = nil
  if start_trip(depot, provider, from, planned, search.best_length) then
    depot.status = logistics.status.delivering
  elseif (depot.retry_at or 0) <= game.tick then
    -- (A freighter that stayed home for want of fuel has set the wait and status already.)
    depot.retry_at = game.tick + RETRY_TICKS
    depot.status = logistics.status.no_freighter
  end
end

function logistics.on_script_path_request_finished(event)
  local search = storage.searches and storage.searches[event.id]
  if not search then
    return
  end
  storage.searches[event.id] = nil
  local owner = owner_of(search)
  local depot = storage.depots[search.request]
  if not (owner and depot and depot.entity.valid) then
    return
  end
  if event.try_again_later then
    -- The pathfinder is busy: this search ends, and a new one starts at the next dispatch (or, for
    -- a freighter, the next once-a-second check), so a busy pathfinder is asked at most once a
    -- second per owner.
    if search.trip then
      owner.search_token, owner.searching = nil, game.tick - SEARCH_TIMEOUT
    else
      cancel_search(depot)
    end
    return
  end
  local candidate = search.candidates[search.index]
  if event.path then
    local length = path_length(search.from, event.path)
    if length < (search.best_length or math.huge) then
      search.best, search.best_length, search.best_rank = candidate.id, length, candidate.rank
    end
  else
    depot.cooldowns[candidate.id] = game.tick + RETRY_TICKS
  end
  -- A road is never shorter than the straight line, so stop at the first candidate that is
  -- already farther away in a straight line than the best road found. Candidates come in ranks
  -- (buffer depots before providers for a request depot that requests from buffers, after them for
  -- one that doesn't; then by priority): once one of a rank has a road, the next rank isn't asked
  -- at all.
  search.index = search.index + 1
  local next_candidate = search.candidates[search.index]
  if
    next_candidate
    and (not search.best or (next_candidate.rank == search.best_rank and next_candidate.distance < search.best_length))
  then
    return ask_route(search, depot.entity.surface, depot.entity.force)
  end
  finish_search(depot, search, owner)
end

-- Hand over every freighter a request depot holds, in its slot and out on trips: into `buffer`
-- (what a player or robot receives for mining it), or, without one or past its room, onto the
-- ground where the depot stood. Freighters out finish their trips, then just leave.
local function refund(depot, buffer, chest)
  local stacks = {}
  if depot.trucks and depot.trucks.valid then
    for index = 1, #depot.trucks do
      stacks[#stacks + 1] = depot.trucks[index]
    end
  end
  -- Freighters still in the chest of a depot about to be destroyed (its slot may be full).
  if chest then
    for index = 1, #chest do
      local stack = chest[index]
      if stack.valid_for_read and stack.name == FREIGHTER then
        stacks[#stacks + 1] = stack
      end
    end
  end
  for id in pairs(trips_of(depot)) do
    local trip = storage.trips[id]
    if trip and trip.truck and trip.truck.valid then
      stacks[#stacks + 1] = trip.truck[1]
    end
  end
  local surface = game.surfaces[depot.surface_index or (depot.entity.valid and depot.entity.surface_index)]
  for _, stack in ipairs(stacks) do
    if stack.valid_for_read and buffer then
      local inserted = buffer.insert(stack)
      if inserted >= stack.count then
        stack.clear()
      else
        stack.count = stack.count - inserted
      end
    end
    if stack.valid_for_read and surface then
      surface.spill_item_stack({
        position = depot.position or depot.entity.position,
        stack = stack,
        enable_looted = true,
        allow_belts = false,
      })
    end
    stack.clear()
  end
end

-- A request depot about to be destroyed (died, or a script raising script_raised_destroy): all its
-- freighters, in the slot, out on trips and still in its chest, are left where it stands.
function logistics.on_depot_destroyed(event)
  local depot = request_depot(event.entity)
  if depot then
    refund(depot, nil, freighter_chest(event.entity))
  end
end

-- A request depot mined by a player, robot or platform: its freighters go with it, and for a
-- liquid depot those waiting in its truck chest too (an item depot's chest is mined with it).
function logistics.on_depot_mined(event)
  local depot = request_depot(event.entity)
  if depot then
    refund(depot, event.buffer, depot.fluid and freighter_chest(event.entity) or nil)
  end
end

function logistics.on_object_destroyed(event)
  -- For entities, useful_id is the unit_number: the key of storage.depots and storage.trips.
  local id = event.useful_id
  if event.type ~= defines.target_type.entity or not id or not storage.depots then
    return
  end
  local depot = storage.depots[id]
  if depot then
    if REQUESTING[depot.role] then
      -- Destroyed rather than mined (or by a script): its freighters are left where it stood.
      refund(depot, nil, depot.chest and depot.chest.valid and inventory(depot.chest) or nil)
      if depot.trucks and depot.trucks.valid then
        depot.trucks.destroy()
      end
    end
    if depot.chest and depot.chest.valid then
      depot.chest.destroy()
    end
    if depot.tank and depot.tank.valid then
      depot.tank.destroy()
    end
    storage.depots[id] = nil
    depot_removed(id)
  elseif storage.trips[id] then
    lose(id, upgrade(storage.trips[id]))
  end
end

-- Moving freighters run over the enemy units they drive through, as trains do: each takes
-- IMPACT_DAMAGE as impact damage, at most once a second from the same freighter. The search
-- covers the ground the freighter crossed since the last look, so a fast one misses nothing in
-- between. A standing freighter (loading, or waiting for a route) hits nothing, players and other
-- freighters are never hit, and nothing makes the freighter stop or turn: it drives on.
function logistics.on_impact_tick()
  local enemies = {}
  local reach = prototypes.entity[DRONE].collision_box.right_bottom.x
  for _, trip in pairs(storage.trips) do
    local drone = trip.drone
    if drone.valid then
      local here, last = drone.position, trip.last_position
      local moved = last and (here.x ~= last.x or here.y ~= last.y)
      local area = moved
        and {
          { math.min(here.x, last.x) - reach, math.min(here.y, last.y) - reach },
          { math.max(here.x, last.x) + reach, math.max(here.y, last.y) + reach },
        }
      trip.last_position = here
      local force = drone.force
      if not enemies[force.name] then
        local list = {}
        for _, other in pairs(game.forces) do
          if force.is_enemy(other) then
            list[#list + 1] = other
          end
        end
        enemies[force.name] = list
      end
      -- Enemies hit in the last second, by unit_number, aren't hit again yet.
      local hits = trip.hits
      if hits then
        for unit_number, tick in pairs(hits) do
          if game.tick - tick >= IMPACT_COOLDOWN then
            hits[unit_number] = nil
          end
        end
      end
      if area and #enemies[force.name] > 0 then
        for _, enemy in
          pairs(drone.surface.find_entities_filtered({
            area = area,
            type = IMPACT_TYPES,
            force = enemies[force.name],
          }))
        do
          -- Damage sets off other mods' handlers there and then, and they can remove the freighter
          -- or an enemy further down this list: check both are still there before reading either.
          if drone.valid and enemy.valid and not paint.is_drone(enemy.name) then
            local key = enemy.unit_number
            if not (key and hits and hits[key]) then
              if key then
                hits = hits or {}
                hits[key] = game.tick
              end
              enemy.damage(IMPACT_DAMAGE, force, "impact", drone, drone)
            end
          end
        end
      end
      trip.hits = hits and next(hits) and hits or nil
    end
  end
end

-- Copy one depot's settings onto another (Copy and Paste settings, and clones): any delivery
-- depot's circuit condition, a request depot's request, and a provider or buffer depot's priority.
local function copy_request(source, destination)
  local from = delivery_depot(source)
  if from and delivery_depot(destination) then
    logistics.set_circuit(
      destination,
      from.circuit_enabled,
      from.circuit_condition or {},
      from.circuit_mode or depot_circuit.network
    )
  end
  -- Items and fluids don't mix: nothing else is copied between an item depot and a liquid depot.
  if (LIQUID[source.name] or false) ~= (LIQUID[destination.name] or false) then
    return
  end
  if request_depot(source) and request_depot(destination) then
    local request = logistics.get_request(source)
    logistics.set_request(destination, request and request.item, request and request.count)
    logistics.set_from_buffers(destination, logistics.get_from_buffers(source))
  end
  if supplying_depot(source) and supplying_depot(destination) then
    logistics.set_priority(destination, logistics.get_priority(source))
  end
end

-- Copy and Paste settings: the request, and the freighters. The destination asks robots for as
-- many more freighters as it takes to match the source's (in its slot, out and coming); a player
-- can fill them in by hand instead.
function logistics.on_entity_settings_pasted(event)
  copy_request(event.source, event.destination)
  if
    request_depot(event.source)
    and request_depot(event.destination)
    and (LIQUID[event.source.name] or false) == (LIQUID[event.destination.name] or false)
  then
    -- All the source has or will have: slot, out, chest (not leaving) and coming.
    logistics.match_freighters(event.destination, logistics.freighter_total(event.source))
  end
end

-- A cloned depot is a new depot with the original's request; a cloned freighter has no trip.
-- Whether a cloned Fuel depot tank belongs to a Fuel depot cloned with it: one that owns it
-- already, or one standing on it whose own clone event hasn't come yet (fuel_tank adopts it then).
local function cloned_tank_kept(tank)
  if tank_owner(tank) then
    return true
  end
  local here = tank.position
  for _, entity in pairs(tank.surface.find_entities_filtered({ name = FUEL, position = here, radius = 0.1 })) do
    local depot = storage.depots[entity.unit_number]
    if entity.position.x == here.x and entity.position.y == here.y then
      return not depot or fuel_tank(entity) == tank
    end
  end
  return false
end

function logistics.on_cloned(source, destination)
  -- A Fuel depot's tank cloned with its depot stays, with its fluid (the depot adopts it); one cloned
  -- without its depot goes, as do cloned freighters and truck chests: the cloned depot makes its own.
  if destination.name == FUEL_TANK then
    if not cloned_tank_kept(destination) then
      destination.destroy()
    end
    return
  end
  if paint.is_drone(destination.name) or destination.name == TRUCK_CHEST then
    destination.destroy()
    return
  end
  logistics.add(destination)
  if destination.name == FUEL then
    -- Cloned without its tank, it has a new, empty one: it takes the original tank's fluid.
    local tank = fuel_tank(destination)
    local from = storage.depots[source.unit_number]
    local held = from and from.tank and from.tank.valid and from.tank.get_fluid(1)
    if tank and held and not tank.get_fluid(1) then
      tank.set_fluid(1, held)
    end
  end
  copy_request(source, destination)
end

-- Find every provider and request depot already in the game (new saves and updated ones), and
-- make trips, freighters and requests agree with the game as loaded.
function logistics.add_all()
  init_storage()
  local names = {}
  for name in pairs(logistics.depots) do
    names[#names + 1] = name
  end
  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered({ name = names })) do
      logistics.add(entity)
    end
  end
  -- Searches still waiting for the pathfinder start again from scratch.
  storage.searches = {}
  for id, depot in pairs(storage.depots) do
    cancel_search(depot)
    if not depot.entity.valid then
      storage.depots[id] = nil
    else
      -- Saves from before liquid depots delivered: liquid depots learn their kind.
      depot.fluid = LIQUID[depot.entity.name] or nil
      if depot.request and not (depot.fluid and prototypes.fluid or prototypes.item)[depot.request.item] then
        -- The requested item's or fluid's mod was removed.
        depot.request = nil
      end
      if depot.circuit_condition then
        -- Signals whose mod was removed leave the condition (the game can't read them).
        depot.circuit_condition = depot_circuit.condition(depot.circuit_condition)
      end
      depot.circuit_mode = depot_circuit.mode(depot.circuit_mode) or nil
      if depot.fluid and REQUESTING[depot.role] then
        truck_chest(depot.entity)
      end
    end
  end
  for id, trip in pairs(storage.trips) do
    upgrade(trip)
    -- Trips whose freighter, cargo or item is gone end; the engine already removed any cargo of
    -- a removed item from the cargo inventory.
    local kept
    if trip.fluid then
      kept = trip.drone.valid and prototypes.fluid[trip.item]
    else
      kept = trip.drone.valid and trip.cargo.valid and prototypes.item[trip.item]
    end
    if not kept then
      if trip.drone.valid and (trip.fluid or trip.cargo.valid) then
        spill(trip)
      end
      end_trip(id, trip)
    end
  end
  for _, surface in pairs(game.surfaces) do
    for _, drone in pairs(surface.find_entities_filtered({ name = logistics.drones })) do
      if not storage.trips[drone.unit_number] then
        drone.destroy()
      end
    end
  end
  for id, trip in pairs(storage.trips) do
    if trip.searching then
      search_again(id, trip)
    end
  end
  for _, depot in pairs(storage.depots) do
    if REQUESTING[depot.role] then
      for id in pairs(trips_of(depot)) do
        if not storage.trips[id] then
          depot.trips[id] = nil
        end
      end
      depot.position = depot.position or (depot.entity.valid and depot.entity.position)
      depot.surface_index = depot.surface_index or (depot.entity.valid and depot.entity.surface_index)
    end
  end
end

-- A request depot's freighters: how many are in its slot, how many are out on trips, and the most
-- it can hold in all (FREIGHTER_CAPACITY). Nil for anything but a request depot.
function logistics.freighter_counts(entity)
  local depot = request_depot(entity)
  if not depot then
    return nil
  end
  local out = 0
  for id in pairs(trips_of(depot)) do
    local trip = storage.trips[id]
    if trip and trip.truck and trip.truck.valid and not trip.truck.is_empty() then
      out = out + 1
    end
  end
  return trucks_of(depot).get_item_count(), out, FREIGHTER_CAPACITY
end

-- Freighters can also be requested, like modules or fuel: an item request proxy asks construction
-- robots to deliver them into the depot's chest, from where they move into the slot. This is how a
-- player in remote view (or anywhere without freighters in hand) stocks a depot.
local PROXY = "item-request-proxy"

local function item_name(id)
  return type(id) == "string" and id or id.name
end

-- The item request proxies targeting a request depot; how many freighters they still ask robots to
-- bring, and to take away; and the chest stacks (0-based) freighters are to be taken from.
function freighter_requests(entity)
  local proxies, requested, removing, marked = {}, 0, 0, {}
  -- A liquid depot's requests are on its truck chest.
  entity = truck_chest(entity)
  local x, y = entity.position.x, entity.position.y
  for _, proxy in
    pairs(entity.surface.find_entities_filtered({
      name = PROXY,
      area = { { x - 0.5, y - 0.5 }, { x + 0.5, y + 0.5 } },
    }))
  do
    if proxy.proxy_target == entity then
      proxies[#proxies + 1] = proxy
      for _, request in pairs(proxy.item_requests) do
        if item_name(request.name) == FREIGHTER then
          requested = requested + request.count
        end
      end
      for _, plan in pairs(proxy.removal_plan) do
        if item_name(plan.id.name) == FREIGHTER then
          for _, position in pairs(plan.items.in_inventory or {}) do
            removing = removing + (position.count or 1)
            marked[position.stack] = (marked[position.stack] or 0) + (position.count or 1)
          end
        end
      end
    end
  end
  return proxies, requested, removing, marked
end

-- How many freighters a request depot has asked robots to bring, and to take away.
function logistics.requested_freighters(entity)
  if not request_depot(entity) then
    return 0, 0
  end
  local _, requested, removing = freighter_requests(entity)
  return requested, removing
end

-- Chest stacks (0-based) that are empty and in no request's plan, as a list.
local function free_chest_stacks(chest, proxies)
  local taken = {}
  for _, proxy in ipairs(proxies) do
    for _, plans in ipairs({ proxy.insert_plan, proxy.removal_plan }) do
      for _, plan in pairs(plans) do
        for _, position in pairs(plan.items.in_inventory or {}) do
          taken[position.stack] = true
        end
      end
    end
  end
  local free = {}
  for index = 1, #chest do
    if not chest[index].valid_for_read and not taken[index - 1] then
      free[#free + 1] = index - 1
    end
  end
  return free
end

-- Positions for `amount` freighters, a stack at a time, in the given chest stacks (0-based); the
-- amount that fits, and the positions.
local function spread(amount, stacks)
  local stack_size = prototypes.item[FREIGHTER].stack_size
  local positions, placed = {}, 0
  for _, stack in ipairs(stacks) do
    if placed >= amount then
      break
    end
    local count = math.min(stack_size, amount - placed)
    positions[#positions + 1] = { inventory = defines.inventory.chest, stack = stack, count = count }
    placed = placed + count
  end
  return placed, positions
end

-- Add an insert or removal plan to a depot's request proxy, making one if it has none.
local function add_plan(entity, proxies, plan, removal)
  entity = truck_chest(entity)
  local proxy = proxies[1]
  if proxy then
    local plans = removal and proxy.removal_plan or proxy.insert_plan
    plans[#plans + 1] = plan
    if removal then
      proxy.removal_plan = plans
    else
      proxy.insert_plan = plans
    end
  else
    entity.surface.create_entity({
      name = PROXY,
      position = entity.position,
      force = entity.force,
      target = entity,
      modules = removal and {} or { plan },
      removal_plan = removal and { plan } or nil,
    })
  end
end

-- Ask construction robots to bring freighters into a request depot's chest until it has `goal`
-- (within its slot's limit), counting freighters in its slot, out, in its chest (except those
-- waiting to be taken away) and already requested. `goal` becomes the depot's target, what the
-- requests are for: freighters arriving some other way (put in by hand) count towards it, and
-- requests beyond it are cancelled. It is kept even when the chest has no free stacks for some or
-- all of them yet (it also holds the depot's cargo): trim_freighter_requests asks for the rest as
-- stacks free up. Returns how many were requested now.
local function request_up_to(entity, goal)
  local in_slot, out, capacity = logistics.freighter_counts(entity)
  if not in_slot then
    return 0
  end
  local chest = freighter_chest(entity)
  local proxies, requested, removing = freighter_requests(entity)
  local have = in_slot + out + count_freighters(chest) - removing + requested
  goal = math.min(goal, capacity)
  if goal <= have then
    return 0
  end
  request_depot(entity).freighter_target = goal
  -- A stack at a time, into chest stacks that are empty and in no other plan.
  local amount, positions = spread(goal - have, free_chest_stacks(chest, proxies))
  if amount <= 0 then
    return 0
  end
  add_plan(entity, proxies, {
    id = { name = FREIGHTER, quality = QUALITY },
    items = { in_inventory = positions },
  })
  return amount
end

-- Ask construction robots to bring `count` more freighters (or as many as the slot has room for)
-- into a request depot's chest: more than it has and has already asked for, including freighters
-- still waiting for a free chest stack (its target). Returns how many were requested now.
function logistics.request_freighters(entity, count)
  local depot = request_depot(entity)
  if not depot then
    return 0
  end
  local have, capacity = logistics.freighter_total(entity)
  local asked = math.max(have, depot.freighter_target or 0)
  local room = capacity - asked
  local amount = math.min(math.floor(tonumber(count) or room), room)
  if amount <= 0 then
    return 0
  end
  return request_up_to(entity, asked + amount)
end

-- Have construction robots take `count` freighters (or all) out of a request depot's slot, as
-- from remote view: they move into an empty chest stack marked for removal, and robots carry them
-- to storage. Returns how many were marked.
function logistics.remove_freighters(entity, count)
  local depot = request_depot(entity)
  if not depot then
    return 0
  end
  -- Taking freighters away on purpose: no longer top the depot up to an earlier target.
  depot.freighter_target = nil
  local slot = trucks_of(depot)
  local wanted = math.min(math.floor(tonumber(count) or slot.get_item_count()), slot.get_item_count())
  if wanted <= 0 then
    return 0
  end
  local chest = freighter_chest(entity)
  local proxies = freighter_requests(entity)
  -- A stack at a time from the slot into empty chest stacks, each marked for removal.
  local positions, moved = {}, 0
  for _, index in ipairs(free_chest_stacks(chest, proxies)) do
    local from = a_freighter(depot)
    if moved >= wanted or not from then
      break
    end
    local into = chest[index + 1]
    into.transfer_stack(from, math.min(from.count, wanted - moved))
    if into.valid_for_read then
      positions[#positions + 1] = { inventory = defines.inventory.chest, stack = index, count = into.count }
      moved = moved + into.count
    end
  end
  if moved > 0 then
    add_plan(
      entity,
      proxies,
      { id = { name = FREIGHTER, quality = QUALITY }, items = { in_inventory = positions } },
      true
    )
  end
  -- The freighters leaving take their fuel entries, as in take_freighters.
  parked_fuel(depot)
  return moved
end

-- Cancel the robots' removal of a request depot's freighters; they go back into its slot at the
-- next dispatch. Returns how many were waiting to be taken.
-- Freighters a request depot has or will have: in its slot, out on trips, in its chest (except
-- those being taken away) and coming. Also the slot's limit and how many are coming.
local function freighter_total(entity)
  local in_slot, out, capacity = logistics.freighter_counts(entity)
  local _, coming, removing = freighter_requests(entity)
  local in_chest = count_freighters(freighter_chest(entity)) - removing
  return in_slot + out + in_chest + coming, capacity, coming
end
logistics.freighter_total = freighter_total

-- Ask robots for as many freighters as it takes for a request depot to have `total` (within its
-- slot's limit). Returns how many were requested.
function logistics.match_freighters(entity, total)
  local depot = request_depot(entity)
  if not depot then
    return 0
  end
  total = math.max(0, math.floor(tonumber(total) or 0))
  local have = freighter_total(entity)
  if total > have then
    return request_up_to(entity, total)
  end
  -- Already as many or more: freighter requests beyond `total` are cancelled. Freighters already
  -- in the depot stay; they are the player's, and taking them away is the player's call.
  depot.freighter_target = total
  logistics.trim_freighter_requests(entity)
  return 0
end

-- Lower a depot's freighter requests by `excess`, editing its request proxies' plans in place,
-- from the last position back, rather than replacing them. An open container window keeps showing
-- the requests of the proxy it opened with: replacing the proxy (cancel, then request anew) left
-- the chest slot's ghost hidden until the window was reopened.
local function reduce_freighter_requests(entity, excess)
  local proxies = freighter_requests(entity)
  for index = #proxies, 1, -1 do
    if excess <= 0 then
      break
    end
    local proxy = proxies[index]
    local plans = proxy.insert_plan
    for plan_index = #plans, 1, -1 do
      local plan = plans[plan_index]
      if excess > 0 and item_name(plan.id.name) == FREIGHTER then
        local positions = plan.items.in_inventory or {}
        for position_index = #positions, 1, -1 do
          if excess <= 0 then
            break
          end
          local count = positions[position_index].count or 1
          local cut = math.min(count, excess)
          excess = excess - cut
          if cut >= count then
            table.remove(positions, position_index)
          else
            positions[position_index].count = count - cut
          end
        end
        if #positions == 0 then
          table.remove(plans, plan_index)
        else
          plan.items.in_inventory = positions
        end
      end
    end
    if #plans == 0 and #proxy.removal_plan == 0 then
      proxy.destroy()
    else
      proxy.insert_plan = plans
    end
  end
end

-- Keep a request depot's freighter requests to what they are for (`depot.freighter_target`: the
-- total the depot should end up with), until it has them:
-- * beyond the target (freighters arrived some other way, put in by hand, say): the excess
--   requests are cancelled, so robots never bring more, nor overfill the slot;
-- * short of it with nothing requested to cover it: the shortfall is requested again. Factorio
--   drops an item request a player fills by hand even when they only put in part of it; the
--   target is what remembers the rest;
-- * once the depot has them all: the target is forgotten.
-- Without a target, requests are only kept within the slot's limit. Runs with every dispatch and
-- whenever freighters are put in by hand.
function logistics.trim_freighter_requests(entity)
  local depot = request_depot(entity)
  local total, capacity, coming = freighter_total(entity)
  if not depot.freighter_target and coming > 0 then
    -- Freighters requested without a target: Factorio's own request from a blueprint ghost (a
    -- player building over a ghost doesn't pass its tags on), or one set by another mod. What the
    -- depot has and is asking for is what it should end up with.
    depot.freighter_target = total
  end
  local wanted = depot.freighter_target and math.min(depot.freighter_target, capacity)
  if not wanted then
    return
  end
  if total - coming >= wanted then
    -- All there, without the requests: they are done.
    if coming > 0 then
      logistics.cancel_freighter_requests(entity)
    end
    depot.freighter_target = nil
  elseif total > wanted then
    -- More coming than still needed: lower the requests by the excess, in place.
    reduce_freighter_requests(entity, total - wanted)
  elseif total < wanted then
    -- Short, with nothing requested to cover it: ask again for the rest.
    request_up_to(entity, wanted)
  end
end

-- Blueprints (and copy and paste) of request depots keep their request, as a tag, and their
-- freighters (in the slot, out and coming), as an insert plan into the chest: the ghost asks for
-- them, robots or a player bring them, and they move into the slot.
local REQUEST_TAG = "jatz_request"
local FREIGHTERS_TAG = "jatz_freighters"
local FROM_BUFFERS_TAG = "jatz_from_buffers"
local PRIORITY_TAG = "jatz_priority"
-- { enabled = true or nil, condition = CircuitCondition, mode = "contents" or nil }, when any is set.
local CIRCUIT_TAG = "jatz_circuit"
logistics.request_tag = REQUEST_TAG

-- A delivery depot's circuit settings as a blueprint tag, or nil if it has none.
local function circuit_tag(depot)
  local condition = depot.circuit_condition
  if not depot.circuit_enabled and not (condition and condition.first_signal) and not depot.circuit_mode then
    return nil
  end
  -- Always with a condition, so a ticked checkbox without one yet is kept too.
  return {
    enabled = depot.circuit_enabled or nil,
    condition = depot_circuit.condition(condition or {}),
    mode = depot.circuit_mode,
  }
end

function logistics.setup_blueprint(blueprint, mapping)
  local entities = blueprint and mapping and blueprint.get_blueprint_entities()
  if not entities then
    return 0
  end
  local changed = 0
  for _, planned in pairs(entities) do
    local entity = mapping[planned.entity_number]
    local depot = entity and entity.valid and request_depot(entity)
    local supplying = entity and entity.valid and supplying_depot(entity)
    if supplying and not depot then
      -- A provider depot: its priority, unless it's the one every new depot has.
      planned.tags = planned.tags or {}
      planned.tags[PRIORITY_TAG] = supplying.priority ~= PRIORITY_DEFAULT and supplying.priority or nil
      planned.tags[CIRCUIT_TAG] = circuit_tag(supplying)
      if next(planned.tags) == nil then
        planned.tags = nil
      end
      changed = changed + 1
    end
    if depot then
      -- The depot's settings as they are now, replacing any from setting this blueprint up
      -- before; other tags and other items' insert plans are kept.
      planned.tags = planned.tags or {}
      planned.tags[PRIORITY_TAG] = supplying and supplying.priority ~= PRIORITY_DEFAULT and supplying.priority or nil
      planned.tags[REQUEST_TAG] = depot.request and { item = depot.request.item, count = depot.request.count } or nil
      -- Its own tag, so it's kept even with no item requested.
      planned.tags[FROM_BUFFERS_TAG] = depot.from_buffers or nil
      local freighters = freighter_total(entity)
      planned.tags[FREIGHTERS_TAG] = freighters > 0 and freighters or nil
      planned.tags[CIRCUIT_TAG] = circuit_tag(depot)
      if next(planned.tags) == nil then
        planned.tags = nil
      end
      local items, used = {}, {}
      for _, plan in pairs(planned.items or {}) do
        if item_name(plan.id.name) ~= FREIGHTER then
          items[#items + 1] = plan
          for _, position in pairs(plan.items.in_inventory or {}) do
            if position.inventory == defines.inventory.chest then
              used[position.stack] = true
            end
          end
        end
      end
      if freighters > 0 and not depot.fluid then
        -- Chest stacks the other plans don't use, a stack of freighters at a time. (A liquid
        -- depot has no chest: its freighters are asked for when it is built, see apply_tags.)
        local stacks = {}
        for index = 0, #inventory(entity) - 1 do
          if not used[index] then
            stacks[#stacks + 1] = index
          end
        end
        local _, positions = spread(freighters, stacks)
        items[#items + 1] = { id = { name = FREIGHTER, quality = QUALITY }, items = { in_inventory = positions } }
      end
      planned.items = #items > 0 and items or nil
      changed = changed + 1
    end
  end
  if changed > 0 then
    blueprint.set_blueprint_entities(entities)
  end
  return changed
end

-- The blueprint being set up: a library record, the stack the event names, the one being set up,
-- or the cursor (copy and paste), whichever holds the blueprint's entities.
local function blueprint_of(candidate)
  if not (candidate and candidate.valid) then
    return nil
  end
  if candidate.object_name == "LuaItemStack" then
    if not (candidate.valid_for_read and candidate.is_blueprint) then
      return nil
    end
  elseif candidate.type ~= "blueprint" then
    return nil
  end
  local entities = candidate.get_blueprint_entities()
  return entities and #entities > 0 and candidate or nil
end

function logistics.on_player_setup_blueprint(event)
  local player = game.get_player(event.player_index)
  local mapping = event.mapping and event.mapping.valid and event.mapping.get()
  if not (player and mapping) then
    return
  end
  -- Any of these may be nil, so not ipairs (it stops at the first nil).
  local sources = { event.record, event.stack, player.blueprint_to_setup, player.cursor_stack }
  for index = 1, 4 do
    local blueprint = blueprint_of(sources[index])
    if blueprint then
      return logistics.setup_blueprint(blueprint, mapping)
    end
  end
end

-- A depot built from a blueprint ghost takes its settings from the ghost's tags: any delivery
-- depot its circuit condition, a provider or buffer depot its priority, a request or buffer depot
-- its request (its freighters arrive through the ghost's insert plan).
function logistics.apply_tags(entity, tags)
  if not tags then
    return
  end
  -- Tags can come from anywhere (other mods, edited blueprint strings): use them only if well formed.
  if type(tags[PRIORITY_TAG]) == "number" then
    logistics.set_priority(entity, tags[PRIORITY_TAG])
  end
  local circuit = tags[CIRCUIT_TAG]
  if type(circuit) == "table" and type(circuit.condition) == "table" then
    logistics.set_circuit(
      entity,
      circuit.enabled == true,
      circuit.condition,
      depot_circuit.mode(circuit.mode) or depot_circuit.network
    )
  end
  local depot = request_depot(entity)
  if not depot then
    return
  end
  local request = tags[REQUEST_TAG]
  if type(request) == "table" and type(request.item) == "string" and type(request.count) == "number" then
    logistics.set_request(entity, request.item, request.count)
  end
  if type(tags[FROM_BUFFERS_TAG]) == "boolean" then
    logistics.set_from_buffers(entity, tags[FROM_BUFFERS_TAG])
  end
  local freighters = tags[FREIGHTERS_TAG]
  if type(freighters) == "number" and freighters >= 0 then
    if depot.fluid then
      -- A liquid depot's ghost can't carry an insert plan (a storage tank has no chest): ask
      -- robots for its freighters now, into its truck chest.
      logistics.match_freighters(entity, freighters)
    else
      -- The ghost's insert plan asks robots for the freighters; this is how many it is for.
      depot.freighter_target = math.floor(freighters)
    end
  end
end

function logistics.cancel_freighter_removal(entity)
  if not request_depot(entity) then
    return 0
  end
  local proxies, _, removing = freighter_requests(entity)
  for _, proxy in ipairs(proxies) do
    local kept = {}
    for _, plan in pairs(proxy.removal_plan) do
      if item_name(plan.id.name) ~= FREIGHTER then
        kept[#kept + 1] = plan
      end
    end
    if #kept == 0 and #proxy.insert_plan == 0 then
      proxy.destroy()
    else
      proxy.removal_plan = kept
    end
  end
  return removing
end

-- Cancel a request depot's freighter requests (other requests on it stay). Returns how many.
function logistics.cancel_freighter_requests(entity)
  local depot = request_depot(entity)
  if not depot then
    return 0
  end
  depot.freighter_target = nil
  local proxies, requested = freighter_requests(entity)
  for _, proxy in ipairs(proxies) do
    local kept = {}
    for _, plan in pairs(proxy.insert_plan) do
      if item_name(plan.id.name) ~= FREIGHTER then
        kept[#kept + 1] = plan
      end
    end
    if #kept == 0 and #proxy.removal_plan == 0 then
      proxy.destroy()
    else
      proxy.insert_plan = kept
    end
  end
  return requested
end

-- Chest stacks (1-based) with freighters waiting for robots to take them away, and how many of
-- each stack's freighters are waiting: those stay; any more merged into the stack don't.
function logistics.leaving(entity)
  local _, _, _, marked = freighter_requests(entity)
  local leave = {}
  for stack, count in pairs(marked) do
    leave[stack + 1] = count
  end
  return leave
end

-- Freighters a player has just put into a request depot's chest (ctrl+click or shift+click in its
-- window, ctrl+click on the depot itself) go into its freighter slot at once, filling it; those
-- that don't fit go back to `give_back` (the player's inventory) rather than staying in the chest.
-- Only freighters the player just put in: at most `moved` (how many left their inventory), and no
-- more than the chest gained since it was last seen, so freighters already in the chest, put
-- there by an inserter, say, stay. Every other item put in stays in the chest, as in any
-- container. Not if freighters are what the depot requests: then they are cargo. Returns how many
-- went into the slot and how many went back.
function logistics.take_in_freighters(entity, give_back, moved)
  local depot = request_depot(entity)
  if not depot or (depot.request and depot.request.item == FREIGHTER) then
    return 0, 0
  end
  local chest = freighter_chest(entity)
  local now = count_freighters(chest)
  local new = math.min(math.max(0, now - (depot.chest_seen or 0)), math.floor(tonumber(moved) or 0))
  if new <= 0 then
    depot.chest_seen = now
    return 0, 0
  end
  local slot = trucks_of(depot)
  local in_slot, out, capacity = logistics.freighter_counts(entity)
  local leave = logistics.leaving(entity)
  local taken = load(chest, slot, FREIGHTER, math.min(new, math.max(0, capacity - in_slot - out)), leave, true)
  local returned = 0
  if give_back then
    for index = 1, #chest do
      local stack = chest[index]
      local movable = stack.valid_for_read and stack.name == FREIGHTER and stack.count - (leave[index] or 0) or 0
      local amount = math.min(movable, new - taken - returned)
      if amount > 0 then
        local inserted
        if amount >= stack.count then
          inserted = give_back.insert(stack)
        else
          inserted = give_back.insert({ name = FREIGHTER, quality = stack.quality.name, count = amount })
        end
        returned = returned + inserted
        if inserted >= stack.count then
          stack.clear()
        elseif inserted > 0 then
          stack.count = stack.count - inserted
        end
      end
    end
  end
  depot.chest_seen = count_freighters(chest)
  if taken > 0 then
    logistics.trim_freighter_requests(entity)
  end
  return taken, returned
end

logistics.count_freighters = count_freighters

-- Put freighters from `stack` (a player's cursor, say) into a request depot's slot: `count` of
-- them, or all, as far as it has room counting those out on trips. Returns how many went in.
function logistics.put_freighters(entity, stack, count)
  local in_slot, out, capacity = logistics.freighter_counts(entity)
  if not in_slot or not stack.valid_for_read or stack.name ~= FREIGHTER then
    return 0
  end
  local amount = math.min(count or stack.count, stack.count, capacity - in_slot - out)
  if amount <= 0 then
    return 0
  end
  local slot, moved = trucks_of(request_depot(entity)), 0
  for index = 1, #slot do
    local into = slot[index]
    if moved >= amount or not stack.valid_for_read then
      break
    end
    if not into.valid_for_read or into.name == stack.name then
      local before = stack.count
      into.transfer_stack(stack, math.min(before, amount - moved))
      moved = moved + before - (stack.valid_for_read and stack.count or 0)
    end
  end
  -- Freighters put in by hand count towards what robots were asked for: cancel the rest now,
  -- before robots deliver it.
  if moved > 0 then
    logistics.trim_freighter_requests(entity)
  end
  return moved
end

-- Take freighters out of a request depot's slot: `count` of them (or all) into `stack` (a
-- player's cursor), or all into `into` (an inventory). Returns how many came out.
function logistics.take_freighters(entity, stack, count, into)
  local depot = request_depot(entity)
  if not depot then
    return 0
  end
  -- Taking freighters out on purpose: no longer top the depot up to an earlier target.
  depot.freighter_target = nil
  local slot = trucks_of(depot)
  local before = slot.get_item_count()
  local wanted = math.min(count or before, before)
  for index = 1, #slot do
    local from = slot[index]
    local taken = before - slot.get_item_count()
    if taken >= wanted then
      break
    end
    if from.valid_for_read then
      if into then
        local inserted = into.insert(from)
        if inserted >= from.count then
          from.clear()
        else
          from.count = from.count - inserted
        end
      else
        -- Into the cursor: as much as it takes, at most one stack.
        local had = stack.valid_for_read and stack.count or 0
        stack.transfer_stack(from, math.min(from.count, wanted - taken))
        if (stack.valid_for_read and stack.count or 0) == had then
          break
        end
      end
    end
  end
  -- The freighters taken take their fuel entries, so freighters put in later come full.
  parked_fuel(depot)
  return before - slot.get_item_count()
end

-- Everything the freighter slot's requests are worked out from, for a request depot: for the
-- /jatz-freighters console command, to see what the game did when something looks wrong.
function logistics.describe_freighters(entity)
  local depot = request_depot(entity)
  if not depot then
    return nil
  end
  local in_slot, out, capacity = logistics.freighter_counts(entity)
  local proxies, coming, removing = freighter_requests(entity)
  local plans = {}
  for _, proxy in ipairs(proxies) do
    for _, kind in ipairs({ "insert", "removal" }) do
      for _, plan in pairs(kind == "insert" and proxy.insert_plan or proxy.removal_plan) do
        local positions = {}
        for _, position in pairs(plan.items.in_inventory or {}) do
          positions[#positions + 1] = position.stack .. ":" .. (position.count or 1)
        end
        plans[#plans + 1] = kind .. " " .. item_name(plan.id.name) .. " [" .. table.concat(positions, " ") .. "]"
      end
    end
  end
  return string.format(
    "depot %d tick %d: slot %d, out %d, chest %d, coming %d, leaving %d, target %s, total %d of %d; %d request proxies: %s",
    entity.unit_number,
    game.tick,
    in_slot,
    out,
    count_freighters(freighter_chest(entity)),
    coming,
    removing,
    tostring(depot.freighter_target),
    freighter_total(entity),
    capacity,
    #proxies,
    #plans > 0 and table.concat(plans, "; ") or "none"
  )
end

-- A requesting depot's freighters' fuel, in joules: those in its slot, fullest first, and those
-- out on trips; what a full tank holds; and whether fuel is used at all. Nil for anything else.
function logistics.freighter_fuel(entity)
  local depot = request_depot(entity)
  if not depot then
    return nil
  end
  local capacity = fuel_capacity()
  local parked = parked_fuel(depot)
  local home, out = {}, {}
  for _ = 1, trucks_of(depot).get_item_count() - #parked do
    home[#home + 1] = capacity
  end
  for _, energy in ipairs(parked) do
    home[#home + 1] = energy
  end
  table.sort(home, function(a, b)
    return a > b
  end)
  for id in pairs(trips_of(depot)) do
    local trip = storage.trips[id]
    if trip then
      out[#out + 1] = trip.energy or capacity
    end
  end
  return { home = home, out = out, capacity = capacity, used = fuel_per_tile() > 0 }
end

-- Give every freighter in a requesting depot's slot `energy` joules of fuel (other mods, tests).
-- Returns how many freighters that was.
function logistics.set_freighter_fuel(entity, energy)
  local depot = request_depot(entity)
  if not depot or type(energy) ~= "number" or energy ~= energy then
    return 0
  end
  local count = trucks_of(depot).get_item_count()
  local parked = {}
  if energy ~= fuel_capacity() then
    for index = 1, count do
      parked[index] = math.max(0, energy)
    end
  end
  depot.fuel = parked
  return count
end

-- What a Fuel depot's tank holds, for its panel: { fluid = name or nil, amount, capacity,
-- burnable }. Nil for anything else.
function logistics.fuel_contents(entity)
  local tank = entity and entity.valid and fuel_tank(entity)
  if not tank then
    return nil
  end
  local held = tank.get_fluid(1)
  return {
    fluid = held and held.name,
    amount = held and held.amount or 0,
    capacity = tank.get_fluid_capacity(1),
    burnable = held and burnable_fluid(held.name) ~= nil or false,
  }
end

-- Empty a Fuel depot's tank (a fluid piped in that doesn't burn blocks it). Returns false for
-- anything else.
function logistics.flush_fuel(entity)
  local tank = entity and entity.valid and fuel_tank(entity)
  if not tank then
    return false
  end
  tank.clear_fluid_inside()
  return true
end

function logistics.init()
  init_storage()
  logistics.add_all()
end

function logistics.register()
  script.on_nth_tick(IMPACT_INTERVAL, logistics.on_impact_tick)
  script.on_event(defines.events.on_ai_command_completed, logistics.on_ai_command_completed)
  script.on_event(defines.events.on_script_path_request_finished, logistics.on_script_path_request_finished)
  remote.add_interface("jatz-distribution", {
    -- For other mods and the tests: read and write a request depot's request and status.
    set_request = logistics.set_request,
    get_request = logistics.get_request,
    get_status = logistics.get_status,
    set_from_buffers = logistics.set_from_buffers,
    get_from_buffers = logistics.get_from_buffers,
    -- A provider or buffer depot's priority, 1 to 10.
    set_priority = logistics.set_priority,
    get_priority = logistics.get_priority,
    -- Any delivery depot's enable/disable circuit condition (enabled, condition, mode: "network",
    -- the default, or "contents").
    set_circuit = logistics.set_circuit,
    get_circuit = logistics.get_circuit,
    -- Give a request depot new freighters, within its slot's limit (counting freighters out);
    -- returns how many it took. And read its freighter counts.
    add_freighters = function(entity, count)
      local depot = request_depot(entity)
      if not depot or type(count) ~= "number" then
        return 0
      end
      local in_slot, out, capacity = logistics.freighter_counts(entity)
      local amount = math.max(0, math.min(math.floor(count), capacity - in_slot - out))
      local added = amount > 0 and trucks_of(depot).insert({ name = FREIGHTER, count = amount }) or 0
      if added > 0 then
        logistics.trim_freighter_requests(entity)
      end
      return added
    end,
    freighter_counts = logistics.freighter_counts,
    -- Ask construction robots to bring freighters (as from remote view), and cancel that.
    request_freighters = logistics.request_freighters,
    requested_freighters = logistics.requested_freighters,
    cancel_freighter_requests = logistics.cancel_freighter_requests,
    remove_freighters = logistics.remove_freighters,
    match_freighters = logistics.match_freighters,
    take_in_freighters = logistics.take_in_freighters,
    describe_freighters = logistics.describe_freighters,
    setup_blueprint = logistics.setup_blueprint,
    cancel_freighter_removal = logistics.cancel_freighter_removal,
    -- Freighter fuel, in joules: read a requesting depot's, and set its parked freighters'.
    freighter_fuel = logistics.freighter_fuel,
    set_freighter_fuel = logistics.set_freighter_fuel,
    fuel_contents = logistics.fuel_contents,
  })
end

return logistics
