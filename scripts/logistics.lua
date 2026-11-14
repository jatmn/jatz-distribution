-- SPDX-License-Identifier: LGPL-3.0-only
-- Deliveries between provider and request depots.
--
-- A request depot asks to keep at least `count` of one item (normal quality), and holds the
-- freighters that fetch it: up to 100 of them, in its freighter slot. Once a second, while what it
-- still needs (less what freighters are already bringing) is more than nothing, it sends one more
-- freighter, so freighters leave one after another rather than all at once. Each goes from the
-- depot's loading zone to the provider depot with the highest priority (1 to 10), nearest by road
-- among equals, that has some of the item not already promised to another freighter, and promises
-- itself what it will load there (up to two stacks, more with capacity research); once one
-- provider's stock is all promised, the next freighter goes to the next provider, so a large
-- request is gathered from several. Road distance comes from the engine's pathfinder (surface.request_path, with the
-- freighter's own size and collision mask), asked one provider at a time in order of straight-line
-- distance until no remaining provider could be nearer by road than the best found; a provider
-- with no road route at all is skipped for a while, and no freighter is sent towards it. The freighter
-- loads what is needed (no more than fits at the request depot, and at most two stacks before
-- capacity research), drives back, unloads and leaves the map. Freighters are units whose only
-- collision layer is on every tile except roads (prototypes/off-road.lua), so the engine's
-- pathfinder keeps them on roads; both loading zones must be road for a trip to start.
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
-- A request or buffer depot's freighters already on their way finish their trips; those on their
-- way to fetch from a depot that switches off, or that no longer has their load (an inserter or a
-- player took it out), go to another one once, then home (logistics.keep_promises).
--
-- Road tunnels (scripts/tunnels.lua) join road networks under whatever stands between their two
-- portals. A depot whose provider (or Fuel depot, or home) is on another network the tunnels join
-- sends its freighter through them: it drives to a portal's mouth, goes under (swapped for an
-- unseen freighter that stands there for as long as the tunnel takes to drive, `into_tunnel`),
-- comes out at the other end (`out_of_tunnel`) and drives on. Within one network it goes through
-- them where that is shorter than the road, as a search measured it (`drive`).
local loading_zone = require("scripts.loading-zone")
local paint = require("scripts.freighter-paint")
local depot_circuit = require("scripts.depot-circuit")
local research = require("scripts.research")
local impact = require("scripts.impact")
local tunnels = require("scripts.tunnels")
local robot_access = require("scripts.robot-access")
local robot_requests = require("scripts.freighter-requests")
local blueprints = require("scripts.blueprints")
local fueling = require("scripts.fuel")
local routes = require("scripts.routes")
local transfer = require("scripts.cargo")
local switching = require("scripts.circuit-switch")
local ledger = require("scripts.promises")
local lifecycle = require("scripts.trip-state")

local logistics = {}

-- Shown at every freighter's once-a-second check (check_trip), so a local, not a field read each time.
local show_fuel = fueling.show_fuel
-- Asked of every provider a search looks at, so a local too.
local enabled = switching.enabled
-- Filed whenever a trip changes, and asked of every provider a search looks at: locals too.
local promise, available = ledger.promise, ledger.available

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
-- Robots bring a requesting depot's freighters into this invisible chest under it
-- (prototypes/truck-chest.lua), which inserters can't reach: liquid depots are storage tanks with
-- no item inventory, and inserters unloading an item depot's chest would take freighters out of it
-- before they reach the slot.
local TRUCK_CHEST = "jatz-truck-chest"
logistics.truck_chest = TRUCK_CHEST

-- Request depots and freighters are checked this often (control.lua spreads the checks over the
-- ticks: logistics.on_tick_share).
local DISPATCH_INTERVAL = 60
logistics.dispatch_interval = DISPATCH_INTERVAL
-- A request depot sends at most one freighter this often, so they leave one after another.
local SEND_SPACING = 60
-- A freighter's fluid capacity before research (scripts/research.lua).
logistics.fluid_capacity = research.base_fluid
-- The least fluid a liquid depot's freighter sets off for, Full loads only or not (or its whole
-- request, if that is less): 100, the owner's choice (November 8, 2026). Without it, a provider with
-- the fraction pumps leave behind, or a tank pipes drained a little, sent freighters for almost
-- nothing, over and over.
logistics.least_fluid = 100

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
  -- Set to send full loads only: it lacks room for one, or no depot it fetches from has one.
  full_load = "full-load",
  -- A liquid depot not set to: it lacks room for logistics.least_fluid (or its whole request, if
  -- less), or no depot it fetches from has that much.
  least_fluid = "least-fluid",
}

-- Trip states: driving out to the provider, bringing cargo to the request depot, or taking cargo
-- back to the provider after the way to the request depot was lost.
local TO_PROVIDER, TO_REQUEST, RETURNING = "to-provider", "to-request", "returning"

-- Defined further down; dispatch, the search and on_tick need them first.
local end_trip, set_off, target, upgrade, burn

local function init_storage()
  storage.depots = storage.depots or {}
  storage.trips = storage.trips or {}
  -- Provider searches waiting for the pathfinder, by path request id.
  storage.searches = storage.searches or {}
end

-- Depots by where they stand and what they do: storage.depot_index[surface index][role] =
-- { [unit_number] = true }, so finding the providers or Fuel depots for a depot looks only at
-- those on its surface rather than at every depot. Depots never change surface or role. Kept up to
-- date as depots are added and removed, and built afresh when missing (a save from before it, or
-- after add_all). Not by force: a script can change an entity's force without an event (and
-- merging forces moves them), so the force is checked as the depots are looked at.
local NO_DEPOTS = {}
local function index_depot(id, depot, added)
  local index = storage.depot_index
  if not index then
    return
  end
  -- (One from an old save whose entity is gone and whose surface is unknown can't serve anyone.)
  local surface_index = depot.surface_index or (depot.entity.valid and depot.entity.surface_index)
  if not surface_index then
    return
  end
  local roles = index[surface_index]
  if added then
    roles = roles or {}
    index[surface_index] = roles
    local ids = roles[depot.role] or {}
    roles[depot.role] = ids
    ids[id] = true
  elseif roles and roles[depot.role] then
    roles[depot.role][id] = nil
  end
end

-- The unit_numbers of the depots with `role` on a surface (a table to read, not to change).
local function depots_at(surface_index, role)
  local index = storage.depot_index
  if not index then
    index = {}
    storage.depot_index = index
    for id, depot in pairs(storage.depots) do
      index_depot(id, depot, true)
    end
  end
  local roles = index[surface_index]
  return roles and roles[role] or NO_DEPOTS
end

-- Drop a request depot's current search; the next dispatch, within a second, starts a fresh one.
local function cancel_search(depot)
  lifecycle.cancel_search(depot)
end

-- A depot's item inventory: its chest, or a mining depot's output.
local function inventory(entity)
  if entity.name == MINING_DEPOT then
    return entity.get_output_inventory()
  end
  return entity.get_inventory(defines.inventory.chest)
end
logistics.inventory = inventory

-- Where robots bring a requesting depot's freighters: the truck chest under it (made if missing: a
-- save from before, or one removed by another mod). Anything else is its own.
local function truck_chest(entity)
  local depot = storage.depots and storage.depots[entity.unit_number]
  if not (depot and REQUESTING[depot.role]) then
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

-- The inventory robots bring a requesting depot's freighters into (see truck_chest).
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
logistics.energy_caption = fueling.energy_caption

-- Whether an item (or, for a liquid depot, a fluid) of this name exists, from game data, read once
-- per name.
local existing = { [true] = {}, [false] = {} }
local function exists(fluid, name)
  fluid = fluid == true
  local known = existing[fluid][name]
  if known == nil then
    known = (fluid and prototypes.fluid or prototypes.item)[name] ~= nil
    existing[fluid][name] = known
  end
  return known
end

-- Freighters of every quality in an inventory: any freighter can be sent out. One call: an item
-- filter without a quality matches every quality.
local FREIGHTERS_ANY_QUALITY = { name = FREIGHTER }
local function count_freighters(inventory_)
  return inventory_.get_item_count_filtered(FREIGHTERS_ANY_QUALITY)
end

-- Freighters in a requesting depot's chests, waiting to move into its slot or to be taken away by
-- robots: its truck chest's, and an item depot's own chest's. (A field, not a local: this file has
-- as many locals as Lua allows.)
function logistics.waiting_freighters(entity)
  local count = count_freighters(freighter_chest(entity))
  if not LIQUID[entity.name] then
    count = count + count_freighters(inventory(entity))
  end
  return count
end

-- What is learned about road (road lengths, whether a loading zone is road) is forgotten after
-- this long, in case another mod changed tiles without raising an event.
local ROAD_MEMORY_TICKS = 5 * 60 * 60

-- The loading zone tile's centre, and whether it is road. A depot keeps both (`depot.zone`): they
-- change only when it turns (its direction) or its surface's road changes (storage.road_versions,
-- counted up by on_roads_changed), and reading them makes a position, a surface and a tile for Lua
-- to collect every time. The table returned is shared: don't change it.
local function loading_tile(entity)
  local depot = storage.depots and storage.depots[entity.unit_number]
  local direction = entity.direction
  local versions = storage.road_versions
  local version = versions and versions[entity.surface_index] or 0
  local zone = depot and depot.zone
  if zone and zone.direction == direction and zone.version == version and game.tick - zone.tick < ROAD_MEMORY_TICKS then
    return zone.position, zone.road
  end
  local x, y = loading_zone.tile_centre(entity)
  local tile = entity.surface.get_tile(math.floor(x), math.floor(y))
  local position, road = { x = x, y = y }, tile.valid and (tile.name == ROAD or tile.name == DEPOT_ROAD)
  if depot then
    depot.zone = { position = position, road = road, direction = direction, version = version, tick = game.tick }
  end
  return position, road
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
  depot = {
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
    -- Request and buffer depots start with "Full loads only" as the startup setting says (off
    -- unless changed); blueprint tags and copied settings then set their own (scripts/blueprints.lua).
    full_loads = REQUESTING[role] and settings.startup["jatz-default-full-loads"].value or nil,
  }
  storage.depots[entity.unit_number] = depot
  index_depot(entity.unit_number, depot, true)
  script.register_on_object_destroyed(entity)
  -- Robots stay out of a new item provider or buffer depot until it lets them (scripts/robot-access.lua).
  robot_access.set(entity, false)
  if REQUESTING[role] then
    truck_chest(entity)
  end
  fuel_tank(entity)
end

-- Every depot's loading zone on a surface: the points tunnels note on each road network they flood
-- (scripts/tunnels.lua), so a depot's network is known without a flood of its own.
tunnels.zones = function(surface_index)
  local zones = {}
  for _, depot in pairs(storage.depots or {}) do
    if depot.surface_index == surface_index and depot.entity.valid then
      zones[#zones + 1] = (loading_tile(depot.entity))
    end
  end
  return zones
end

-- Moving cargo (scripts/cargo.lua).
transfer.install(logistics, { quality = QUALITY })

-- The freighter item's stack size.
local freighter_stack
local function freighter_stack_size()
  freighter_stack = freighter_stack or prototypes.item[FREIGHTER].stack_size
  return freighter_stack
end

-- A request depot's freighter slot: room for FREIGHTER_CAPACITY freighters, as real items, in as
-- many stacks as that takes. Slots from saves when it held one stack are made bigger.
local function trucks_of(depot)
  local stacks = math.ceil(FREIGHTER_CAPACITY / freighter_stack_size())
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

local function cargo_empty(trip)
  if trip.fluid then
    return trip.fluid.amount <= 0
  end
  return not (trip.cargo and trip.cargo.valid) or trip.cargo.is_empty()
end

-- The paint for what a trip's freighter carries.
local function paint_of(trip)
  if trip.movement == "underground" or trip.movement == "entering-tunnel" then
    -- In a tunnel: unseen.
    return paint.underground
  end
  return cargo_empty(trip) and DRONE or paint.drone_for_cargo(trip.fluid ~= nil, trip.item)
end

-- Put trip `id`'s freighter in the paint for what it carries: the same freighter, where it stands,
-- facing the same way and as damaged, as the drone prototype in that paint, and the trip moves to
-- the new unit_number. Only between commands: the new unit has none. Returns whether its paint is
-- right now.
-- Not while anything is stuck to it (fire, acid, slowdown): stickers are entities of their own,
-- stuck to this unit for good, and one made anew on another unit would restart its damage cycle,
-- adding or skipping a hit. A paint is only a look, so the freighter keeps its old one until they
-- wear off, and its once-a-second check paints it then (`check_trip`, `repaint_now`).
-- `position`: where the new one stands instead (coming out of a tunnel at its other end).
-- `orientation`: the way the new one faces instead (out of a tunnel's mouth).
-- The new unit is made facing that way (its nearest of the 16 directions, then exactly): a unit
-- made without one is drawn facing north and turns round at its rotation speed, whatever its
-- orientation is set to after (the owner's video, November 8, 2026: freighters coming out of a
-- tunnel and swapped for their cargo's paint showed north for a few ticks first).
local function repaint(id, trip, position, orientation)
  local old = trip.drone
  local name = paint_of(trip)
  if not old.valid or old.name == name then
    return true
  end
  if next(old.stickers or {}) then
    return false
  end
  orientation = orientation or old.orientation or 0
  local drone = old.surface.create_entity({
    name = name,
    position = position or old.position,
    force = old.force,
    direction = math.floor(orientation * 16 + 0.5) % 16,
  })
  if not drone then
    return false
  end
  drone.orientation = orientation
  drone.health = old.health
  -- A dry freighter crawls (DRY_SPEED): the new one must too.
  drone.speed = old.speed
  local depot = storage.depots[trip.request]
  lifecycle.rebind(trip, id, drone, depot and trips_of(depot))
  script.register_on_object_destroyed(drone)
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
  if cargo_empty(trip) or not trip.drone.valid or (trip.movement == "underground") then
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
    if trip and trip.search then
      lifecycle.retry_search(trip, game.tick - SEARCH_TIMEOUT)
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

-- Whether a request or buffer depot sends only freighters that can load a full load (see
-- full_load), rather than one for whatever little a provider has or the depot has room for.
function logistics.get_full_loads(entity)
  local depot = request_depot(entity)
  return depot and depot.full_loads == true or false
end

-- Returns false, changing nothing, for anything but a request or buffer depot.
function logistics.set_full_loads(entity, full_loads)
  local depot = request_depot(entity)
  if not depot then
    return false
  end
  depot.full_loads = full_loads == true
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

-- Depots switched by their circuit condition (scripts/circuit-switch.lua).
switching.install(logistics, { inventory = inventory, file_promises = ledger.file_promises })
logistics.sample_circuits = switching.sample_circuits
logistics.enabled = switching.enabled
logistics.holds_less = switching.holds_less
logistics.claims_ahead = switching.claims_ahead
logistics.get_circuit = switching.get_circuit
logistics.set_circuit = switching.set_circuit

-- Set by scripts/road-monitor.lua: what the road network monitors on a circuit network counted for
-- a depot (counted(unit_number, network) gives a list of counts by key), for its condition to
-- leave out.
logistics.monitor_counts = nil

-- A provider keeps its promises in the order they were made there (`trip.queued`, numbered as each
-- trip's promise is filed at a provider: setting off, or a reroute; trips from before have none and
-- come first), trip key breaking ties. Whether the promise filed under `key` comes before `trip`'s.
-- A promise is filed under the trip's key, and found by it in storage.trips: a trip holding one is
-- driving out (TO_PROVIDER, set only in start_trip), carrying nothing, in the empty paint it was
-- made in, so `repaint` (which would give it a new unit number) never touches it until it has
-- loaded and its promise is gone. (A field, not a local: this file has as many locals as Lua
-- allows.)
function logistics.ahead(key, trip)
  local other = storage.trips[key]
  if not other then
    return true
  end
  local mine, theirs = trip.queued or 0, other.queued or 0
  return theirs < mine or (theirs == mine and key < trip.key)
end

-- The next place in the queue of promises (see logistics.ahead).
function logistics.queue_place()
  storage.promise_order = (storage.promise_order or 0) + 1
  return storage.promise_order
end

-- Set a request depot's request, or clear it with a nil item. Returns false, changing nothing,
-- for anything but a request depot, an item that doesn't exist, or a count that isn't a number.
-- A request is at most what the depot holds: its tank's size for a liquid depot, and for an item
-- depot as many of the item as fill every slot of its chest (slots are a startup setting, 48 by
-- default: 4,800 of an item that stacks to 100, 480 of one that stacks to 10).
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
    count = math.max(0, math.floor(count))
    if depot.fluid then
      -- The tank's size, not a constant: liquid buffer sizes are a startup setting.
      count = math.min(count, depot.entity.get_fluid_capacity(1))
    else
      -- The chest's slots, not a constant, each a stack of this item.
      count = math.min(count, #inventory(depot.entity) * transfer.stack_size_of(item))
    end
    depot.request = { item = item, count = count }
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
      promise(trip)
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
-- what the depot can hold are filled as far as it can hold. Fourth, when it wants nothing more: by
-- how much what it holds and what is coming exceed its request (logistics.release_excess).
local function need(depot, except)
  local request = depot.request
  if not request or request.count <= 0 or not exists(depot.fluid, request.item) then
    return 0, 0
  end
  if depot.fluid then
    local tank = depot.entity
    local coming = ledger.committed(depot, except)
    local wanted = request.count - tank.get_fluid_count(request.item) - coming
    if wanted <= 0 then
      return 0, 0, nil, -wanted
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
  -- (An item's name alone means normal quality.)
  local chest, id = inventory(depot.entity), request.item
  local coming = ledger.committed(depot, except)
  local wanted = request.count - chest.get_item_count(id) - coming
  if wanted <= 0 then
    return 0, 0, nil, -wanted
  end
  return wanted, math.max(0, math.min(wanted, chest.get_insertable_count(id) - coming))
end

-- What a request or buffer depot still needs of what it requests: its request, less what it holds
-- and what freighters are bringing (0 with nothing requested). The road network monitor reads it.
function logistics.missing(depot)
  return (need(depot))
end

-- Provider and buffer depots that can supply `item` (a fluid, for liquid depots) on a surface, to a
-- force: on that surface, of that force and kind, holding the item unpromised, switched on by their
-- circuit condition, and with road at their loading zone. A list of { id, depot, position }.
-- While a tick's depots are checked (`suppliers_cache` is set: checking them changes no provider's
-- stock or promises), depots asking for the same share one look at every depot.
local suppliers_cache
local SUPPLYING = { "provider", "buffer" }
local function suppliers(surface_index, force_index, fluid, item)
  local key = suppliers_cache and table.concat({ surface_index, force_index, fluid and "fluid" or "item", item }, " ")
  if key and suppliers_cache[key] then
    return suppliers_cache[key]
  end
  local found = {}
  local depots = storage.depots
  for _, role in ipairs(SUPPLYING) do
    for unit_number in pairs(depots_at(surface_index, role)) do
      local provider = depots[unit_number]
      local candidate = provider and provider.entity
      if
        provider
        -- Items from item depots, fluids from liquid depots.
        and provider.fluid == fluid
        and candidate.valid
        and candidate.force_index == force_index
        and available(provider, item) > 0
        and enabled(provider, true)
      then
        local position, on_road = loading_tile(candidate)
        if on_road then
          found[#found + 1] = { id = unit_number, depot = provider, position = position }
        end
      end
    end
  end
  if key then
    suppliers_cache[key] = found
  end
  return found
end

-- For a depot set to send full loads only, the least a freighter of it may set off (or be rerouted)
-- to load: a full load, or the whole request if that is less (so a request smaller than a load
-- still comes, in one trip); and what the freighter carries. A new freighter (no `trip`) carries
-- the force's cargo stacks of the item or its fluid capacity, both with research; one already out
-- carries what its cargo inventory holds, sized when it set off, or for fluid the force's fluid
-- capacity, which arrived_at_provider reads as it loads. A liquid depot not set to full loads
-- still never sends one for less than logistics.least_fluid (or its whole request, if less). nil
-- for item depots not set to full loads, which send a freighter for any amount. (On the module table, as `missing`
-- is, to spare this file's main chunk a local: Lua allows 200, and it is close; see issue #69.)
--
-- Intentional: the threshold is the whole request, not what is still missing. A depot whose
-- request is smaller than one load, with some of it already in stock, has less room than the
-- request and so waits until it is empty enough to take all of it in one trip, rather than send
-- freighters to top it up a few at a time, which is the small trip this setting exists to stop.
-- Players who want topping up leave the setting off.
function logistics.full_load(depot, trip)
  local request = depot.request
  if not request or request.count <= 0 or not (depot.full_loads or depot.fluid) then
    return nil
  end
  local force = depot.entity.force
  if not depot.full_loads then
    return math.min(logistics.least_fluid, request.count), research.fluid_capacity_of(force)
  end
  local capacity
  if depot.fluid then
    capacity = research.fluid_capacity_of(force)
  else
    local stacks = trip and trip.cargo and #trip.cargo or research.cargo_stacks(force)
    capacity = stacks * transfer.stack_size_of(request.item)
  end
  return math.min(capacity, request.count), capacity
end

-- Every depot that could serve a requesting depot: provider depots, and for a request depot,
-- buffer depots too (a buffer depot itself fetches only from providers). A request depot set to
-- request from buffer depots ranks buffers first, however near a provider is; one not set to ranks
-- them last, so it falls back to a buffer only for what no provider can supply. All on the same
-- surface and force, with road at its loading zone, holding the item and not on cooldown for this
-- request. Within each kind, the highest priority first; within each priority, nearest first in a
-- straight line from `from`. With `full` (the least the freighter may load, for a depot sending
-- full loads only or a liquid depot: logistics.full_load), only those holding that much unpromised.
-- `passed` (a unit number) is left out: the provider a rerouted freighter gave up on. Also says
-- whether one was skipped for cooldown, and whether one was skipped for holding less than `full`.
local function candidates(depot, from, full, passed)
  local entity = depot.entity
  local found, waiting, short = {}, false, false
  local buffers = depot.role == "request"
  -- The kind of depot asked about first.
  local first = buffers and depot.from_buffers and "buffer" or "provider"
  local own = entity.unit_number
  for _, supplier in ipairs(suppliers(entity.surface_index, entity.force_index, depot.fluid, depot.request.item)) do
    local provider = supplier.depot
    -- (The one passed is neither ready nor waiting: the freighter goes on, or home.)
    if supplier.id ~= passed and (provider.role == "provider" or (buffers and supplier.id ~= own)) then
      if full and available(provider, depot.request.item) < full then
        short = true
      elseif (depot.cooldowns[supplier.id] or 0) > game.tick then
        waiting = true
      else
        local position = supplier.position
        local dx, dy = position.x - from.x, position.y - from.y
        found[#found + 1] = {
          id = supplier.id,
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
  table.sort(found, function(a, b)
    if a.rank ~= b.rank then
      return a.rank < b.rank
    end
    return a.distance < b.distance or (a.distance == b.distance and a.id < b.id)
  end)
  return found, waiting, short
end

-- Every trip out has its own tick of the second, its phase: storage.trip_phases[phase + 1] lists
-- the trips with that phase. Its once-a-second check (`check_trip`) comes at that tick, exactly
-- DISPATCH_INTERVAL ticks apart and within one of setting off, and it looks for enemies to run
-- over at that tick and every IMPACT_INTERVAL ticks after (`on_impact_share`). Exactly, because
-- fuel is burned by the straight-line distance since the last check: as every stop to load,
-- unload or fill up lasts LOADING_TICKS, no shorter than DISPATCH_INTERVAL, every stop has a check
-- in it, so two legs (out to a provider and back) are never measured as one (they would cancel).
-- A trip in a list is still out while storage.trips[trip.id] is that trip (`repaint` moves `id`
-- with it); the others are dropped when their phase comes round. Kept in storage, so every
-- player's game agrees, and kept as it is when the configuration changes (add_all): a trip given
-- a new phase could go up to two seconds without a check (Pullfrog's review of 0125590).
local function trip_phases()
  local phases = storage.trip_phases
  if not phases then
    -- First use in a save from before phases (every trip was checked at the same tick): the trips
    -- out share the phases in turn. Each burns what it has driven since its last check first, so
    -- its next check, at its new phase, is less than a second after a sample whatever that phase.
    phases = {}
    for phase = 1, DISPATCH_INTERVAL do
      phases[phase] = {}
    end
    local count = 0
    for id, trip in pairs(storage.trips) do
      trip.id = id
      burn(trip)
      local list = phases[count % DISPATCH_INTERVAL + 1]
      list[#list + 1] = trip
      count = count + 1
    end
    storage.trip_phases = phases
  end
  return phases
end

-- Give a trip setting off the phase with the fewest trips, so the checks stay evenly spread.
local function schedule_trip(id, trip)
  trip.id = id
  local phases = trip_phases()
  local fewest = 1
  for phase = 2, DISPATCH_INTERVAL do
    if #phases[phase] < #phases[fewest] then
      fewest = phase
    end
  end
  phases[fewest][#phases[fewest] + 1] = trip
end

-- Give a freighter a new command, counting its commands (`trip.command_id`): a failed command is
-- acted on the tick after (failed_commands), and only if no newer command has replaced it by then.
-- Every command a freighter gets goes through here. (A field, not a local: this file has as many
-- locals as Lua allows.)
function logistics.command(trip, command)
  if trip.movement == "underground" then
    -- Under ground: it comes out at the other end first (out_of_tunnel), which then drives it on
    -- to where it is going by then, or stops it for a search under way.
    return
  end
  trip.command_id = (trip.command_id or 0) + 1
  trip.drone.commandable.set_command(command)
end

-- Every leg starts here, so the fuel driven so far is burned here first: `burn` measures the
-- straight line since its last sample, and a freighter turned on the road without standing
-- anywhere (its pickup given up or cancelled, sent to another provider, its road cut) would
-- otherwise have the way out and the way back measured as one leg, which cancels out (Copilot's
-- review of feca8c7). (Even after a stand: one can be cut short, its provider removed or its
-- command failed, before the check in it. Only one that never left home, `departing`, is skipped.)
-- `sampled`: the caller burned it just now (set_off does, before deciding whether the leg needs a
-- Fuel depot first).
--
-- On a surface with tunnels, it follows a plan (`trip.plan`: the tunnels to go through in turn to
-- its destination, tunnels.plan), the shortest way by measured road, through any number of tunnels
-- or none (the owner, November 14, 2026: no penalty for going under, even several in series): the
-- plan a search made (`plan`), the one it is on (re-planned for the same destination), or one made
-- now. A plan needing roads not yet measured waits for the pathfinder, the freighter stopped
-- (`trip.planning`; tunnels.resume drives it on). It drives to the next tunnel's mouth
-- (`trip.tunnel`), and on from where it comes out (logistics.out_of_tunnel). Under ground, it only
-- notes where it is going.
local function drive(trip, destination, sampled, plan)
  if trip.movement == "underground" then
    trip.destination = destination
    lifecycle.travel(trip)
    return
  end
  if not (sampled or (trip.movement == "departing")) then
    burn(trip)
  end
  trip.destination = destination
  lifecycle.travel(trip)
  -- On the road now: no longer standing at home deciding whether it can go.
  lifecycle.move(trip, "road")
  trip.planning = nil
  -- (Not even asked in a game without tunnels: every leg of every freighter starts here.)
  local hop
  local tunnelled = storage.tunnel_surfaces
  if tunnelled and next(tunnelled) then
    if plan then
      trip.plan = { to = destination, hops = plan, step = 1 }
    end
    local current = trip.plan
    local surface_index = trip.drone.surface_index
    if
      tunnels.on(surface_index)
      and not (current and current.to.x == destination.x and current.to.y == destination.y)
    then
      -- From the last place it arrived at (its road network is known there), or where it stands.
      storage.search_count = (storage.search_count or 0) + 1
      local token = storage.search_count
      local hops = tunnels.plan(
        surface_index,
        trip.origin or trip.drone.position,
        destination,
        nil,
        trip.drone.force,
        { id = "trip " .. token, order = token, trip = trip, token = token }
      )
      if hops == false then
        trip.plan, trip.planning = nil, { to = destination, token = token, since = game.tick }
        return logistics.command(trip, { type = defines.command.stop, distraction = defines.distraction.none })
      end
      trip.plan = hops and { to = destination, hops = hops, step = 1 } or nil
      current = trip.plan
    end
    hop = current and current.hops[current.step]
  end
  lifecycle.road(trip, hop)
  logistics.command(trip, {
    type = defines.command.go_to_location,
    destination = hop and hop.entry or destination,
    radius = ARRIVAL_RADIUS,
    distraction = defines.distraction.none,
    pathfind_flags = { no_break = true },
  })
end

-- Send one of a request depot's freighters, the one with the most fuel, to `provider` (`length`
-- tiles away by road, through the tunnels `plan` lists, if any: see drive), to load `planned` of the
-- item. Returns whether it set off: one that can't reach the provider on its fuel, with no Fuel
-- depot to fill up at, goes back into the slot.
local function start_trip(depot, provider, from, planned, length, plan)
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
  if #parked > 0 and (trucks_of(depot).get_item_count() <= #parked or parked[#parked] > fueling.fuel_capacity()) then
    -- The fullest parked one: more than a tank, or (with none full) the most short of one.
    energy = table.remove(parked)
  else
    -- One with a full tank.
    energy = fueling.fuel_capacity()
  end
  drone.speed = research.freighter_speed(drone.force)
  local trip = {
    drone = drone,
    request = depot.entity.unit_number,
    provider = provider.entity.unit_number,
    item = depot.request.item,
    cargo = not depot.fluid and game.create_inventory(research.cargo_stacks(drone.force)) or nil,
    fluid = depot.fluid and { amount = 0 } or nil,
    -- The freighter item it was, taken from the depot's slot; it goes back there afterwards.
    truck = game.create_inventory(1),
    planned = planned,
    state = TO_PROVIDER,
    -- Fuel in joules; where it stood when last burned; the road length to its provider.
    energy = energy,
    at = from,
    -- Where it last arrived (or set off from): the road network it is on, for tunnels.
    origin = from,
    leg = length,
    movement = "departing",
    fuel_check = "unchecked",
    lifecycle_version = 1,
    -- Where it is going, should the provider go before it sets off (see target).
    destination = (loading_tile(provider.entity)),
  }
  trip.truck[1].transfer_stack(slot, 1)
  -- on_object_destroyed reports an entity's unit_number as its useful_id, the key used here.
  storage.trips[drone.unit_number] = trip
  trip.key = drone.unit_number
  trip.queued = logistics.queue_place()
  -- The request it was sent for (logistics.release_excess leaves it alone once that is lowered).
  trip.request_count = depot.request.count
  promise(trip)
  schedule_trip(drone.unit_number, trip)
  script.register_on_object_destroyed(drone)
  trips_of(depot)[drone.unit_number] = true
  depot.next_send = game.tick + SEND_SPACING
  if energy <= 0 and fueling.fuel_per_tile() > 0 then
    trip.dry = true
    drone.speed = research.freighter_speed(drone.force) * DRY_SPEED
  end
  show_fuel(trip)
  -- set_off may send it straight back into the slot (too little fuel, nowhere to fill up), which
  -- destroys the unit: only its id can be read after.
  set_off(trip.key, trip, length, plan)
  return storage.trips[trip.key] ~= nil
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
    return lifecycle.owns_search(trip, search.token) and trip or nil
  end
  local depot = storage.depots[search.request]
  return lifecycle.owns_search(depot, search.token) and depot or nil
end

-- Start looking for the provider nearest by road. With `trip`, the search is for a freighter
-- already out (its provider was removed) and starts where it stands. Returns false, with whether
-- a provider was skipped for cooldown, if there is nothing to look for.
local function search_providers(depot, from, trip)
  local rerouted = trip and storage.trips[trip]
  local found, waiting, short =
    candidates(depot, from, logistics.full_load(depot, rerouted), rerouted and rerouted.passed)
  if #found == 0 then
    return false, waiting, short
  end
  local search = {
    token = new_token(),
    request = depot.entity.unit_number,
    item = depot.request.item,
    from = from,
    -- Where a rerouted freighter last arrived when its search started (see logistics.search_plan).
    origin = rerouted and rerouted.origin,
    candidates = found,
    index = 1,
    trip = trip,
  }
  local owner = trip and storage.trips[trip] or depot
  lifecycle.begin_search(owner, "provider", search.token, game.tick)
  routes.ask_route(search, depot.entity.surface, depot.entity.force)
  return true
end

-- A failed pickup: home empty, through set_off like any leg, so a freighter short of fuel for the
-- way fills up at a Fuel depot first (as one that found nothing to load at its provider always
-- did). (A field, not a local: this file has as many locals as Lua allows.)
function logistics.home_empty(id, trip, depot)
  if trip.movement == "departing" then
    -- Still at home, never set off (waiting to hear where to fill up): it parks there and then, as
    -- one that can't set off does (go_without_fuel), rather than driving to a Fuel depot and back.
    return end_trip(id, trip)
  end
  trip.planned, trip.passed = nil, nil
  lifecycle.mission(trip, TO_REQUEST, promise)
  -- As far by road as it came (when it came from home), never less than the straight line: as one
  -- that found nothing to load at its provider (arrived_at_provider).
  local home, here = loading_tile(depot.entity), trip.drone.position
  set_off(id, trip, math.max(trip.leg or 0, math.sqrt((home.x - here.x) ^ 2 + (home.y - here.y) ^ 2)))
end

-- Find a new provider, nearest by road from where it stands, for a freighter whose provider is
-- gone or no longer suitable. It waits while the search runs, and goes home if there is none, or if
-- its depot no longer has room for what it would bring (filled meanwhile, by hand or otherwise):
-- sent on, it would drive farther only to load nothing (Copilot's review of 86332ce). A freighter
-- is sent to another provider only once a trip (`trip.diverted`, set when a reroute finds one,
-- whatever started it: its provider removed, or given up on): another reroute is a failed pickup,
-- and it goes home, never on to a third provider (the owner: no going back and forth).
local function reroute(id, trip)
  local depot = storage.depots[trip.request]
  local request = depot and depot.entity.valid and depot.request
  -- A Fuel depot it was heading for, or looking for, waits: set_off decides again for the new leg.
  lifecycle.clear_route_search(trip)
  -- A depot sending full loads only sends this one on only while the depot has room for its full
  -- load, besides what its other freighters are bringing, as when it was sent (a liquid depot, for
  -- its least load: logistics.full_load).
  local full = request and logistics.full_load(depot, trip)
  if
    trip.drone.valid
    and request
    and request.item == trip.item
    and not trip.diverted
    and select(2, need(depot, id)) > 0
    and (not full or select(2, need(depot, id)) >= full)
    and search_providers(depot, trip.drone.position, id)
  then
    logistics.command(trip, { type = defines.command.stop, distraction = defines.distraction.none })
  elseif not trip.drone.valid then
    -- Destroyed (by a script, say), its on_object_destroyed still to come at the end of this tick
    -- or the next: lost now, as that would, and its depot asks for a replacement. Ended as a trip,
    -- its truck would go back into the slot for free (Pullfrog's review of e949b72).
    logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = id })
  elseif depot and depot.entity.valid then
    -- No provider for it any more (none found at once, or every one asked had no road; diverted
    -- once already; nothing more needed): home empty.
    logistics.home_empty(id, trip, depot)
  else
    end_trip(id, trip)
  end
end

-- What a freighter driving out to its provider can still load there, or false for nothing: the
-- provider's stock of its item less what was promised there before its promise (logistics.ahead),
-- if above 0 and the provider's circuit condition holds now and with those loads taken (as it was
-- when the freighter was sent there, for one sent last). Stock taken out some other way (an
-- inserter, a player) or a condition switched off since leaves the last promised without a load
-- first, and the stock left after earlier promises is all a later freighter may take, even
-- arriving first. For one freighter (arriving to load); keep_promises works the same out for all of
-- a provider's in one pass. (A field, not a local: this file has as many locals as Lua allows.)
--
-- Many freighters can arrive at a busy provider in one tick, and asking which promises are ahead
-- of each one's walks all of the provider's promises of its item: arrivals cost the square of them
-- (Pullfrog's review of feca8c7: 800 arrivals in one tick, 320,400 order comparisons). So while the
-- provider's stock covers every promise there (their kept total, promise_totals), the order is not
-- asked: this freighter may load all it promised, and the answer is at least that. Its condition,
-- read from its contents, is then decided without the order too where one comparison of its item's
-- signal with a constant reads it ("<", ">", "≥", "≤": each only ever turns one way as stock goes):
-- holding now and with every other promise taken (more than those ahead), it holds with those
-- ahead taken. Otherwise (stock short of the promises, "=" or "≠", a condition reading more signals,
-- or one not holding with every other promise taken) the promises ahead are added up as before.
function logistics.honoured(trip)
  local provider = storage.depots[trip.provider]
  if not (provider and provider.entity.valid) then
    return false
  end
  if not (storage.promised and storage.promise_totals) then
    -- A save from before their totals were kept (or before promises were filed): filed afresh.
    ledger.file_promises()
  end
  local item = trip.item
  local contents = provider.circuit_enabled and provider.circuit_mode == depot_circuit.contents
  -- What it holds, read once: each read builds a signal for every item in it.
  local held = contents and switching.own_signals(provider) or nil
  if not enabled(provider, nil, held) then
    -- Switched off now: nothing for anyone, whatever the promises.
    return false
  end
  local stock = available(provider, item, true)
  local filed = trip.promise
  local own = filed and filed.provider == trip.provider and filed.amount == trip.planned and filed.amount or nil
  local sums = own and storage.promise_totals[trip.provider]
  local total = sums and sums[item] or 0
  if own and stock >= total then
    local spare = stock - total + own
    if not contents then
      return spare
    end
    local condition = provider.circuit_condition
    local signal = depot_circuit.key({ type = provider.fluid and "fluid" or "item", name = item })
    if
      depot_circuit.reads(condition) == signal
      and condition.comparator ~= "="
      and condition.comparator ~= "≠"
      and logistics.holds_less(provider, { [item] = total - math.ceil(own) }, held)
    then
      return spare
    end
  end
  -- What the promises ahead of its own add up to, of its item, and its stock less those.
  local ahead = 0
  local items = storage.promised[trip.provider]
  for key, amount in pairs(items and items[item] or {}) do
    if logistics.ahead(key, trip) then
      ahead = ahead + amount
    end
  end
  local left = stock - ahead
  if left <= 0 then
    return false
  end
  -- Only a condition reading its contents needs the promises ahead. One reading only this item's
  -- signal (a minimum on what it provides, the usual) needs only those of its item, added up above:
  -- scanning every item's again for each freighter made many arriving at a busy provider together
  -- cost the square of its promises (Sourcery's review of 2559152). Any other reads them all.
  local claims
  if contents then
    local signal = depot_circuit.key({ type = provider.fluid and "fluid" or "item", name = item })
    if depot_circuit.reads(provider.circuit_condition) == signal then
      claims = { [item] = ahead }
    else
      claims = logistics.claims_ahead(trip.provider, trip)
    end
  end
  -- (Its condition holds now, as read at the start.)
  if claims and not logistics.holds_less(provider, claims, held) then
    return false
  end
  return left
end

-- Look for another provider for a freighter its provider no longer has a load for, leaving that
-- one out: with a condition that taking items switches on (fetch only while below some amount,
-- say), it would pass for a new freighter and be found again, over and over. Its promise there
-- goes at once (promise files none while `passed`), so others can have that stock. reroute sends
-- it home instead if it was diverted once already, by a Fuel depot if it is short of fuel for the
-- way (home_empty), so it never goes back and forth between providers.
function logistics.give_up(id, trip)
  lifecycle.travel(trip)
  trip.passed = trip.provider
  promise(trip)
  reroute(id, trip)
end

-- At a provider or buffer depot's once-a-second check: freighters on their way there that it no
-- longer has a load for (as logistics.honoured: those promised first keep theirs) look for another
-- provider now, rather than finding out on arrival. Ones standing there to load find out then
-- (arrived_at_provider). Unless a condition reading its contents is in effect, or one reading the
-- network doesn't hold, or its stock no longer covers what was promised, only its promises are
-- looked at. Otherwise its promises are walked once, in order, adding up those ahead as it goes:
-- asking honoured for each would add them up afresh for every freighter, which for a provider with
-- hundreds of promises took tens of milliseconds in one tick (Pullfrog's review of 712a2fd).
function logistics.keep_promises(id, depot, held)
  local items = storage.promised and storage.promised[id]
  if not items then
    return
  end
  local on = not depot.circuit_enabled or enabled(depot, nil, held)
  local contents = depot.circuit_enabled and depot.circuit_mode == depot_circuit.contents
  -- (Read from the network, the condition leaves its contents out: the same for every freighter.)
  if on and not contents then
    local short = false
    for item in pairs(items) do
      if available(depot, item) < 0 then
        short = true
        break
      end
    end
    if not short then
      return
    end
  end
  -- Each item's stock as it is (what is unpromised, and every promise), and the trips promised.
  local stock, queue = {}, {}
  for item, trips in pairs(items) do
    local count = available(depot, item)
    for key, amount in pairs(trips) do
      count = count + amount
      local trip = storage.trips[key]
      if trip and trip.key == key then
        queue[#queue + 1] = trip
      end
    end
    stock[item] = count
  end
  -- The first promised first (logistics.ahead's order): a freighter rerouted from here no longer
  -- counts for those after it.
  table.sort(queue, function(a, b)
    local first, second = a.queued or 0, b.queued or 0
    return first < second or (first == second and a.key < b.key)
  end)
  -- What it holds, for the condition (only reading its contents do promises matter).
  local live = on and contents and (held or switching.own_signals(depot)) or nil
  -- Every freighter is decided first, and those it no longer has a load for give up only after:
  -- each give-up starts a search, which reads the providers (`suppliers`), so they must see this
  -- provider's promises as they end up, not some still to be let go (Sourcery's review of ac9ab0a).
  local ahead, failed, trimmed = {}, {}, false
  for _, trip in ipairs(queue) do
    local item = trip.item
    local kept = true
    if trip.state == TO_PROVIDER and trip.provider == id and not trip.service then
      local left = stock[item] - (ahead[item] or 0)
      if not (on and left > 0 and (not live or logistics.holds_less(depot, ahead, live))) then
        failed[#failed + 1] = trip
        kept = false
      elseif left < trip.planned then
        -- Only part of its load is left: it promises that, and its depot sends for the rest.
        trip.planned = left
        promise(trip)
        trimmed = true
      end
    end
    -- What it still promises here comes before those after it.
    if kept and trip.promise and trip.promise.provider == id then
      ahead[item] = (ahead[item] or 0) + trip.promise.amount
    end
  end
  if #failed == 0 then
    -- A promise made smaller changes what this provider has unpromised, and what its condition
    -- reads with promises taken: the depots checked before it this tick saw it as it was (Sourcery's
    -- review of 2559152).
    if trimmed and suppliers_cache then
      suppliers_cache = {}
    end
    return
  end
  for _, trip in ipairs(failed) do
    lifecycle.travel(trip)
    trip.passed = trip.provider
    promise(trip)
  end
  -- The depots checked before it this tick saw it among their suppliers, with those promises (and
  -- any made smaller): the searches look at the depots afresh.
  if suppliers_cache then
    suppliers_cache = {}
  end
  for _, trip in ipairs(failed) do
    logistics.give_up(trip.key, trip)
  end
end

-- Set off on a leg of `length` tiles by road towards the trip's target, by way of a Fuel depot if
-- the tank is short for it. The way here is burned first (see drive), so the tank is read as it is:
-- a freighter turned on the road between its checks was otherwise judged on the fuel it had at the
-- last one, and could set off for home without the Fuel depot it needed (Copilot's review of
-- be24d17). `plan`: the way to its target a search found, if any (see drive).
function set_off(id, trip, length, plan)
  if trip.movement ~= "departing" then
    burn(trip)
  end
  upgrade(trip)
  lifecycle.begin_leg(trip)
  if fueling.short_of_fuel(trip, length) then
    return fueling.look_for_fuel(id, trip)
  end
  drive(trip, target(trip), true, plan)
end

-- Drop a trip's search and start again: for fuel, or for a new provider.
local function search_again(id, trip)
  if trip.search and trip.search.kind == "fuel" then
    fueling.look_for_fuel(id, trip)
  else
    reroute(id, trip)
  end
end

-- Freighters robots brought into a request depot's truck chest, and those put into an item depot's
-- own chest (by hand or by inserters), go into its slot, as far as it has room; those in its own
-- chest stay there when freighters are what it requests (they are cargo then).
local function absorb_freighters(depot)
  local entity = depot.entity
  local chest = freighter_chest(entity)
  local own = not depot.fluid and not (depot.request and depot.request.item == FREIGHTER) and inventory(entity) or nil
  local in_truck_chest = count_freighters(chest)
  local in_own = own and count_freighters(own) or 0
  if in_truck_chest == 0 and in_own == 0 then
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
    -- Freighters waiting in the truck chest for robots to take them away stay there.
    local moved = in_truck_chest > 0 and transfer.load(chest, slot, FREIGHTER, room, logistics.leaving(entity), true)
      or 0
    if in_own > 0 and moved < room then
      moved = moved + transfer.load(own, slot, FREIGHTER, room - moved, nil, true)
    end
    -- (A buffer depot's freighters could be another depot's cargo: the depots checked with it look
    -- again.)
    if moved > 0 and suppliers_cache then
      suppliers_cache = {}
    end
  end
  -- What the chest a player puts freighters in holds now, so those put in later can be told apart.
  depot.chest_seen = count_freighters(own or chest)
end

-- A requesting depot that holds and has coming more than it asks for (filled meanwhile some other
-- way: by hand, an inserter, another depot's freighter) lets `excess` go from its freighters' promises
-- at providers, the last sent first, so those providers can give that stock to other depots at once
-- rather than when the freighters get there to load nothing. A freighter left with nothing to fetch
-- goes home empty (home_empty; one still at home parks). Freighters standing at a provider to load,
-- or bringing cargo home, aren't changed, nor are those sent for a larger request than it now has
-- (`trip.request_count`; trips from before have none): a lower request isn't stock got elsewhere,
-- and the request panel sets the amount as it is typed, so typing 200 passes through 2 and 20 on
-- the way, which cut freighters on the road for good (review of this change). (A field, not a local:
-- this file has as many locals as Lua allows. The owner's decision, November 7, 2026, from
-- Sourcery's review of 2559152.)
function logistics.release_excess(depot, excess)
  local outbound = {}
  for id in pairs(trips_of(depot)) do
    local trip = storage.trips[id]
    if
      trip
      and trip.state == TO_PROVIDER
      and not trip.service
      and trip.drone.valid
      and (trip.planned or 0) > 0
      and trip.item == depot.request.item
      and (trip.request_count or math.huge) <= depot.request.count
    then
      trip.id = id
      outbound[#outbound + 1] = trip
    end
  end
  -- The last promised first: those sent earlier keep their loads.
  table.sort(outbound, function(a, b)
    local first, second = a.queued or 0, b.queued or 0
    return first > second or (first == second and a.key > b.key)
  end)
  for _, trip in ipairs(outbound) do
    if excess <= 0 then
      break
    end
    local cut = math.min(excess, trip.planned)
    excess = excess - cut
    trip.planned = trip.planned - cut
    if trip.planned > 0 then
      promise(trip)
    else
      -- Nothing left to fetch: any search or Fuel depot it was heading for is dropped (set_off
      -- decides again for the way home).
      lifecycle.clear_route_search(trip)
      logistics.home_empty(trip.id, trip, depot)
    end
  end
  -- The providers have more unpromised now: depots checked after this one this tick look afresh.
  if #outbound > 0 and suppliers_cache then
    suppliers_cache = {}
  end
end

local function dispatch(depot)
  absorb_freighters(depot)
  logistics.trim_freighter_requests(depot.entity)
  local wanted, room, other_fluid, excess = need(depot)
  if excess and excess > 0 then
    logistics.release_excess(depot, excess)
  end
  if not enabled(depot) then
    -- Disabled by its circuit condition: no search, no freighter. One under way is dropped.
    cancel_search(depot)
    depot.status = logistics.status.disabled
    return
  end
  -- "On its way" only while a freighter is bringing some of the requested item: not one taking
  -- cargo back to its provider, nor one driving home empty.
  local out = ledger.committed(depot) > 0
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
  local full = logistics.full_load(depot)
  -- (A liquid depot not set to full loads waits for its least load the same way.)
  local short_status = depot.full_loads and logistics.status.full_load or logistics.status.least_fluid
  if full and room < full then
    -- Sending full loads only, and a full load wouldn't fit: it waits until one does.
    depot.status = out and logistics.status.delivering or short_status
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
    and #fueling.fuel_candidates(depot, from) > 0
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
  if depot.search and game.tick - depot.search.since < SEARCH_TIMEOUT then
    return
  end
  local started, waiting, short = search_providers(depot, from)
  if started then
    depot.status = out and logistics.status.delivering or logistics.status.searching
  else
    cancel_search(depot)
    depot.status = out and logistics.status.delivering
      or (waiting and logistics.status.unreachable)
      or (short and short_status)
      or logistics.status.no_provider
  end
end

-- Burn the fuel a freighter used driving since last time: what the tiles it covered take.
-- (`per_tile`: fueling.fuel_per_tile(), if the caller has read it already.)
function burn(trip, per_tile)
  local drone = trip.drone
  if not drone.valid then
    return
  end
  local position = drone.position
  local last = trip.at or position
  trip.at, trip.at_tick = position, game.tick
  upgrade(trip)
  per_tile = per_tile or fueling.fuel_per_tile()
  local dx, dy = position.x - last.x, position.y - last.y
  trip.energy = math.max(0, trip.energy - math.sqrt(dx * dx + dy * dy) * per_tile)
  if trip.dry and per_tile <= 0 then
    -- Fuel was turned off: nothing to crawl for.
    trip.dry = nil
    drone.speed = research.freighter_speed(drone.force)
  end
end

-- A trip's once-a-second check: it burns fuel, shows it, and pollutes a little (standing or
-- driving). A freighter whose search never answered (or met a busy pathfinder) searches again, and
-- one whose tank just ran dry crawls on, to a Fuel depot if it can find one. Returns whether it
-- drives in the wrong paint (something was stuck to it when it loaded) and can be painted now:
-- painting changes trip ids, so the caller does it after its loop (`repaint_now`).
-- `per_tile` and `capacity`: the fuel settings, read once for every trip checked in the tick;
-- `polluters`: each surface's pollute by surface index, bound once a tick (a method read off an
-- object is a new function every time).
local function check_trip(id, trip, per_tile, capacity, polluters)
  burn(trip, per_tile)
  show_fuel(trip, per_tile, capacity)
  local drone = trip.drone
  if drone.valid then
    local surface_index = drone.surface_index
    local pollute = polluters[surface_index]
    if not pollute then
      pollute = drone.surface.pollute
      polluters[surface_index] = pollute
    end
    -- Where burn just found it.
    pollute(trip.at, POLLUTION_PER_SECOND * DISPATCH_INTERVAL / 60, DRONE)
  end
  if trip.search and game.tick - trip.search.since >= SEARCH_TIMEOUT then
    search_again(id, trip)
  elseif trip.planning and drone.valid and game.tick - trip.planning.since >= SEARCH_TIMEOUT then
    -- Its roads were never measured (a busy pathfinder, say): it asks again. (Not one destroyed,
    -- its on_object_destroyed still to come: Pullfrog's review of 5d10933.)
    drive(trip, trip.planning.to)
  elseif trip.drone.valid and trip.energy <= 0 and not trip.dry and per_tile > 0 then
    trip.dry = true
    trip.drone.speed = research.freighter_speed(trip.drone.force) * DRY_SPEED
    if not (trip.refuel or trip.search or trip.service) then
      fueling.look_for_fuel(id, trip)
    end
  elseif
    trip.drone.valid
    and trip.destination
    and not trip.search
    and not trip.service
    and trip.drone.name ~= paint_of(trip)
  then
    return true
  end
  return false
end

-- Paint the freighters of these trips (ids) for their cargo, once nothing is stuck to them, and
-- drive them on from where they stand.
local function repaint_now(pending)
  for _, id in ipairs(pending) do
    local trip = storage.trips[id]
    if trip and trip.drone.valid and repaint(id, trip) then
      show_cargo(trip)
      drive(trip, target(trip))
    end
  end
end

-- A depot's once-a-second check: a request or buffer depot dispatches, a Fuel depot's tank keeps
-- facing as the depot does, and one gone before on_object_destroyed reached it (Factorio raises
-- that at the end of the tick or the next) is forgotten exactly as that would: its freighters in
-- the slot, on trips and in its truck chest left where it stood, its truck chest and Fuel depot tank
-- removed, and trips to it sent elsewhere. Then on_object_destroyed finds nothing left to do.
local function check_depot(id, depot)
  if not depot.entity.valid then
    logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = id })
    -- The depots checked with it saw it among their suppliers, with its promises.
    if suppliers_cache then
      suppliers_cache = {}
    end
    return
  end
  -- A condition reading the depot's own contents reads them once for its status and its promises
  -- (nothing in between changes them): each read builds a signal for every item it holds.
  local held = depot.circuit_enabled and depot.circuit_mode == depot_circuit.contents and switching.own_signals(depot)
    or nil
  if depot.circuit_enabled or depot.shown_off then
    switching.show_switched(depot, held)
  end
  if depot.role == "provider" or depot.role == "buffer" then
    logistics.keep_promises(id, depot, held)
  end
  if REQUESTING[depot.role] then
    dispatch(depot)
  elseif depot.role == "fuel" then
    fuel_tank(depot.entity)
  end
end

-- Every trip's and every depot's check at once.
function logistics.on_tick()
  local pending = {}
  local per_tile, capacity, polluters = fueling.fuel_per_tile(), fueling.fuel_capacity(), {}
  for id, trip in pairs(storage.trips) do
    if check_trip(id, trip, per_tile, capacity, polluters) then
      pending[#pending + 1] = id
    end
  end
  repaint_now(pending)
  suppliers_cache = {}
  routes.checking_depots = true
  for id, depot in pairs(storage.depots) do
    check_depot(id, depot)
  end
  suppliers_cache = nil
  routes.checking_depots = false
  logistics.answer_remembered()
end

-- The tick of the second (0 to DISPATCH_INTERVAL - 1) at which a depot is checked; `index` is its
-- place in this pass. Requesting depots that fetch the same thing from the same depots (same
-- surface, the same item or fluid) are checked in the same tick, as every depot was before the
-- checks were spread: their searches then all see the stock as it was before any of them promised
-- a load, and near stock is shared among them before anyone drives farther. Checked one after
-- another, later depots found the near providers' stock promised to earlier ones and drove past
-- them to farther ones (in the UPS emulator, 14% fewer items delivered with the same freighters).
-- Each such group gets its own tick, the next group the golden ratio of a second further on, so
-- groups spread evenly over the second; every other depot is checked at the tick of its place.
local GROUP_STRIDE = 37
local function check_phase(depot, index)
  local request = REQUESTING[depot.role] and depot.request
  if not (request and depot.surface_index) then
    return index % DISPATCH_INTERVAL
  end
  local group = depot.surface_index .. (depot.fluid and " fluid " or " item ") .. request.item
  storage.check_phases = storage.check_phases or {}
  local phase = storage.check_phases[group]
  if not phase then
    storage.check_groups = (storage.check_groups or 0) + 1
    phase = storage.check_groups * GROUP_STRIDE % DISPATCH_INTERVAL
    storage.check_phases[group] = phase
  end
  return phase
end

-- The depots (unit numbers) to check at `tick`, from a plan made at the start of each second and
-- kept in storage, so every player's game agrees. Depots added during a second wait for the next.
local function depots_due(tick)
  local phase = tick % DISPATCH_INTERVAL
  storage.passes = storage.passes or {}
  local plan = storage.passes.depots
  if phase == 0 or not plan then
    plan = {}
    local index = 0
    for id, depot in pairs(storage.depots) do
      local at = check_phase(depot, index) + 1
      plan[at] = plan[at] or {}
      plan[at][#plan[at] + 1] = id
      index = index + 1
    end
    storage.passes.depots = plan
  end
  return plan[phase + 1] or {}
end

-- Once a second for every trip and depot, spread over the second, so a game with hundreds of
-- depots and thousands of freighters does this work evenly rather than all in one tick: the trips
-- by their phase (trip_phases), and the depots by check_phase.
function logistics.on_tick_share(tick)
  if not storage.depots then
    return
  end
  -- The trips whose phase this is; those no longer out leave the list.
  local list = trip_phases()[tick % DISPATCH_INTERVAL + 1]
  local pending, kept = {}, 0
  local per_tile, capacity, polluters
  if #list > 0 then
    per_tile, capacity, polluters = fueling.fuel_per_tile(), fueling.fuel_capacity(), {}
  end
  for index = 1, #list do
    local trip = list[index]
    list[index] = nil
    local id = trip.id
    if storage.trips[id] == trip then
      kept = kept + 1
      list[kept] = trip
      if check_trip(id, trip, per_tile, capacity, polluters) then
        pending[#pending + 1] = id
      end
    end
  end
  repaint_now(pending)
  local depots = storage.depots
  suppliers_cache = {}
  routes.checking_depots = true
  for _, id in ipairs(depots_due(tick)) do
    local depot = depots[id]
    if depot then
      check_depot(id, depot)
    end
  end
  suppliers_cache = nil
  routes.checking_depots = false
  logistics.answer_remembered()
end

-- Saves from this PR's first version carried cargo as a plain count, and the mod version didn't
-- change, so no configuration change converts them: carry such cargo as stacks from here on.
-- Base stacks is 2, so the inventory has to be large enough for a count saved when a freighter
-- held ten.
function upgrade(trip)
  lifecycle.upgrade(trip)
  -- Trips from before fuel set off with a full tank.
  trip.energy = trip.energy or fueling.fuel_capacity()
  if type(trip.cargo) == "number" then
    local count = trip.cargo
    local item = prototypes.item[trip.item]
    local slots = research.base_stacks
    if count > 0 and item and item.stack_size > 0 then
      slots = math.max(slots, math.ceil(count / item.stack_size))
    end
    trip.cargo = game.create_inventory(slots)
    if count > 0 and item then
      trip.cargo.insert({ name = trip.item, count = count })
    end
  end
  return trip
end

-- End a trip: its freighter leaves the map and goes back into its depot's slot as an item, unless
-- it was `lost` (destroyed on the way). If the depot is gone it has already handed its freighters
-- over; one somehow still aboard is left where the freighter stands. What it drove since its last
-- fuel sample is burned first: one coming home empty parks at once, with no stand (and so no
-- once-a-second check) at the end of its last leg (see drive).
function end_trip(id, trip, lost)
  if storage.trips[id] ~= trip then
    return
  end
  if trip.movement ~= "departing" then
    burn(trip)
  end
  lifecycle.finish(trip, id, promise)
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
      if inserted > 0 and trip.energy and trip.energy ~= fueling.fuel_capacity() then
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
  local had = entity and math.max(logistics.freighter_total(entity), robot_requests.target(home) or 0)
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
  -- changed to another item, or been filled some other way, since the freighter set off. This holds
  -- with Full loads only too: that rule decides when a freighter sets off (dispatch, reroute), and
  -- once it is here, bringing what fits beats driving home empty for the same trip.
  if provider and request and request.item == trip.item then
    -- What it promised, as far as the depot (counting its other freighters) still needs it.
    local _, room = need(depot, id)
    local left = room > 0 and logistics.honoured(trip)
    if room > 0 and not left then
      -- Nothing here for it any more (taken out some other way, or switched off since its
      -- provider's last check): another provider, rather than home empty.
      return logistics.give_up(id, trip)
    end
    -- No more than is left after the promises made before its own, which are their freighters'.
    local limit = math.min(trip.planned or room, room, left or room)
    if trip.fluid then
      transfer.load_fluid(provider, trip, math.min(limit, research.fluid_capacity_of(depot.entity.force)))
    else
      transfer.load(inventory(provider), trip.cargo, trip.item, limit)
    end
  end
  trip.planned = nil
  lifecycle.mission(trip, TO_REQUEST, promise)
  if not (depot and depot.entity.valid) then
    return end_trip(id, trip)
  end
  -- Home, loaded or (if there was nothing to load) empty, to unload and park, painted for its load:
  -- as far by road as it came (when it came from home), and never less than the straight line.
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
  lifecycle.fuel_checked(trip)
  if fuel and fuel.entity.valid then
    fueling.refuel(trip, fuel)
  end
  if trip.dry and trip.energy > 0 then
    trip.dry = nil
    trip.drone.speed = research.freighter_speed(trip.drone.force)
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
      transfer.unload_fluid(trip, entity)
    end
    -- Fluid that didn't fit (another fluid got into the tank meanwhile, say) goes back.
    local provider = depot_entity(trip.provider)
    if trip.fluid.amount > 0 and provider then
      lifecycle.mission(trip, RETURNING, promise)
      return drive(trip, (loading_tile(provider)))
    end
    return end_trip(id, trip)
  end
  if entity then
    transfer.unload(trip.cargo, inventory(entity))
  end
  transfer.spill(trip, entity and (loading_tile(entity)) or nil)
  end_trip(id, trip)
end

local function returned_to_provider(id, trip)
  local provider = depot_entity(trip.provider)
  if provider then
    if trip.fluid then
      transfer.unload_fluid(trip, provider)
    else
      transfer.unload(trip.cargo, inventory(provider))
    end
  end
  transfer.spill(trip, provider and (loading_tile(provider)) or nil)
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
    lifecycle.mission(trip, RETURNING, promise)
    return drive(trip, (loading_tile(provider)))
  end
  transfer.spill(trip)
  end_trip(id, trip)
end

-- No road route to the Fuel depot it was heading for: don't try that one again for a while, and
-- look for another, or go on without.
local function fuel_route_failed(id, trip, depot)
  if depot then
    depot.cooldowns[trip.refuel] = game.tick + RETRY_TICKS
  end
  fueling.look_for_fuel(id, trip)
end

-- The road's speed bonus (prototypes/roads.lua), read once: a freighter goes through a tunnel as
-- fast as it drives on road. (A field, not a local: this file has few locals to spare.)
function logistics.road_speed()
  if not logistics.road_speed_bonus then
    local tile = prototypes.tile and prototypes.tile["jatz-road"]
    logistics.road_speed_bonus = tile and tile.walking_speed_modifier or 1
  end
  return logistics.road_speed_bonus
end

-- At a tunnel's mouth: it goes under, swapped for the unseen freighter (`paint.underground`),
-- which stands there for as long as driving the tunnel's length on road takes, then comes out at
-- the other end (out_of_tunnel). Commands wait meanwhile (logistics.command). A tunnel closed
-- since (a portal removed or turned) is no way through: it plans afresh from here. Something stuck
-- to it (fire, acid) is its own entity, stuck to this unit for good (see repaint): it waits at the
-- mouth until that wears off.
function logistics.into_tunnel(id, trip)
  local tunnel = trip.tunnel
  trip.origin = tunnel.entry
  -- Fuel is burned by the straight line since the last sample (`burn`), and going through moves it
  -- from one mouth to the other at once: the way here is burned now, the tunnel's length when it
  -- comes out (out_of_tunnel), so neither is measured as part of one line across both (Pullfrog's
  -- review of fa62744).
  burn(trip)
  if not tunnels.open(tunnel) then
    -- Its plan went through this tunnel: plan afresh from here.
    lifecycle.move(trip, "road")
    trip.plan = nil
    return drive(trip, trip.destination or target(trip))
  end
  lifecycle.move(trip, "entering-tunnel", tunnel)
  -- The unseen freighter has one direction, so the game turns it north: remember which way it went in.
  tunnel.orientation = trip.drone.orientation
  if not repaint(id, trip) then
    lifecycle.move(trip, "waiting-at-tunnel", tunnel)
    return logistics.command(trip, {
      type = defines.command.stop,
      distraction = defines.distraction.none,
      ticks_to_wait = 60,
    })
  end
  -- Where it goes in isn't where it comes out: it runs nothing over in between (scripts/impact.lua).
  trip.last_position = nil
  local speed = trip.drone.speed * logistics.road_speed()
  logistics.command(trip, {
    type = defines.command.stop,
    distraction = defines.distraction.none,
    ticks_to_wait = math.max(1, math.ceil(tunnel.length / math.max(speed, 0.001))),
  })
  lifecycle.move(trip, "underground", tunnel)
end

-- Out of a tunnel, where it now stands at the far mouth: the fuel for the tunnel's length on road,
-- exactly, and the next sample measured from here (into_tunnel burned the way to the mouth).
function logistics.through_tunnel(trip, tunnel)
  local per_tile = fueling.fuel_per_tile()
  if per_tile > 0 then
    trip.energy = math.max(0, (trip.energy or fueling.fuel_capacity()) - tunnel.length * per_tile)
  end
  trip.at, trip.at_tick = trip.drone.position, game.tick
  show_fuel(trip)
end

-- Through a tunnel: it comes out at the other end, seen again in its cargo's paint, and drives on
-- to where it is going (trip.destination, which a re-plan or reroute while it was under ground
-- changed), or waits there for a search still under way.
function logistics.out_of_tunnel(id, trip)
  local tunnel = trip.tunnel
  lifecycle.move(trip, "road")
  trip.origin = tunnel.exit
  -- On to the next tunnel of its plan, or its destination.
  local plan = trip.plan
  local done = plan and plan.hops[plan.step]
  if done and done.from == tunnel.from and done.to == tunnel.to then
    plan.step = plan.step + 1
  end
  trip.last_position = nil
  -- Facing out of the far mouth (or as it went in, should that portal be gone), not as the unseen
  -- freighter stood: north, which it then turned from at once. However it comes out.
  local facing = tunnels.facing(tunnel.to) or tunnel.orientation
  if trip.search then
    -- A search under way belongs to this unit (its id): it comes out unseen, waits for the answer,
    -- and is painted once that is in (check_trip), as repainting would make the search stale.
    -- Painting keeps its facing, so it is turned now. (A stop keeps a unit's facing; an idle one
    -- drifts round, probed on 2.1.24.)
    trip.drone.teleport(tunnel.exit)
    trip.drone.orientation = facing or trip.drone.orientation
    logistics.through_tunnel(trip, tunnel)
    return logistics.command(trip, { type = defines.command.stop, distraction = defines.distraction.none })
  end
  -- Just inside the mouth, facing out, then straight out of it before its route (tunnels.way_out).
  local start, out = tunnels.way_out(tunnel.to, tunnel.exit)
  if not repaint(id, trip, start or tunnel.exit, facing) then
    -- Something got stuck to it under ground: it comes out unseen, and is painted once that wears off
    -- (check_trip).
    trip.drone.teleport(start or tunnel.exit)
  end
  trip.drone.orientation = facing or trip.drone.orientation
  logistics.through_tunnel(trip, tunnel)
  show_cargo(trip)
  if out then
    -- On to where it is going once out (on_ai_command_completed; a re-plan meanwhile drives it there).
    lifecycle.travel(trip)
    lifecycle.move(trip, "exiting-tunnel")
    return logistics.command(trip, {
      type = defines.command.go_to_location,
      destination = out,
      radius = 0.2,
      distraction = defines.distraction.none,
      pathfind_flags = { no_break = true },
    })
  end
  drive(trip, trip.destination or target(trip))
end

function logistics.on_ai_command_completed(event)
  local id = event.unit_number
  local trip = storage.trips and storage.trips[id]
  if not trip or event.result == defines.behavior_result.deleted then
    return
  end
  lifecycle.upgrade(trip)
  local tunnel = trip.tunnel
  if trip.movement == "underground" and event.result == defines.behavior_result.success and trip.drone.valid then
    -- Through the tunnel (a search under way waits for it to come out). A failure under ground is
    -- a freighter dying at the mouth (enemies, or a script: see below), acted on as any failure.
    return logistics.out_of_tunnel(id, trip)
  end
  -- A command replaced by a newer one (see replan) is not the end of anything, and a freighter
  -- waiting for a reroute search has nowhere to arrive (unless under ground, whose failed wait is
  -- acted on below).
  if (trip.search or trip.planning) and trip.movement ~= "underground" then
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
  if event.result == defines.behavior_result.success and not (tunnel or (trip.movement == "exiting-tunnel")) then
    -- Where it is now (a depot's loading zone): its road network is known there. Its plan got it here.
    trip.origin = trip.destination or trip.origin
    trip.plan = nil
  end
  if event.result ~= defines.behavior_result.success then
    -- One killed by a script (LuaEntity::die: the console, the editor, another mod) fails its
    -- command as it dies with its health still showing, so a failure is acted on next tick
    -- (failed_commands), when such a freighter is gone: taken home as a failed route, it went back
    -- into the slot and its depot asked robots for no replacement. Which command failed is noted:
    -- one given meanwhile (its request depot removed, say) replaces it.
    local failed = storage.failed_trips or {}
    trip.id = id
    failed[#failed + 1] = { trip = trip, command_id = trip.command_id }
    storage.failed_trips = failed
  elseif tunnel then
    -- At a tunnel's mouth (or waiting there for something stuck to it to wear off).
    logistics.into_tunnel(id, trip)
  elseif trip.movement == "exiting-tunnel" then
    -- Out of a tunnel's mouth: on to where it is going.
    drive(trip, trip.destination or target(trip))
  elseif trip.refuel and not trip.service then
    -- At the Fuel depot: it stands there LOADING_TICKS to fill up too.
    lifecycle.begin_service(trip, game.tick)
    logistics.command(trip, {
      type = defines.command.stop,
      distraction = defines.distraction.none,
      ticks_to_wait = LOADING_TICKS,
    })
  elseif trip.refuel then
    arrived_at_fuel(id, trip)
  elseif not trip.service and not (trip.state == TO_REQUEST and cargo_empty(trip)) then
    -- Arrived to load or unload: stand there LOADING_TICKS first. The stop command's completion
    -- comes back here, and the freighter loads or unloads then. One coming home empty just parks.
    lifecycle.begin_service(trip, game.tick)
    logistics.command(trip, {
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

-- The commands freighters failed (on_ai_command_completed), the tick after, from control.lua's
-- on_tick: a freighter gone by now died as it failed and is lost; any other lost its way, unless
-- it has had a newer command since (the failure is then the old command's, and over), or waits
-- for a reroute search. (A field, not a local: this file has as many locals as Lua allows.)
function logistics.failed_commands()
  local failed = storage.failed_trips
  storage.failed_trips = nil
  for _, failure in ipairs(failed or {}) do
    -- Still out (`repaint` moves `id` with it): one that ended meanwhile (on_object_destroyed found
    -- it gone, say) needs nothing more.
    local trip = failure.trip
    local id = trip.id
    if storage.trips[id] == trip then
      if not trip.drone.valid then
        lose(id, trip)
      elseif trip.movement == "underground" and trip.command_id == failure.command_id then
        -- Its wait under ground failed, yet it lives: it comes out at the other end all the same.
        logistics.out_of_tunnel(id, trip)
      elseif (trip.movement == "exiting-tunnel") and trip.command_id == failure.command_id then
        -- Its short stretch out of a mouth failed (road removed there, say): its route decides.
        drive(trip, trip.destination or target(trip))
      elseif trip.command_id == failure.command_id and not trip.search and not trip.planning then
        if trip.refuel then
          fuel_route_failed(id, trip, storage.depots[trip.request])
        else
          route_failed(id, trip, storage.depots[trip.request])
        end
      end
    end
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
  if trip.drone.valid and trip.destination and not trip.search and not trip.service then
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
    if depot.search and depot.search.token and depot.entity.valid and depot.entity.surface_index == surface_index then
      cancel_search(depot)
    end
  end
  for id, trip in pairs(storage.trips) do
    if trip.search and trip.search.token and trip.drone.valid and trip.drone.surface_index == surface_index then
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
  -- Routes there may be longer, shorter, new or gone.
  if storage.road_lengths then
    storage.road_lengths[surface_index] = nil
  end
  storage.road_versions = storage.road_versions or {}
  storage.road_versions[surface_index] = (storage.road_versions[surface_index] or 0) + 1
  -- Which road networks tunnels join may have changed too: at once if road was removed, which can
  -- split one.
  tunnels.changed(surface_index, removed)
  -- The roads measured for ways through tunnels, where road was laid or removed (not for a tile
  -- such as concrete laid elsewhere).
  if added or removed then
    tunnels.forget(surface_index, removed)
  end
  if removed then
    -- Where a freighter last arrived may be on another road network than where it stands now: it
    -- plans from where it stands. First, before anything reads it: the searches restarted below fix
    -- their origin from it (Pullfrog's review of fa62744).
    for _, trip in pairs(storage.trips) do
      if trip.drone.valid and trip.drone.surface_index == surface_index then
        -- Its plan was worked out on the road as it was.
        trip.origin, trip.plan = nil, nil
      end
    end
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
        lifecycle.mission(trip, RETURNING, promise)
        replan(trip)
      elseif trip.state == TO_PROVIDER or cargo_empty(trip) then
        end_trip(trip_id, trip)
      end
    elseif trip.provider == id and trip.state == RETURNING then
      -- Bringing cargo back to a provider that is gone: try the request depot again.
      if depot_entity(trip.request) then
        lifecycle.mission(trip, TO_REQUEST, promise)
        replan(trip)
      else
        transfer.spill(trip)
        end_trip(trip_id, trip)
      end
    elseif trip.provider == id and trip.state == TO_PROVIDER then
      reroute(trip_id, trip)
    elseif trip.refuel == id then
      -- The Fuel depot it was heading for is gone (one standing there leaves at once): another.
      lifecycle.clear_route_search(trip)
      fueling.look_for_fuel(trip_id, trip)
    end
  end
end

-- The way through tunnels a freighter's search found, if it still starts where the freighter is: a
-- search started under ground plans from the mouth it went in at, and one that has come out at the
-- other end since plans afresh from there (drive). (A field, not a local: this file has few locals
-- to spare.)
function logistics.search_plan(search, trip)
  local was, now = search.origin, trip.origin
  if was == now or (was and now and was.x == now.x and was.y == now.y) then
    return search.best_plan
  end
  return nil
end

-- The search is over: send a freighter to the provider nearest by road (or redirect the freighter
-- the search was for), if the request still wants the item.
local function finish_search(depot, search, owner)
  if search.fuel then
    -- A freighter's search for a Fuel depot: fill up at the nearest by road, if it still has fuel.
    lifecycle.cancel_search(owner)
    local fuel = search.best and storage.depots[search.best]
    if fuel and fuel.entity.valid and fueling.has_fuel(fuel) then
      owner.refuel = search.best
      drive(owner, (loading_tile(fuel.entity)), nil, logistics.search_plan(search, owner))
    elseif search.best and search.best_rank == 0 then
      -- The one found was emptied or removed meanwhile: look again among the rest.
      fueling.look_for_fuel(search.trip, owner)
    else
      -- None with fuel has a road; one without fuel may (rank 1).
      fueling.go_without_fuel(search.trip, owner, search.best ~= nil)
    end
    return
  end
  local provider = search.best and storage.depots[search.best]
  -- Sending full loads only: the provider must still have one, and the depot room for one (for a
  -- rerouted freighter, the full load its cargo holds); a liquid depot, its least load likewise.
  local full, carries = logistics.full_load(depot, search.trip and owner)
  local still = depot.request
    and depot.request.item == search.item
    and provider
    and provider.entity.valid
    and available(provider, search.item) > 0
    and (not full or available(provider, search.item) >= full)
    and enabled(provider, true)
  if search.trip then
    -- What its depot still has room for, counting its other freighters (not this one).
    local _, room = need(depot, search.trip)
    -- Its depot filled during the search: reroute sends it home. Sending full loads only, it needs
    -- room for this freighter's full load.
    if still and room > 0 and (not full or room >= full) then
      lifecycle.cancel_search(owner)
      -- Promise only what its depot still has room for (it may have filled in part during the
      -- search: Sourcery's review of ac9ab0a), and the new provider has unpromised (`available`
      -- doesn't count this trip's promise: it gave up on its old provider, logistics.give_up, which
      -- unfiled it, or that one was removed, its entry left under the removed depot's number).
      -- Sending full loads only, a full load: planned afresh, as a freighter sent off now would be,
      -- whatever it set off for. So is a liquid freighter (its least load), rather than keep a load
      -- keep_promises cut down to almost nothing at the provider it gave up on.
      local unpromised = available(provider, search.item)
      owner.planned = full and math.min(room, unpromised, carries) or math.min(owner.planned or 0, room, unpromised)
      owner.provider = search.best
      -- Last in its new provider's queue, and its one diversion used (reroute). Any provider may be
      -- found again by a later search (the one passed was only for this one).
      owner.queued, owner.passed, owner.diverted = logistics.queue_place(), nil, true
      promise(owner)
      owner.leg = search.best_length
      set_off(search.trip, owner, search.best_length, logistics.search_plan(search, owner))
    else
      -- The provider found was emptied or removed meanwhile: look again among the rest. (Or the
      -- depot no longer has room for a full load: reroute sends it home.)
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
  if not still or not on_road or room <= 0 or (full and room < full) then
    -- Something changed while searching; the next dispatch looks again.
    return
  end
  -- This freighter promises to load what the depot still needs, as far as the provider has it
  -- unpromised and it can carry; the next freighter covers the rest, from here or elsewhere.
  local force = depot.entity.force
  local capacity = depot.fluid and research.fluid_capacity_of(force)
    or research.cargo_stacks(force) * transfer.stack_size_of(search.item)
  local planned = math.min(room, available(provider, search.item), capacity)
  depot.retry_status = nil
  if start_trip(depot, provider, from, planned, search.best_length, search.best_plan) then
    depot.status = logistics.status.delivering
  elseif (depot.retry_at or 0) <= game.tick then
    -- (A freighter that stayed home for want of fuel has set the wait and status already.)
    depot.retry_at = game.tick + RETRY_TICKS
    depot.status = logistics.status.no_freighter
  end
end

-- The road length to the search's current candidate is known (nil: no road): take it, and ask about
-- the next candidate or finish.
local function route_answered(search, length)
  local owner = owner_of(search)
  local depot = storage.depots[search.request]
  if not (owner and depot and depot.entity.valid) then
    return
  end
  local candidate = search.candidates[search.index]
  -- On a surface with tunnels, the way through them, if shorter than the road (or where there is
  -- none), from where the search asks the road from, as tunnels.plan measures it: until it has,
  -- the search waits here (`search.waiting`, the road's length or false; tunnels.resume).
  local plan
  local surface_index = depot.entity.surface_index
  if tunnels.on(surface_index) then
    local through
    plan, through = tunnels.plan(
      surface_index,
      search.from,
      candidate.position,
      length or false,
      depot.entity.force,
      { id = "search " .. search.token, order = search.token, search = search, wait = (search.wait or 0) + 1 }
    )
    if plan == false then
      -- (Each wait its own: a question an earlier one asked, answered busy, says nothing of this.)
      search.waiting, search.wait = length or false, (search.wait or 0) + 1
      return
    end
    if plan then
      length = through
    end
  end
  if length then
    if length < (search.best_length or math.huge) then
      search.best, search.best_length, search.best_rank = candidate.id, length, candidate.rank
      search.best_plan = plan
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
    return routes.ask_route(search, depot.entity.surface, depot.entity.force)
  end
  finish_search(depot, search, owner)
end

-- Road routes for searches (scripts/routes.lua), once route_answered is defined.
routes.install(logistics, {
  owner_of = owner_of,
  cancel_search = cancel_search,
  route_answered = route_answered,
  drone = DRONE,
  arrival_radius = ARRIVAL_RADIUS,
  road_memory_ticks = ROAD_MEMORY_TICKS,
  dispatch_interval = DISPATCH_INTERVAL,
  search_timeout = SEARCH_TIMEOUT,
})
-- An owner waiting for the roads of a way through tunnels to be measured (tunnels.plan) goes on:
-- a search takes its candidate's road again, a freighter drives on. With the pathfinder busy, a
-- search starts afresh later as with its own question (routes.on_script_path_request_finished), and
-- a freighter plans again at its next check.
function tunnels.resume(waiter, busy)
  local search = waiter.search
  if search then
    local owner = owner_of(search)
    local depot = storage.depots[search.request]
    if not (owner and depot and depot.entity.valid and search.waiting ~= nil and waiter.wait == search.wait) then
      return
    end
    if busy then
      if search.trip then
        lifecycle.retry_search(owner, game.tick - SEARCH_TIMEOUT)
      else
        cancel_search(depot)
      end
      return
    end
    local length = search.waiting
    search.waiting = nil
    return route_answered(search, length or nil)
  end
  local trip = waiter.trip
  local planning = trip and trip.planning
  if not (planning and planning.token == waiter.token and storage.trips[trip.id] == trip and trip.drone.valid) then
    return
  end
  if busy then
    planning.since = game.tick - SEARCH_TIMEOUT
    return
  end
  drive(trip, planning.to)
end

logistics.on_script_path_request_finished = routes.on_script_path_request_finished
logistics.answer_remembered = routes.answer_remembered

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
-- (Those in its truck chest are left there too, when on_object_destroyed removes it.)
function logistics.on_depot_destroyed(event)
  local depot = request_depot(event.entity)
  if depot then
    -- Those put in its own chest: an item depot's, or a liquid depot's truck chest.
    refund(depot, nil, inventory(depot.fluid and truck_chest(event.entity) or event.entity))
  end
end

-- A request depot mined by a player, robot or platform: its freighters go with it, those waiting in
-- its truck chest too (an item depot's own chest is mined with it).
function logistics.on_depot_mined(event)
  local depot = request_depot(event.entity)
  if depot then
    refund(depot, event.buffer, freighter_chest(event.entity))
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
    index_depot(id, depot, false)
    depot_removed(id)
  elseif storage.trips[id] then
    lose(id, upgrade(storage.trips[id]))
  end
end

-- Every freighter looked at every IMPACT_INTERVAL ticks (scripts/impact.lua), at the ticks of its
-- phase (trip_phases), so thousands of freighters don't all search the ground in the same tick.
-- Whether there are units at all is asked at the start of each round.
logistics.on_impact_tick = impact.on_tick
function logistics.on_impact_share(tick)
  if not storage.trips then
    return
  end
  if not impact.open(tick) then
    return
  end
  local interval = impact.INTERVAL
  local phases = trip_phases()
  for phase = tick % interval, DISPATCH_INTERVAL - 1, interval do
    local list = phases[phase + 1]
    impact.run_over(list, 1, #list, storage.impact_fresh)
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
  blueprints.copy_request(source, destination)
end

-- A depot the game knew as `old_id` is now `entity`, a new entity of the same depot standing where
-- it stood (scripts/legacy-depots.lua: an item provider or buffer depot from before they were
-- logistic containers). Everything kept by its unit number moves to the new one, so its settings,
-- freighters, trips and the promises made to it carry on. Called before add_all, which starts
-- searches afresh and files promises again.
function logistics.replaced(old_id, entity)
  local depots = storage.depots
  local depot = depots and depots[old_id]
  local id = entity.unit_number
  if not (depot and id) then
    return
  end
  index_depot(old_id, depot, false)
  depots[old_id], depots[id] = nil, depot
  index_depot(id, depot, true)
  depot.entity = entity
  -- The old entity's inventory, and its custom status, which the new one doesn't show yet.
  depot.stock_inventory, depot.shown_off = nil, nil
  script.register_on_object_destroyed(entity)
  for _, other in pairs(depots) do
    local cooldowns = other.cooldowns
    if cooldowns and cooldowns[old_id] then
      cooldowns[id], cooldowns[old_id] = cooldowns[old_id], nil
    end
  end
  for _, trip in pairs(storage.trips) do
    if trip.request == old_id then
      trip.request = id
    end
    if trip.provider == old_id then
      trip.provider = id
    end
    if trip.passed == old_id then
      trip.passed = id
    end
  end
  for _, name in ipairs({ "promised", "promise_totals", "coming", "spoiling", "circuit_watch" }) do
    local by_depot = storage[name]
    if by_depot and by_depot[old_id] ~= nil then
      by_depot[id], by_depot[old_id] = by_depot[old_id], nil
    end
  end
  -- The second's plan of depot checks names the old one: planned again.
  if storage.passes then
    storage.passes.depots = nil
  end
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
  -- Migrate before removing depots can inspect or redirect their live trips.
  for _, trip in pairs(storage.trips) do
    lifecycle.upgrade(trip)
  end
  for id, depot in pairs(storage.depots) do
    lifecycle.upgrade_search(depot)
    cancel_search(depot)
    if not depot.entity.valid then
      -- Gone without on_object_destroyed reaching it: forgotten as that would (see check_depot).
      logistics.on_object_destroyed({ type = defines.target_type.entity, useful_id = id })
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
      switching.watch(depot)
      if REQUESTING[depot.role] then
        robot_requests.target(depot)
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
        transfer.spill(trip)
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
    if trip.search then
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
    end
    depot.position = depot.position or (depot.entity.valid and depot.entity.position)
    depot.surface_index = depot.surface_index or (depot.entity.valid and depot.entity.surface_index)
  end
  ledger.file_promises()
  -- Mods changed: roads, freighters and research may have too. The depot index is built afresh.
  storage.road_lengths, storage.road_answers, storage.research_levels = nil, nil, nil
  storage.depot_index = nil
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

-- Freighters asked of construction robots, as from remote view (scripts/freighter-robot_requests.lua).
robot_requests.install(logistics, {
  request_depot = request_depot,
  truck_chest = truck_chest,
  freighter_chest = freighter_chest,
  trucks_of = trucks_of,
  a_freighter = a_freighter,
  parked_fuel = parked_fuel,
  freighter_stack_size = freighter_stack_size,
  freighter = FREIGHTER,
  quality = QUALITY,
})
logistics.requested_freighters = robot_requests.requested_freighters
logistics.request_freighters = robot_requests.request_freighters
logistics.remove_freighters = robot_requests.remove_freighters
logistics.freighter_total = robot_requests.freighter_total
logistics.match_freighters = robot_requests.match_freighters
logistics.trim_freighter_requests = robot_requests.trim_freighter_requests

-- Depot settings in blueprints, copy and paste and undo (scripts/blueprints.lua).
blueprints.install(logistics, {
  request_depot = request_depot,
  supplying_depot = supplying_depot,
  priority_default = PRIORITY_DEFAULT,
  freighter = FREIGHTER,
  liquid = LIQUID,
})
logistics.request_tag = blueprints.request_tag
logistics.freighters_tag = blueprints.freighters_tag
logistics.settings_tags = blueprints.settings_tags
logistics.setup_blueprint = blueprints.setup_blueprint
logistics.on_player_setup_blueprint = blueprints.on_player_setup_blueprint
logistics.apply_tags = blueprints.apply_tags
logistics.on_entity_settings_pasted = blueprints.on_entity_settings_pasted

function logistics.cancel_freighter_removal(entity)
  if not request_depot(entity) then
    return 0
  end
  local proxies, _, removing = robot_requests.freighter_requests(entity)
  for _, proxy in ipairs(proxies) do
    local kept = {}
    for _, plan in pairs(proxy.removal_plan) do
      if robot_requests.item_name(plan.id.name) ~= FREIGHTER then
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
  robot_requests.set_target(depot, nil)
  local proxies, requested = robot_requests.freighter_requests(entity)
  for _, proxy in ipairs(proxies) do
    local kept = {}
    for _, plan in pairs(proxy.insert_plan) do
      if robot_requests.item_name(plan.id.name) ~= FREIGHTER then
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
  local _, _, _, marked = robot_requests.freighter_requests(entity)
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
  -- Freighters put in by hand go into an item depot's own chest (a liquid depot has none but its
  -- truck chest).
  local chest = inventory(depot.fluid and truck_chest(entity) or entity)
  local now = count_freighters(chest)
  local new = math.min(math.max(0, now - (depot.chest_seen or 0)), math.floor(tonumber(moved) or 0))
  if new <= 0 then
    depot.chest_seen = now
    return 0, 0
  end
  local slot = trucks_of(depot)
  local in_slot, out, capacity = logistics.freighter_counts(entity)
  -- Robots take freighters away from the truck chest only (a liquid depot's is its hand chest).
  local leave = depot.fluid and logistics.leaving(entity) or {}
  local taken = transfer.load(chest, slot, FREIGHTER, math.min(new, math.max(0, capacity - in_slot - out)), leave, true)
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
  robot_requests.set_target(depot, nil)
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
  local proxies, coming, removing = robot_requests.freighter_requests(entity)
  local plans = {}
  for _, proxy in ipairs(proxies) do
    for _, kind in ipairs({ "insert", "removal" }) do
      for _, plan in pairs(kind == "insert" and proxy.insert_plan or proxy.removal_plan) do
        local positions = {}
        for _, position in pairs(plan.items.in_inventory or {}) do
          positions[#positions + 1] = position.stack .. ":" .. (position.count or 1)
        end
        plans[#plans + 1] = kind
          .. " "
          .. robot_requests.item_name(plan.id.name)
          .. " ["
          .. table.concat(positions, " ")
          .. "]"
      end
    end
  end
  return string.format(
    "depot %d tick %d: slot %d, out %d, chest %d, coming %d, leaving %d, target %s, total %d of %d; %d request proxies: %s",
    entity.unit_number,
    game.tick,
    in_slot,
    out,
    logistics.waiting_freighters(entity),
    coming,
    removing,
    tostring(robot_requests.target(depot)),
    robot_requests.freighter_total(entity),
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
  local capacity = fueling.fuel_capacity()
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
  return { home = home, out = out, capacity = capacity, used = fueling.fuel_per_tile() > 0 }
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
  if energy ~= fueling.fuel_capacity() then
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
    burnable = held and fueling.burnable_fluid(held.name) ~= nil or false,
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

-- Set by other scripts (scripts/road-monitor.lua) before register(): more functions for the remote
-- interface.
logistics.remote_extra = {}
-- Set by scripts/road-monitor.lua: the blueprint tag (name and value) of a road network monitor.
logistics.monitor_tag = nil
-- Set by scripts/depot-settings.lua: a blueprint's entries with request depots' requests and
-- freighters added as request settings, for parametrisation (plan), and the request and freighters
-- of the settings beside a depot built at once, removing them, or that they gave it (take).
logistics.plan_request_settings = nil
logistics.take_request_settings = nil

-- Speed research finished (or undone): the force's freighters on the road drive at the new speed.
function logistics.on_research_changed(event)
  local technology = event.research
  if storage.research_levels then
    storage.research_levels[technology.force.index] = nil
  end
  if not research.is_speed(technology) then
    return
  end
  local force = technology.force
  local speed = research.freighter_speed(force)
  for _, trip in pairs(storage.trips or {}) do
    local drone = trip.drone
    if drone.valid and drone.force.index == force.index then
      -- A dry one still crawls (DRY_SPEED), at its share of the new speed.
      drone.speed = trip.dry and speed * DRY_SPEED or speed
    end
  end
end

-- Forces reset, made or merged: forget every force's research (scripts/research.lua's research_of).
function logistics.on_forces_changed()
  storage.research_levels = nil
end

function logistics.register()
  script.on_event(defines.events.on_force_reset, logistics.on_forces_changed)
  script.on_event(defines.events.on_technology_effects_reset, logistics.on_forces_changed)
  script.on_event(defines.events.on_force_created, logistics.on_forces_changed)
  script.on_event(defines.events.on_forces_merged, logistics.on_forces_changed)
  script.on_event(defines.events.on_research_finished, logistics.on_research_changed)
  script.on_event(defines.events.on_research_reversed, logistics.on_research_changed)
  script.on_event(defines.events.on_ai_command_completed, logistics.on_ai_command_completed)
  script.on_event(defines.events.on_script_path_request_finished, logistics.on_script_path_request_finished)
  local interface = {
    -- For other mods and the tests: read and write a request depot's request and status.
    set_request = logistics.set_request,
    get_request = logistics.get_request,
    get_status = logistics.get_status,
    set_from_buffers = logistics.set_from_buffers,
    get_from_buffers = logistics.get_from_buffers,
    -- A request or buffer depot sending only freighters that can load a full load.
    set_full_loads = logistics.set_full_loads,
    get_full_loads = logistics.get_full_loads,
    -- A provider or buffer depot's priority, 1 to 10.
    set_priority = logistics.set_priority,
    get_priority = logistics.get_priority,
    -- Whether logistic robots may use an item provider or buffer depot (scripts/robot-access.lua).
    set_robot_access = robot_access.set,
    get_robot_access = robot_access.get,
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
  }
  for name, call in pairs(logistics.remote_extra) do
    interface[name] = call
  end
  remote.add_interface("jatz-distribution", interface)
end

-- Freighter fuel (scripts/fuel.lua), once end_trip and target are defined.
fueling.install(logistics, {
  fuel_tank = fuel_tank,
  inventory = inventory,
  depots_at = depots_at,
  loading_tile = loading_tile,
  new_token = new_token,
  ask_route = routes.ask_route,
  drive = drive,
  end_trip = end_trip,
  target = target,
  retry_ticks = RETRY_TICKS,
})

-- What trips promised and are bringing (scripts/promises.lua), once upgrade is defined.
ledger.install(logistics, {
  inventory = inventory,
  trips_of = trips_of,
  upgrade = upgrade,
  to_provider = TO_PROVIDER,
  to_request = TO_REQUEST,
})

return logistics
