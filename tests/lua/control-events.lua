-- SPDX-License-Identifier: LGPL-3.0-only
-- control.lua's event wiring for depot roads, against a small fake of the Factorio runtime: the
-- real control.lua registers its handlers on a fake `script`, and this fires the game's events
-- at them (building, turning, removing a depot; a player placing or mining a tile over its road;
-- a script setting tiles), so a handler that is missing or routes to the wrong place fails here.
-- Run from the repository root with Lua 5.2 (tools/test_mod_setup.py does): lua5.2 tests/lua/control-events.lua
package.path = "./?.lua;" .. package.path

local handlers = {}
defines = setmetatable({
  direction = { north = 0, east = 4, south = 8, west = 12 },
  inventory = { chest = 1 },
  target_type = { entity = 1 },
  behavior_result = { in_progress = 0, fail = 1, success = 2, deleted = 3 },
  command = { go_to_location = 1, stop = 2 },
  distraction = { none = 0 },
  -- Events are identified by name here.
  events = setmetatable({}, {
    __index = function(_, name)
      return name
    end,
  }),
}, {
  __index = function(_, name)
    return setmetatable({}, {
      __index = function(_, key)
        return name .. "." .. key
      end,
    })
  end,
})
-- defines.relative_gui_type as Factorio 2.1 has it (runtime-api.json, api_version 6): a name it
-- doesn't have (storage_tank_gui was removed in 2.1) is an error here, as it is in game, rather than
-- a made-up value.
local RELATIVE_GUI_TYPES = {
  "accumulator_gui",
  "achievement_gui",
  "additional_entity_info_gui",
  "admin_gui",
  "agriculture_tower_gui",
  "alerts_config_gui",
  "arithmetic_combinator_gui",
  "armor_gui",
  "assembling_machine_gui",
  "assembling_machine_select_recipe_gui",
  "asteroid_collector_gui",
  "beacon_gui",
  "blueprint_book_gui",
  "blueprint_library_gui",
  "blueprint_setup_gui",
  "boiler_gui",
  "bonus_gui",
  "burner_equipment_gui",
  "car_gui",
  "cargo_landing_pad_gui",
  "constant_combinator_gui",
  "container_gui",
  "controller_gui",
  "decider_combinator_gui",
  "deconstruction_item_gui",
  "display_panel_gui",
  "electric_energy_interface_equipment_gui",
  "electric_energy_interface_gui",
  "electric_network_gui",
  "entity_variations_gui",
  "entity_with_energy_source_gui",
  "equipment_grid_gui",
  "furnace_gui",
  "generic_on_off_entity_gui",
  "ghost_picker_gui",
  "global_electric_network_gui",
  "heat_interface_gui",
  "heat_pipe_gui",
  "infinity_pipe_gui",
  "inserter_gui",
  "item_with_inventory_gui",
  "lab_gui",
  "lamp_gui",
  "linked_container_gui",
  "loader_gui",
  "logistic_gui",
  "market_gui",
  "mining_drill_gui",
  "other_player_gui",
  "permissions_gui",
  "pick_stop_gui",
  "pipe_gui",
  "power_switch_gui",
  "production_gui",
  "programmable_speaker_gui",
  "proxy_container_gui",
  "pump_gui",
  "radar_gui",
  "rail_signal_base_gui",
  "reactor_gui",
  "resource_entity_gui",
  "roboport_gui",
  "rocket_silo_gui",
  "script_inventory_gui",
  "selector_combinator_gui",
  "server_config_gui",
  "space_platform_hub_gui",
  "spider_vehicle_gui",
  "splitter_gui",
  "standalone_character_gui",
  "tile_variations_gui",
  "tips_and_tricks_gui",
  "train_gui",
  "train_stop_gui",
  "trains_gui",
  "transport_belt_gui",
  "turret_gui",
  "upgrade_item_gui",
  "wall_gui",
}
defines.relative_gui_type = setmetatable({}, {
  __index = function(_, key)
    error("FAILED: defines.relative_gui_type has no " .. tostring(key) .. " in Factorio 2.1", 2)
  end,
})
for _, name in ipairs(RELATIVE_GUI_TYPES) do
  rawset(defines.relative_gui_type, name, "relative_gui_type." .. name)
end
-- defines.wire_connector_id as Factorio 2.1 has it (runtime-api.json 2.1.24); others are errors.
defines.wire_connector_id = setmetatable({}, {
  __index = function(_, key)
    error("FAILED: defines.wire_connector_id has no " .. tostring(key) .. " in Factorio 2.1", 2)
  end,
})
for _, name in ipairs({
  "circuit_green",
  "circuit_red",
  "combinator_input_green",
  "combinator_input_red",
  "combinator_output_green",
  "combinator_output_red",
  "pole_copper",
  "power_switch_left_copper",
  "power_switch_right_copper",
}) do
  rawset(defines.wire_connector_id, name, "wire_connector_id." .. name)
end
-- defines.control_behavior's types and storage tank modes as Factorio 2.1 has them
-- (runtime-api.json 2.1.24); others are errors.
local function strict(what, names)
  local list = setmetatable({}, {
    __index = function(_, key)
      error("FAILED: " .. what .. " has no " .. tostring(key) .. " in Factorio 2.1", 2)
    end,
  })
  for _, name in ipairs(names) do
    rawset(list, name, what .. "." .. name)
  end
  return list
end
defines.entity_status_diode = strict("defines.entity_status_diode", { "green", "red", "yellow" })
defines.control_behavior = {
  type = strict("defines.control_behavior.type", {
    "accumulator",
    "agricultural_tower",
    "arithmetic_combinator",
    "artillery_turret",
    "assembling_machine",
    "asteroid_collector",
    "boiler",
    "cargo_landing_pad",
    "constant_combinator",
    "container",
    "decider_combinator",
    "display_panel",
    "furnace",
    "generic_on_off",
    "heat_pipe",
    "inserter",
    "lab",
    "lamp",
    "land_mine",
    "loader",
    "logistic_container",
    "mining_drill",
    "programmable_speaker",
    "proxy_container",
    "pump",
    "radar",
    "rail_chain_signal",
    "rail_signal",
    "reactor",
    "roboport",
    "rocket_silo",
    "selector_combinator",
    "single_fluid_box",
    "space_platform_hub",
    "splitter",
    "train_stop",
    "transport_belt",
    "turret",
    "wall",
  }),
  single_fluid_box = {
    exclusive_mode = strict(
      "defines.control_behavior.single_fluid_box.exclusive_mode",
      { "none", "send_contents", "send_segment_contents" }
    ),
  },
}
local nth = {}
-- The filters each event was registered with.
local filters = {}
-- control.lua's on_init and on_configuration_changed handlers.
local lifecycle = {}
script = {
  on_event = function(event, handler, filter)
    handlers[event] = handler
    filters[event] = filter
  end,
  on_nth_tick = function(ticks, handler)
    nth[ticks] = handler
  end,
  on_init = function(handler)
    lifecycle.init = handler
  end,
  on_load = function() end,
  on_configuration_changed = function(handler)
    lifecycle.configuration_changed = handler
  end,
  register_on_object_destroyed = function() end,
}
remote = { add_interface = function() end }
local console = {}
commands = {
  add_command = function(name, _, handler)
    console[name] = handler
  end,
}
-- luacheck: globals settings
-- Runtime settings, as Factorio gives them: an unknown name fails, as `settings.global[name].value`
-- would on nil in game.
local SETTINGS = { ["jatz-freighter-fuel-capacity"] = 20, ["jatz-freighter-fuel-per-tile"] = 10 }
settings = {
  global = setmetatable({}, {
    __index = function(_, name)
      local value = SETTINGS[name]
      if value == nil then
        error("FAILED: no runtime-global setting " .. tostring(name), 2)
      end
      return { value = value }
    end,
  }),
}
prototypes = {
  decorative = {},
  item = {
    ["jatz-quinityn-freighter"] = { stack_size = 10, fuel_value = 0 },
    wood = { stack_size = 100, fuel_value = 2000000 },
    ["iron-plate"] = { stack_size = 100, fuel_value = 0 },
  },
  fluid = { water = { fuel_value = 0 } },
  -- As with one of the Mining Drones mods installed (tests/lua/logistics.lua checks without).
  entity = { ["mining-depot"] = { type = "assembling-machine" } },
  virtual_signal = { ["signal-A"] = {}, ["signal-each"] = {} },
  quality = { normal = {}, uncommon = {} },
}

local tiles = {}
local function cell(x, y)
  local key = x .. "," .. y
  tiles[key] = tiles[key] or { name = "grass-1" }
  return tiles[key]
end
local surface = { index = 1 }
function surface.get_tile(x, y)
  local tile = cell(x, y)
  return {
    valid = true,
    name = tile.name,
    collides_with = function()
      return false
    end,
  }
end
function surface.set_tiles(list)
  for _, tile in ipairs(list) do
    cell(tile.position[1], tile.position[2]).name = tile.name
  end
end
function surface.get_hidden_tile(position)
  return cell(position[1], position[2]).hidden
end
function surface.set_hidden_tile(position, name)
  cell(position[1], position[2]).hidden = name
end
function surface.get_double_hidden_tile(position)
  return cell(position[1], position[2]).double
end
function surface.set_double_hidden_tile(position, name)
  cell(position[1], position[2]).double = name
end
-- The engine's flood fill: tiles named in `names` joined side by side to `position`'s.
function surface.get_connected_tiles(position, names)
  local wanted = {}
  for _, name in ipairs(names) do
    wanted[name] = true
  end
  local function road(x, y)
    local tile = tiles[x .. "," .. y]
    return tile and wanted[tile.name]
  end
  local found, seen, queue = {}, {}, { { position[1], position[2] } }
  while #queue > 0 do
    local x, y = table.unpack(table.remove(queue))
    local key = x .. "," .. y
    if not seen[key] and road(x, y) then
      seen[key] = true
      found[#found + 1] = { x = x, y = y }
      for _, step in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        queue[#queue + 1] = { x + step[1], y + step[2] }
      end
    end
  end
  return found
end
function surface.find_decoratives_filtered()
  return {}
end
function surface.find_entities_filtered()
  return {}
end
-- Entities scripts create: here, liquid depots' truck chests (ten empty stacks).
surface.created = {}
function surface.create_entity(spec)
  local stacks = {
    get_item_count_filtered = function()
      return 0
    end,
  }
  for index = 1, 10 do
    stacks[index] = { valid_for_read = false }
  end
  local created = {
    valid = true,
    name = spec.name,
    position = spec.position,
    force = spec.force,
    surface = surface,
    get_inventory = function()
      return stacks
    end,
  }
  -- Called as the game's are, created.destroy() with no self.
  function created.destroy()
    created.valid = false
  end
  if spec.name == "jatz-fuel-depot-tank" then
    -- A Fuel depot's hidden tank, holding 300 water.
    created.direction = spec.direction
    created.held = { name = "water", amount = 300 }
    created.get_fluid = function(index)
      return index == 1 and created.held.amount > 0 and created.held or nil
    end
    created.get_fluid_capacity = function()
      return 25000
    end
    created.clear_fluid_inside = function()
      created.held.amount = 0
    end
  end
  surface.created[#surface.created + 1] = created
  return created
end

storage = {}
-- A one-slot script inventory, as far as the freighter slot's counts need.
local function script_inventory()
  local slot = { valid_for_read = false, count = 0 }
  return {
    valid = true,
    [1] = slot,
    get_item_count = function()
      return slot.count
    end,
    -- An ItemFilter of any quality, as the freighter counts ask.
    get_item_count_filtered = function(filter)
      assert(type(filter) == "table" and filter.name and not filter.quality, "an item filter of any quality")
      return slot.name == filter.name and slot.count or 0
    end,
    is_empty = function()
      return slot.count == 0
    end,
    resize = function() end,
  }
end
game = { tick = 0, surfaces = { [1] = surface }, create_inventory = script_inventory }

require("control")

local next_unit = 0
-- A provider depot at (x + 0.5, 0.5): unrotated, its loading zone is the tile (x, 2).
local function depot(x)
  next_unit = next_unit + 1
  return {
    valid = true,
    name = "jatz-provider-depot",
    unit_number = next_unit,
    position = { x = x + 0.5, y = 0.5 },
    direction = defines.direction.north,
    surface = surface,
    surface_index = 1,
    force = "player",
    force_index = 1,
    -- No wires, so no control behavior either.
    get_circuit_network = function()
      return nil
    end,
    get_control_behavior = function()
      return nil
    end,
    get_inventory = function()
      -- An empty chest of 48 stacks.
      local chest = {
        get_item_count = function()
          return 0
        end,
        get_item_count_filtered = function()
          return 0
        end,
        get_contents = function()
          return {}
        end,
      }
      for index = 1, 48 do
        chest[index] = { valid_for_read = false }
      end
      return chest
    end,
  }
end

local function fire(event, data)
  local handler = handlers[event]
  if not handler then
    error("FAILED: control.lua handles no " .. event, 2)
  end
  data.name = event
  handler(data)
end

local function check(name, condition)
  if not condition then
    error("FAILED: " .. name, 2)
  end
  print("ok   " .. name)
end

local function removed(entity)
  entity.valid = false
  fire("on_object_destroyed", { type = defines.target_type.entity, useful_id = entity.unit_number })
end

do -- Built, then removed: road laid, then the ground back.
  cell(0, 2).name = "concrete"
  local entity = depot(0)
  fire("on_built_entity", { entity = entity })
  check("building a depot lays its road", cell(0, 2).name == "jatz-depot-road")
  removed(entity)
  check("removing it puts back the concrete", cell(0, 2).name == "concrete")
end

do -- Turned: the road follows the loading zone.
  local entity = depot(10)
  fire("on_built_entity", { entity = entity })
  entity.direction = defines.direction.east -- loading zone moves to (8, 0)
  fire("on_player_rotated_entity", { entity = entity })
  check("turning a depot lays road at its new loading zone", cell(8, 0).name == "jatz-depot-road")
  check("and puts back the ground at the old one", cell(10, 2).name == "grass-1")
  entity.direction = defines.direction.south -- loading zone moves to (10, -2)
  fire("on_player_flipped_entity", { entity = entity })
  check("flipping does the same", cell(10, -2).name == "jatz-depot-road" and cell(8, 0).name == "grass-1")
end

do -- A player places a tile over the depot's road: it stays when the depot goes.
  local entity = depot(20)
  fire("on_built_entity", { entity = entity })
  cell(20, 2).name = "stone-path"
  fire("on_player_built_tile", {
    surface_index = 1,
    tile = { name = "stone-path" },
    tiles = { { old_tile = { name = "jatz-depot-road" }, position = { x = 20, y = 2 } } },
  })
  check("the depot gives the spot up to the player", storage.depot_roads[entity.unit_number] == false)
  removed(entity)
  check("a tile a player placed over depot road stays", cell(20, 2).name == "stone-path")
end

do -- A robot places one: the same.
  local entity = depot(25)
  fire("on_built_entity", { entity = entity })
  cell(25, 2).name = "concrete"
  fire("on_robot_built_tile", {
    surface_index = 1,
    tile = { name = "concrete" },
    tiles = { { old_tile = { name = "jatz-depot-road" }, position = { x = 25, y = 2 } } },
  })
  check("the depot gives the spot up to the robot's owner", storage.depot_roads[entity.unit_number] == false)
  removed(entity)
  check("a tile a robot placed over depot road stays", cell(25, 2).name == "concrete")
end

do -- A player mines the depot's road: the concrete under it comes back, not just the hidden tile.
  local spot = cell(30, 2)
  spot.name, spot.hidden = "concrete", "grass-1"
  local entity = depot(30)
  fire("on_built_entity", { entity = entity })
  spot.name = "grass-1" -- mining reveals the hidden tile
  fire("on_player_mined_tile", {
    surface_index = 1,
    tiles = { { old_tile = { name = "jatz-depot-road" }, position = { x = 30, y = 2 } } },
  })
  check("mining the depot's road by hand puts back the concrete", spot.name == "concrete")
  check("and gives the spot up", storage.depot_roads[entity.unit_number] == false)
  removed(entity)
  check("and removing the depot then leaves it", spot.name == "concrete")
end

do -- Another mod's script sets a tile over the depot's road: it stays when the depot goes.
  local entity = depot(40)
  fire("on_built_entity", { entity = entity })
  cell(40, 2).name = "refined-concrete"
  fire(
    "script_raised_set_tiles",
    { surface_index = 1, tiles = { { name = "refined-concrete", position = { 40, 2 } } } }
  )
  check("the depot gives the spot up to the script", storage.depot_roads[entity.unit_number] == false)
  removed(entity)
  check("a tile a script set over depot road stays", cell(40, 2).name == "refined-concrete")
end

do -- A request depot mined by a player, robot or platform hands its freighters to the miner.
  for _, event in ipairs({ "on_player_mined_entity", "on_robot_mined_entity", "on_space_platform_mined_entity" }) do
    local entity = depot(50)
    entity.name = "jatz-request-depot"
    fire("on_built_entity", { entity = entity })
    local slot = { name = "jatz-quinityn-freighter", count = 4, valid_for_read = true }
    function slot.clear()
      slot.count, slot.valid_for_read = 0, false
    end
    storage.depots[entity.unit_number].trucks = { valid = true, [1] = slot, destroy = function() end }
    local received = 0
    local buffer = {
      insert = function(stack)
        received = received + stack.count
        return stack.count
      end,
    }
    fire(event, { entity = entity, buffer = buffer })
    check(event .. " hands the freighters to the miner", received == 4 and not slot.valid_for_read)
    removed(entity)
  end
end

do -- The freighter slot's clicks: ghosts request freighters from robots; remote view moves nothing.
  local logistics = require("scripts.logistics")
  local calls = {}
  local removing = 0
  logistics.requested_freighters = function()
    return 0, removing
  end
  for _, name in ipairs({
    "request_freighters",
    "cancel_freighter_requests",
    "put_freighters",
    "take_freighters",
    "remove_freighters",
    "cancel_freighter_removal",
  }) do
    logistics[name] = function(_, a, b)
      calls[#calls + 1] = { name = name, a = a, b = b }
      return 0
    end
  end
  local entity = depot(60)
  entity.name = "jatz-request-depot"
  local player = { index = 1 }
  game.get_player = function()
    return player
  end
  storage.request_gui = { [1] = entity }
  local inner = {}
  local element = { name = "jatz_request_freighters", parent = { parent = inner } }
  local function click(controller, ghost, held, button)
    calls = {}
    player.controller_type = controller
    player.cursor_ghost = ghost and { name = { name = ghost } } or nil
    player.cursor_stack = held and { valid_for_read = true, name = held, count = 5 } or { valid_for_read = false }
    player.get_main_inventory = function()
      return {}
    end
    fire("on_gui_click", {
      element = element,
      player_index = 1,
      button = button or defines.mouse_button_type.left,
      shift = false,
    })
    return calls[1] or {}
  end
  local remote_view, character = defines.controllers.remote, defines.controllers.character
  local freighter = "jatz-quinityn-freighter"
  local call = click(remote_view, freighter)
  check(
    "remote view: a freighter ghost asks robots to fill the slot",
    call.name == "request_freighters" and call.a == nil
  )
  call = click(remote_view, freighter, nil, defines.mouse_button_type.right)
  check("remote view: right-click asks for one more", call.name == "request_freighters" and call.a == 1)
  call = click(remote_view)
  check("remote view: an empty cursor cancels the requests", call.name == "cancel_freighter_requests")
  call = click(remote_view, nil, freighter)
  check("remote view: nothing is moved by hand from afar", call.name == nil)
  call = click(character, freighter)
  check("in person, a freighter ghost requests too", call.name == "request_freighters")
  call = click(character, nil, freighter)
  check("in person, freighters in hand go into the slot", call.name == "put_freighters")
  local right = defines.mouse_button_type.right
  call = click(remote_view, nil, nil, right)
  check("remote view: right-click has robots take the freighters away", call.name == "remove_freighters")
  removing = 3
  call = click(remote_view, nil, nil, right)
  check("remote view: right-click again cancels that", call.name == "cancel_freighter_removal")

  -- Pipette over the slot picks up a freighter (or its ghost); elsewhere it's the game's own.
  local picked
  player.pipette = function(id, _, allow_ghost)
    picked = { id = id, ghost = allow_ghost }
  end
  prototypes.item[freighter] = { name = freighter, stack_size = 10 }
  fire("on_gui_hover", { element = element, player_index = 1 })
  fire("jatz-pipette", { player_index = 1 })
  check(
    "pipette over the slot picks up a freighter, or its ghost",
    picked and picked.id.name == freighter and picked.ghost
  )
  picked = nil
  fire("on_gui_leave", { element = element, player_index = 1 })
  fire("jatz-pipette", { player_index = 1 })
  check("pipette elsewhere is left to the game", picked == nil)
end

do -- Every status the dispatcher can report has a status light, one of the game's own.
  local lights = require("scripts.request-gui").lights
  local game_lights = {
    ["utility/status_working"] = true,
    ["utility/status_yellow"] = true,
    ["utility/status_not_working"] = true,
    ["utility/status_inactive"] = true,
  }
  for _, status in pairs(require("scripts.logistics").status) do
    check("status " .. status .. " has a status light", game_lights[lights[status]])
  end
end

-- A minimal GUI: elements with children by name, add and destroy.
local function element(spec, parent)
  local self = { children = {}, style = {}, parent = parent, valid = true }
  for key, value in pairs(spec or {}) do
    self[key] = value
  end
  function self.add(child_spec)
    local child = element(child_spec, self)
    self.children[#self.children + 1] = child
    if child.name then
      self[child.name] = child
    end
    return child
  end
  function self.destroy()
    self.valid = false
    for index, child in ipairs(parent.children) do
      if child == self then
        table.remove(parent.children, index)
      end
    end
    if self.name then
      parent[self.name] = nil
    end
  end
  return self
end

do -- A panel opened before an update that changed its layout is rebuilt, with its status light.
  local entity = depot(70)
  entity.name = "jatz-request-depot"
  fire("on_built_entity", { entity = entity })
  local relative = element()
  local player = { index = 2, valid = true, gui = { relative = relative } }
  game.get_player = function()
    return player
  end
  -- The old layout: a status label, no request row.
  relative.add({ name = "jatz_request_frame" }).add({}).add({ name = "jatz_request_status", caption = "old" })
  storage.request_gui = { [2] = entity }
  nth[30]()
  local row = relative.jatz_request_frame.children[1].request_row
  local light = row and row.jatz_request_status
  check("a panel from before the update is rebuilt", light ~= nil and light.type == "sprite")
  check("with its status light lit", light.sprite == "utility/status_inactive" and light.tooltip ~= nil)
end

do -- The line beside the freighter slot: how many are out on the road, always, and a green "+N"
  -- while N more are requested.
  local caption = require("scripts.request-gui").freighter_caption
  local none, some = caption(0, 0), caption(3, 0)
  check(
    "none out still says so, and nothing else",
    #none == 2 and none[2][1] == "jatz-gui.freighters-out" and none[2][2] == 0
  )
  check("three out", #some == 2 and some[2][2] == 3)
  local coming = caption(0, 4)
  check("four requested: a green +4 after it", #coming == 3 and coming[3] == "  [color=green]+4[/color]")
end

do -- Copy and paste: settings, blueprints, and depots built from blueprint ghosts.
  local logistics = require("scripts.logistics")
  prototypes.item.wood = { name = "wood", stack_size = 100 }
  local function request_depot(x)
    local entity = depot(x)
    entity.name = "jatz-request-depot"
    fire("on_built_entity", { entity = entity })
    return entity
  end
  local source, destination = request_depot(80), request_depot(90)
  assert(logistics.set_request(source, "wood", 7))
  storage.depots[source.unit_number].trucks = script_inventory()
  storage.depots[source.unit_number].trucks[1].count = 3

  -- Copy and Paste settings: the request, and robots asked for the source's 3 freighters.
  local matched
  logistics.match_freighters = function(entity, total)
    matched = { entity = entity, total = total }
    return total
  end
  fire("on_entity_settings_pasted", { source = source, destination = destination, player_index = 1 })
  local copied = logistics.get_request(destination)
  check("pasting settings copies the request", copied and copied.item == "wood" and copied.count == 7)
  check("and asks for the source's freighters", matched and matched.entity == destination and matched.total == 3)

  -- A blueprint of the source keeps its request (tag) and freighters (insert plan).
  local saved
  local blueprint = {
    valid = true,
    object_name = "LuaItemStack",
    valid_for_read = true,
    is_blueprint = true,
    get_blueprint_entities = function()
      return { { entity_number = 1, name = "jatz-request-depot", position = { x = 0, y = 0 } } }
    end,
    set_blueprint_entities = function(entities)
      saved = entities
    end,
  }
  game.get_player = function()
    return { index = 3 }
  end
  fire("on_player_setup_blueprint", {
    player_index = 3,
    stack = blueprint,
    mapping = {
      valid = true,
      get = function()
        return { [1] = source }
      end,
    },
  })
  local planned = saved and saved[1]
  check("a blueprint keeps the request as a tag", planned and planned.tags.jatz_request.item == "wood")
  check("and the freighters as a tag", planned.tags.jatz_freighters == 3)
  check("not as an insert plan, whose item parametrising would offer to swap", planned.items == nil)

  -- A depot built from that ghost takes the request from its tags.
  local built = depot(100)
  built.name = "jatz-request-depot"
  fire("on_robot_built_entity", { entity = built, tags = planned.tags })
  local request = logistics.get_request(built)
  check(
    "a depot built from a blueprint ghost has its request",
    request and request.item == "wood" and request.count == 7
  )

  -- Blueprint parametrisation: the request and the freighters also go in as request settings, a
  -- decider combinator at the depot's centre whose conditions the game can turn into parameters:
  -- the request compares its item to its amount, the freighters are a constant with no signal, so
  -- parametrising offers their number but no item.
  local function settings_entry(entries)
    for _, entry in pairs(entries) do
      if entry.name == "jatz-depot-settings" then
        return entry
      end
    end
  end
  local function conditions_of(entry)
    return entry and entry.control_behavior.decider_conditions.conditions
  end
  -- A condition's constant is an int32: the game refuses others.
  local function strict_set(entities)
    for _, entry in pairs(entities) do
      for _, condition in pairs(entry.control_behavior and entry.control_behavior.decider_conditions.conditions or {}) do
        assert(
          condition.constant >= -2147483648 and condition.constant <= 2147483647,
          "Count out of bounds: " .. condition.constant
        )
      end
    end
    saved = entities
  end
  blueprint.set_blueprint_entities = strict_set
  local settings = settings_entry(saved)
  local planned_conditions = conditions_of(settings)
  local wanted, freighter_condition =
    planned_conditions and planned_conditions[1], planned_conditions and planned_conditions[2]
  check(
    "a blueprint holds the request as request settings at the depot",
    wanted
      and wanted.first_signal.type == "item"
      and wanted.first_signal.name == "wood"
      and wanted.comparator == "="
      and wanted.constant == 7
      and settings.position.x == planned.position.x
      and settings.position.y == planned.position.y
      and settings.entity_number == 2
      and settings.tags.jatz_settings_of == "jatz-request-depot"
  )
  check(
    "and its freighters, as a number with no signal",
    freighter_condition
      and freighter_condition.first_signal == nil
      and freighter_condition.second_signal == nil
      and freighter_condition.constant == 3
  )
  -- Set up again, the blueprint keeps one, with the request as it is now.
  assert(logistics.set_request(source, "wood", 9))
  blueprint.get_blueprint_entities = function()
    return saved
  end
  logistics.setup_blueprint(blueprint, { [1] = source })
  local count, again = 0, nil
  for _, entry in pairs(saved) do
    if entry.name == "jatz-depot-settings" then
      count = count + 1
      again = conditions_of(entry)[1].constant
    end
  end
  check("setting it up again replaces them", #saved == 2 and count == 1 and again == 9)

  -- A request above a condition's int32 constant can't be a condition: the blueprint is still
  -- made, the request in the depot's tag and the settings' tag (so pasting over a depot sets it
  -- too), the settings' condition holding the freighters. Requests stop at a full chest (48 slots
  -- here), so only an item stacking past 44 million (as a mod can make) gets there.
  prototypes.item.crate = { name = "crate", stack_size = 1000000000 }
  assert(logistics.set_request(source, "crate", 9999999999))
  local made = pcall(logistics.setup_blueprint, blueprint, { [1] = source })
  local huge = settings_entry(saved)
  local huge_conditions = conditions_of(huge)
  check(
    "a request too large for a condition still blueprints, in tags",
    made
      and saved[1].tags.jatz_request.count == 9999999999
      and huge.tags.jatz_request.item == "crate"
      and huge.tags.jatz_request.count == 9999999999
      and #huge_conditions == 1
      and huge_conditions[1].first_signal == nil
      and huge_conditions[1].constant == 3
  )
  assert(logistics.set_request(source, "wood", 9))

  -- Every requesting depot gets settings, holding the depot as it is: a depot with no request and no
  -- freighters too, so pasting over the same depot always sets both.
  local bare = request_depot(105)
  logistics.setup_blueprint(blueprint, { [1] = bare })
  local bare_settings = settings_entry(saved)
  local bare_conditions = conditions_of(bare_settings)
  check(
    "a depot with no request and no freighters gets settings holding none",
    bare_settings
      and #bare_conditions == 1
      and bare_conditions[1].first_signal == nil
      and bare_conditions[1].constant == 0
      and bare_settings.tags.jatz_settings_of == "jatz-request-depot"
      and bare_settings.tags.jatz_request == nil
  )

  -- Request settings as built: a ghost (or, at once, the combinator itself) whose decider
  -- parameters read the request and the freighters, either missing, in either order, and whose
  -- tags name the depot they were made from (`made_from`, a request depot unless given; false for
  -- settings from before, without it). Strict: only `parameters` reads them, as
  -- LuaDeciderCombinatorControlBehavior gives them, and a real one has no tags to read (only its
  -- build event's).
  prototypes.item["iron-plate"] = { name = "iron-plate", stack_size = 100 }
  local function placed_settings(x, item, count_, freighters, force, extra_tags, made_from)
    local tags = {}
    if made_from ~= false then
      tags.jatz_settings_of = made_from or "jatz-request-depot"
    end
    for name, value in pairs(extra_tags or {}) do
      tags[name] = value
    end
    local conditions = {}
    if freighters then
      conditions[#conditions + 1] = { comparator = "=", constant = freighters, compare_type = "or" }
    end
    if item then
      table.insert(conditions, 1, {
        first_signal = { type = "item", name = item },
        comparator = "=",
        constant = count_,
        compare_type = "or",
      })
    end
    local entity = {
      valid = true,
      name = "entity-ghost",
      type = "entity-ghost",
      ghost_name = "jatz-depot-settings",
      position = { x = x, y = 0.5 },
      surface = surface,
      force = force or "player",
      tags = tags,
      get_control_behavior = function()
        return { parameters = { conditions = conditions, outputs = {}, else_outputs = {} } }
      end,
    }
    function entity.destroy()
      entity.valid = false
    end
    return entity
  end
  local function at_once(entity)
    entity.name, entity.type, entity.ghost_name = "jatz-depot-settings", "decider-combinator", nil
    entity.event_tags, entity.tags = entity.tags, nil
    return entity
  end
  -- Entities at a spot, as find_entities_filtered gives them: by position, name, ghost name and
  -- force when asked.
  local search = surface.find_entities_filtered
  local function standing(x, entities)
    surface.find_entities_filtered = function(filter)
      local found = {}
      if filter.position and filter.position.x == x + 0.5 then
        for _, entity in ipairs(entities) do
          if
            entity.valid
            and (filter.name == nil or entity.name == filter.name)
            and (filter.ghost_name == nil or entity.ghost_name == filter.ghost_name)
            and (filter.force == nil or entity.force == filter.force)
          then
            found[#found + 1] = entity
          end
        end
      end
      return found
    end
  end

  -- The settings' ghost, parametrised to 50 iron plates and 6 freighters, hands both to the
  -- depot's ghost placed with it, keeping its other tags, and goes.
  local ghost = {
    valid = true,
    name = "entity-ghost",
    type = "entity-ghost",
    ghost_name = "jatz-request-depot",
    position = { x = 120.5, y = 0.5 },
    force = "player",
    tags = { jatz_request = { item = "wood", count = 9 }, jatz_freighters = 3, jatz_from_buffers = true },
  }
  local ghost_settings = placed_settings(120.5, "iron-plate", 50, 6)
  standing(120, { ghost, ghost_settings })
  fire("on_built_entity", { entity = ghost_settings, player_index = 3 })
  surface.find_entities_filtered = search
  check(
    "parametrised request settings hand their request and freighters to the depot's ghost",
    ghost.tags.jatz_request.item == "iron-plate"
      and ghost.tags.jatz_request.count == 50
      and ghost.tags.jatz_freighters == 6
      and ghost.tags.jatz_from_buffers == true
  )
  check("and go", not ghost_settings.valid)
  local from_ghost = depot(120)
  from_ghost.name = "jatz-request-depot"
  matched = nil
  fire("on_robot_built_entity", { entity = from_ghost, tags = ghost.tags })
  request = logistics.get_request(from_ghost)
  check("the depot built from it requests that", request and request.item == "iron-plate" and request.count == 50)
  check("and asks for that many freighters", matched and matched.entity == from_ghost and matched.total == 6)

  -- Built at once (as in the editor), the depot takes the request and freighters from its settings
  -- beside it rather than its tags, whichever event comes first.
  local function built_at_once(x, settings_first, tags)
    local entity = depot(x)
    entity.name = "jatz-request-depot"
    local real_settings = at_once(placed_settings(x + 0.5, "iron-plate", 40, 5))
    standing(x, { entity, real_settings })
    matched = nil
    if settings_first then
      fire("on_built_entity", { entity = real_settings, player_index = 3, tags = real_settings.event_tags })
    end
    fire("on_built_entity", { entity = entity, tags = tags })
    if not settings_first then
      -- The depot's build event leaves them (it can't read their tags) to their own.
      assert(real_settings.valid)
      fire("on_built_entity", { entity = real_settings, player_index = 3, tags = real_settings.event_tags })
    end
    surface.find_entities_filtered = search
    return entity, real_settings
  end
  local old_tags = { jatz_request = { item = "wood", count = 9 }, jatz_freighters = 3 }
  local first, first_settings = built_at_once(130, false, old_tags)
  request = logistics.get_request(first)
  check(
    "a depot built at once takes its settings' request and freighters",
    request and request.item == "iron-plate" and request.count == 40 and matched and matched.total == 5
  )
  check("and they go", not first_settings.valid)
  local second = built_at_once(140, true, old_tags)
  request = logistics.get_request(second)
  check(
    "and keeps them when the settings' build event comes first",
    request and request.item == "iron-plate" and request.count == 40 and matched and matched.total == 5
  )
  -- Settings' ghost placed with no build event (a script's build_blueprint without raise_built),
  -- and the depot built over its ghost without tags (a player building over a ghost passes none
  -- on): the depot still takes them, and they go.
  local untagged = depot(150)
  untagged.name = "jatz-request-depot"
  local quiet_settings = placed_settings(150.5, "iron-plate", 40, 5)
  standing(150, { untagged, quiet_settings })
  matched = nil
  fire("on_built_entity", { entity = untagged, player_index = 3 })
  surface.find_entities_filtered = search
  request = logistics.get_request(untagged)
  check(
    "a depot built without tags takes its settings' ghost's request and freighters",
    request and request.item == "iron-plate" and request.count == 40 and matched and matched.total == 5
  )
  check("and the ghost goes", not quiet_settings.valid)

  -- Another force's settings (pasted over its depot, or its ghost) change nothing of the player's.
  local guarded = depot(160)
  guarded.name = "jatz-request-depot"
  fire("on_built_entity", { entity = guarded })
  assert(logistics.set_request(guarded, "wood", 9))
  local foreign = placed_settings(160.5, "iron-plate", 50, 6, "enemy")
  standing(160, { guarded, foreign })
  matched = nil
  fire("on_built_entity", { entity = foreign, player_index = 3 })
  request = logistics.get_request(guarded)
  check(
    "another force's request settings leave a depot alone",
    request and request.item == "wood" and request.count == 9 and matched == nil
  )
  local beside = depot(170)
  beside.name = "jatz-request-depot"
  local foreign_beside = at_once(placed_settings(170.5, "iron-plate", 40, 5, "enemy"))
  standing(170, { beside, foreign_beside })
  fire("on_built_entity", { entity = beside, tags = old_tags })
  surface.find_entities_filtered = search
  request = logistics.get_request(beside)
  check(
    "and a depot built beside them doesn't take them",
    request and request.item == "wood" and request.count == 9 and foreign_beside.valid
  )

  -- Pasted over a depot already built: a blueprint with no freighters matches none (cancelling
  -- requests for more, as Copy and Paste settings does), and a request too large for a condition
  -- comes from the settings' tag.
  local pasted_over = depot(180)
  pasted_over.name = "jatz-request-depot"
  fire("on_built_entity", { entity = pasted_over })
  local none = placed_settings(180.5, "iron-plate", 20, 0)
  standing(180, { pasted_over, none })
  matched = nil
  fire("on_built_entity", { entity = none, player_index = 3 })
  request = logistics.get_request(pasted_over)
  check(
    "settings with no freighters, pasted over a depot, match none",
    request and request.item == "iron-plate" and matched and matched.entity == pasted_over and matched.total == 0
  )
  local oversized = placed_settings(180.5, nil, nil, 3, nil, { jatz_request = { item = "crate", count = 9999999999 } })
  standing(180, { pasted_over, oversized })
  matched = nil
  fire("on_built_entity", { entity = oversized, player_index = 3 })
  surface.find_entities_filtered = search
  request = logistics.get_request(pasted_over)
  check(
    "and a request too large for a condition comes from their tag",
    request and request.item == "crate" and request.count == 9999999999 and matched and matched.total == 3
  )

  -- Settings of a depot with no request clear one: pasted over a depot asking for wood, handed to a
  -- ghost tagged with one, or built at once with it (either event first, its tags still naming the
  -- old request). Copilot's and Pullfrog's review of 4a0d9b9.
  assert(logistics.set_request(pasted_over, "wood", 7))
  local empty = placed_settings(180.5, nil, nil, 0)
  standing(180, { pasted_over, empty })
  matched = nil
  fire("on_built_entity", { entity = empty, player_index = 3 })
  surface.find_entities_filtered = search
  check(
    "settings with no request, pasted over a depot, clear its request",
    logistics.get_request(pasted_over) == nil and matched and matched.total == 0
  )
  local tagged_ghost = {
    valid = true,
    name = "entity-ghost",
    type = "entity-ghost",
    ghost_name = "jatz-request-depot",
    position = { x = 190.5, y = 0.5 },
    force = "player",
    tags = { jatz_request = { item = "wood", count = 9 }, jatz_freighters = 3 },
  }
  local empty_for_ghost = placed_settings(190.5, nil, nil, 2)
  standing(190, { tagged_ghost, empty_for_ghost })
  fire("on_built_entity", { entity = empty_for_ghost, player_index = 3 })
  surface.find_entities_filtered = search
  check(
    "and a ghost's request tag",
    tagged_ghost.tags.jatz_request == nil and tagged_ghost.tags.jatz_freighters == 2 and not empty_for_ghost.valid
  )
  for _, settings_first in ipairs({ false, true }) do
    local x = settings_first and 210 or 200
    local cleared = depot(x)
    cleared.name = "jatz-request-depot"
    local real_empty = at_once(placed_settings(x + 0.5, nil, nil, 0))
    standing(x, { cleared, real_empty })
    if settings_first then
      fire("on_built_entity", { entity = real_empty, player_index = 3, tags = real_empty.event_tags })
    end
    fire("on_built_entity", { entity = cleared, tags = old_tags })
    if not settings_first then
      fire("on_built_entity", { entity = real_empty, player_index = 3, tags = real_empty.event_tags })
    end
    surface.find_entities_filtered = search
    check(
      "and a depot built at once with them" .. (settings_first and ", their event first" or ""),
      logistics.get_request(cleared) == nil and not real_empty.valid
    )
  end

  -- Only the depot they were made from takes them: a request depot's settings left by a forced
  -- paste over a buffer depot, beside a buffer depot's ghost, or at the centre of a buffer depot
  -- built from its ghost change nothing there, and go (Copilot's and Pullfrog's review of
  -- 4a0d9b9). Settings from before, naming no depot, are ignored.
  local other_kind = depot(220)
  other_kind.name = "jatz-buffer-depot"
  fire("on_built_entity", { entity = other_kind })
  assert(logistics.set_request(other_kind, "wood", 9))
  local wrong = placed_settings(220.5, "iron-plate", 50, 6)
  standing(220, { other_kind, wrong })
  matched = nil
  fire("on_built_entity", { entity = wrong, player_index = 3 })
  request = logistics.get_request(other_kind)
  check(
    "a request depot's settings leave a buffer depot alone",
    request.item == "wood" and request.count == 9 and matched == nil and not wrong.valid
  )
  local buffer_ghost = {
    valid = true,
    name = "entity-ghost",
    type = "entity-ghost",
    ghost_name = "jatz-buffer-depot",
    position = { x = 230.5, y = 0.5 },
    force = "player",
    tags = { jatz_request = { item = "wood", count = 9 }, jatz_freighters = 3 },
  }
  local wrong_for_ghost = placed_settings(230.5, "iron-plate", 50, 6)
  standing(230, { buffer_ghost, wrong_for_ghost })
  fire("on_built_entity", { entity = wrong_for_ghost, player_index = 3 })
  check(
    "and its ghost",
    buffer_ghost.tags.jatz_request.item == "wood"
      and buffer_ghost.tags.jatz_freighters == 3
      and not wrong_for_ghost.valid
  )
  local built_buffer = depot(240)
  built_buffer.name = "jatz-buffer-depot"
  local wrong_at_centre = placed_settings(240.5, "iron-plate", 50, 6)
  standing(240, { built_buffer, wrong_at_centre })
  matched = nil
  fire("on_robot_built_entity", { entity = built_buffer, tags = old_tags })
  surface.find_entities_filtered = search
  request = logistics.get_request(built_buffer)
  check(
    "and a buffer depot built beside their ghost",
    request.item == "wood" and request.count == 9 and matched and matched.total == 3 and not wrong_at_centre.valid
  )
  local from_before = placed_settings(220.5, "iron-plate", 50, 6, nil, nil, false)
  standing(220, { other_kind, from_before })
  matched = nil
  fire("on_built_entity", { entity = from_before, player_index = 3 })
  request = logistics.get_request(other_kind)
  check(
    "settings naming no depot are ignored, and go",
    request.item == "wood" and matched == nil and not from_before.valid
  )
  surface.find_entities_filtered = search

  -- A parametrised request the depot can't take (a fluid for an item depot) has no say: the ghost
  -- keeps the request it was blueprinted with, and still takes the freighters.
  local kept_ghost = {
    valid = true,
    name = "entity-ghost",
    type = "entity-ghost",
    ghost_name = "jatz-request-depot",
    position = { x = 250.5, y = 0.5 },
    force = "player",
    tags = { jatz_request = { item = "wood", count = 9 }, jatz_freighters = 3 },
  }
  local fluid_for_items = placed_settings(250.5, "water", 500, 4)
  standing(250, { kept_ghost, fluid_for_items })
  fire("on_built_entity", { entity = fluid_for_items, player_index = 3 })
  surface.find_entities_filtered = search
  check(
    "a request the depot can't take leaves its ghost's",
    kept_ghost.tags.jatz_request.item == "wood" and kept_ghost.tags.jatz_freighters == 4
  )
end

do -- Freighters moved out of the player's inventory into a request depot (ctrl+ or shift+click in
  -- its window, ctrl+click on it in the world) go to its slot; unrelated inventory changes don't.
  local logistics = require("scripts.logistics")
  local taken
  logistics.take_in_freighters = function(entity, give_back, moved)
    taken = { entity = entity, give_back = give_back, moved = moved }
    return 0, 0
  end
  local entity = depot(110)
  entity.name = "jatz-request-depot"
  local pocket_count = 12
  local pockets = {}
  logistics.count_freighters = function(inventory_)
    return inventory_ == pockets and pocket_count or 0
  end
  local player = {
    index = 4,
    valid = true,
    get_main_inventory = function()
      return pockets
    end,
  }
  game.get_player = function()
    return player
  end
  local function changed(count)
    taken, pocket_count = nil, count
    fire("on_player_main_inventory_changed", { player_index = 4 })
  end
  -- The depot's window is open, and the player's 12 freighters were counted when it opened.
  storage.request_gui = { [4] = entity }
  storage.pocket_freighters = { [4] = 12 }
  changed(2)
  check(
    "ctrl+click of 10 freighters into an open depot takes those 10 in, overflow back to the player",
    taken and taken.entity == entity and taken.moved == 10 and taken.give_back == pockets
  )
  changed(5)
  check("freighters coming into the inventory take nothing in", taken == nil)
  changed(5)
  check("nor does an unrelated change", taken == nil)
  -- Ctrl+click on a depot in the world: the one the player points at.
  storage.request_gui = {}
  player.selected = entity
  fire("on_selected_entity_changed", { player_index = 4 })
  changed(1)
  check(
    "ctrl+click of 4 freighters onto a depot in the world takes those in",
    taken and taken.entity == entity and taken.moved == 4 and taken.give_back == pockets
  )
  player.selected = nil
  changed(0)
  check("with no depot open or pointed at, nothing", taken == nil)
end

do -- /jatz-freighters describes the open request depot's freighter slot.
  local logistics = require("scripts.logistics")
  local entity = depot(120)
  entity.name = "jatz-request-depot"
  fire("on_built_entity", { entity = entity })
  local printed
  local player = {
    index = 5,
    opened = entity,
    print = function(text)
      printed = text
    end,
  }
  entity.object_name = "LuaEntity"
  game.get_player = function()
    return player
  end
  logistics.describe_freighters = function(described)
    return described == entity and "described" or nil
  end
  check("the command is registered", console["jatz-freighters"] ~= nil)
  console["jatz-freighters"]({ player_index = 5 })
  check("it prints the open depot's freighter slot", printed == "described")
end

do -- A freighter placed from the cursor into an open request depot goes to its slot at once;
  -- moving freighters between inventory and cursor takes nothing in.
  local logistics = require("scripts.logistics")
  local taken
  logistics.take_in_freighters = function(entity, _, moved)
    taken = { entity = entity, moved = moved }
    return moved, 0
  end
  local entity = depot(130)
  entity.name = "jatz-request-depot"
  local pockets, in_pockets = {}, 5
  logistics.count_freighters = function(inventory_)
    return inventory_ == pockets and in_pockets or 0
  end
  local cursor = { valid_for_read = false }
  local player = {
    index = 6,
    valid = true,
    gui = { relative = {} },
    cursor_stack = cursor,
    get_main_inventory = function()
      return pockets
    end,
  }
  game.get_player = function()
    return player
  end
  storage.request_gui = { [6] = entity }
  storage.pocket_freighters = { [6] = 5 }
  -- Picked up into the cursor: still carried.
  in_pockets, taken = 0, nil
  cursor.valid_for_read, cursor.name, cursor.count = true, "jatz-quinityn-freighter", 5
  fire("on_player_main_inventory_changed", { player_index = 6 })
  fire("on_player_cursor_stack_changed", { player_index = 6 })
  check("moving freighters from inventory to cursor takes nothing in", taken == nil)
  -- One placed into the depot's chest from the cursor.
  cursor.count = 4
  fire("on_player_cursor_stack_changed", { player_index = 6 })
  check("one placed from the cursor goes to the slot at once", taken and taken.entity == entity and taken.moved == 1)
end

do -- The "request from buffer depots" checkbox, and Copy and Paste settings carrying it.
  local logistics = require("scripts.logistics")
  local function requesting(x, name)
    local entity = depot(x)
    entity.name = name
    fire("on_built_entity", { entity = entity })
    return entity
  end
  local source, destination = requesting(160, "jatz-request-depot"), requesting(170, "jatz-request-depot")
  local player = { index = 10, valid = true }
  game.get_player = function()
    return player
  end
  storage.request_gui = { [10] = source }
  fire("on_gui_checked_state_changed", {
    player_index = 10,
    element = { name = "jatz_request_from_buffers", state = true },
  })
  check("ticking the checkbox has the depot request from buffers", logistics.get_from_buffers(source))
  fire("on_entity_settings_pasted", { source = source, destination = destination, player_index = 10 })
  check("Copy and Paste settings carries it", logistics.get_from_buffers(destination))
  local buffer = requesting(180, "jatz-buffer-depot")
  check("buffer depots take requests too", logistics.set_request(buffer, "wood", 5))
  check("but not the request-from-buffers setting", not logistics.set_from_buffers(buffer, true))
end

do -- "Request from buffer depots" survives a blueprint even with no item requested.
  local logistics = require("scripts.logistics")
  local entity = depot(190)
  entity.name = "jatz-request-depot"
  fire("on_built_entity", { entity = entity })
  assert(logistics.set_from_buffers(entity, true))
  local saved
  local blueprint = {
    valid = true,
    object_name = "LuaItemStack",
    valid_for_read = true,
    is_blueprint = true,
    get_blueprint_entities = function()
      return { { entity_number = 1, name = "jatz-request-depot", position = { x = 0, y = 0 } } }
    end,
    set_blueprint_entities = function(entities)
      saved = entities
    end,
  }
  logistics.setup_blueprint(blueprint, { [1] = entity })
  check("the setting is kept with no item requested", saved[1].tags and saved[1].tags.jatz_from_buffers == true)
  local built = depot(200)
  built.name = "jatz-request-depot"
  fire("on_robot_built_entity", { entity = built, tags = saved[1].tags })
  check("and restored on the depot built from it", logistics.get_from_buffers(built))
end

do -- The "full loads only" checkbox, on buffer and request depots alike, carried by Copy and Paste
  -- settings and blueprints.
  local logistics = require("scripts.logistics")
  local function requesting(x, name)
    local entity = depot(x)
    entity.name = name
    fire("on_built_entity", { entity = entity })
    return entity
  end
  local source, destination = requesting(210, "jatz-buffer-depot"), requesting(220, "jatz-request-depot")
  check("off on a new depot", not logistics.get_full_loads(source))
  local player = { index = 11, valid = true }
  game.get_player = function()
    return player
  end
  storage.request_gui = { [11] = source }
  fire("on_gui_checked_state_changed", {
    player_index = 11,
    element = { name = "jatz_request_full_loads", state = true },
  })
  check("ticking the checkbox has a buffer depot send full loads only", logistics.get_full_loads(source))
  fire("on_entity_settings_pasted", { source = source, destination = destination, player_index = 11 })
  check("Copy and Paste settings carries it to a request depot", logistics.get_full_loads(destination))
  local saved
  local blueprint = {
    valid = true,
    object_name = "LuaItemStack",
    valid_for_read = true,
    is_blueprint = true,
    get_blueprint_entities = function()
      return { { entity_number = 1, name = "jatz-request-depot", position = { x = 0, y = 0 } } }
    end,
    set_blueprint_entities = function(entities)
      saved = entities
    end,
  }
  logistics.setup_blueprint(blueprint, { [1] = destination })
  check("a blueprint keeps it", saved[1].tags and saved[1].tags.jatz_full_loads == true)
  local built = requesting(230, "jatz-request-depot")
  fire("on_robot_built_entity", { entity = built, tags = saved[1].tags })
  check("and the depot built from it sends full loads only", logistics.get_full_loads(built))
  storage.request_gui = { [11] = built }
  fire("on_gui_checked_state_changed", {
    player_index = 11,
    element = { name = "jatz_request_full_loads", state = false },
  })
  check("unticking it turns it off", not logistics.get_full_loads(built))
  local provider = requesting(240, "jatz-provider-depot")
  check("provider depots have no such setting", not logistics.set_full_loads(provider, true))
end

do -- The priority slider: provider depots get a panel with it and their circuit condition; buffer
  -- depots have it above their request; request depots have none.
  local logistics = require("scripts.logistics")
  local relative = element()
  local player = { index = 11, valid = true, gui = { relative = relative } }
  game.get_player = function()
    return player
  end
  -- Only this player's panel: the fake has one player for every index.
  storage.request_gui = {}
  local provider = depot(210)
  fire("on_built_entity", { entity = provider })
  fire("on_gui_opened", { player_index = 11, entity = provider })
  local frame = relative.jatz_request_frame
  local row = frame and frame.children[1].priority_row
  check("a provider depot's window gets a panel", frame and frame.caption[1] == "jatz-gui.provider-title")
  local children = frame.children[1].children
  check(
    "with the priority slider, then only its circuit condition",
    row and children[1] == row and #children == 5 and children[5] == frame.children[1].condition_row
  )
  local slider = row.jatz_depot_priority
  check(
    "a slider from 1 to 10 in whole steps",
    slider.type == "slider"
      and slider.minimum_value == 1
      and slider.maximum_value == 10
      and slider.value_step == 1
      and slider.discrete_values
  )
  check("showing the depot's priority", slider.slider_value == 5 and row.jatz_depot_priority_value.caption == "5")
  slider.slider_value = 8
  fire("on_gui_value_changed", { player_index = 11, element = slider })
  check("moving it sets the priority", logistics.get_priority(provider) == 8)
  check("and the number beside it", row.jatz_depot_priority_value.caption == "8")
  logistics.set_priority(provider, 3)
  nth[30]()
  check("the open panel isn't rebuilt every refresh", relative.jatz_request_frame == frame)
  check("but follows a priority changed elsewhere", slider.slider_value == 3)

  player.get_main_inventory = function() end
  local buffer = depot(220)
  buffer.name = "jatz-buffer-depot"
  fire("on_built_entity", { entity = buffer })
  fire("on_gui_opened", { player_index = 11, entity = buffer })
  local inner = relative.jatz_request_frame.children[1]
  check("a buffer depot's panel has its request", inner.request_row and inner.request_row.jatz_request_status)
  check("and a priority slider", inner.priority_row and inner.priority_row.jatz_depot_priority)
  check("above the request", inner.children[1] == inner.priority_row and inner.children[2] == inner.request_row)
  inner.priority_row.jatz_depot_priority.slider_value = 2
  fire("on_gui_value_changed", { player_index = 11, element = inner.priority_row.jatz_depot_priority })
  check("which sets the buffer depot's priority", logistics.get_priority(buffer) == 2)
  nth[30]()
  check("a buffer panel isn't rebuilt either", relative.jatz_request_frame.children[1] == inner)

  local request = depot(230)
  request.name = "jatz-request-depot"
  fire("on_built_entity", { entity = request })
  fire("on_gui_opened", { player_index = 11, entity = request })
  inner = relative.jatz_request_frame.children[1]
  check("a request depot's panel has no priority", inner.request_row and not inner.priority_row)
  nth[30]()
  check("and isn't rebuilt for lacking one", relative.jatz_request_frame.children[1] == inner)
  local chooser, amount = inner.request_row.jatz_request_item, inner.request_row.jatz_request_count
  chooser.elem_value = "iron-plate"
  fire("on_gui_elem_changed", { player_index = 11, element = chooser })
  check("an item chosen starts at one stack", logistics.get_request(request).count == 100 and amount.text == "100")
  amount.text = "1000000"
  fire("on_gui_text_changed", { player_index = 11, element = amount, text = amount.text })
  check(
    "an amount above its 48 stacks is 48 stacks, in the field too",
    logistics.get_request(request).count == 4800 and amount.text == "4800"
  )
  assert(logistics.set_request(request, nil))
  local full_loads = inner.jatz_request_full_loads
  check("it has the full-loads-only checkbox, unticked", full_loads and full_loads.state == false)
  logistics.set_full_loads(request, true)
  nth[30]()
  check(
    "which follows the setting changed elsewhere (another player, a paste, a mod)",
    relative.jatz_request_frame.children[1] == inner and full_loads.state == true
  )
  local from_buffers = inner.jatz_request_from_buffers
  check("it has the request-from-buffers checkbox, unticked", from_buffers and from_buffers.state == false)
  logistics.set_from_buffers(request, true)
  nth[30]()
  check(
    "which follows the setting changed elsewhere too",
    relative.jatz_request_frame.children[1] == inner and from_buffers.state == true
  )
  logistics.set_from_buffers(request, false)
  nth[30]()
  check("and back off", from_buffers.state == false)
  -- A panel left open across the update that added the checkbox: rebuilt with it.
  full_loads.destroy()
  nth[30]()
  inner = relative.jatz_request_frame.children[1]
  check(
    "a panel from before the checkbox is rebuilt with it, ticked as the depot is",
    inner.jatz_request_full_loads and inner.jatz_request_full_loads.state == true
  )
end

do -- Priority in blueprints: kept for provider and buffer depots, and restored when built.
  local logistics = require("scripts.logistics")
  local provider, plain, buffer = depot(240), depot(250), depot(260)
  buffer.name = "jatz-buffer-depot"
  for _, entity in ipairs({ provider, plain, buffer }) do
    fire("on_built_entity", { entity = entity })
  end
  assert(logistics.set_priority(provider, 8) and logistics.set_priority(buffer, 2))
  assert(logistics.set_request(buffer, "wood", 5))
  local saved
  local blueprint = {
    valid = true,
    object_name = "LuaItemStack",
    valid_for_read = true,
    is_blueprint = true,
    get_blueprint_entities = function()
      return {
        { entity_number = 1, name = "jatz-provider-depot", position = { x = 0, y = 0 } },
        { entity_number = 2, name = "jatz-provider-depot", position = { x = 4, y = 0 } },
        { entity_number = 3, name = "jatz-buffer-depot", position = { x = 8, y = 0 } },
      }
    end,
    set_blueprint_entities = function(entities)
      saved = entities
    end,
  }
  logistics.setup_blueprint(blueprint, { provider, plain, buffer })
  check("a provider's priority is kept", saved[1].tags and saved[1].tags.jatz_priority == 8)
  check("one left at 5 has no tags", saved[2].tags == nil)
  check(
    "a buffer depot keeps its priority and its request",
    saved[3].tags and saved[3].tags.jatz_priority == 2 and saved[3].tags.jatz_request.item == "wood"
  )
  local built, built_buffer, odd = depot(270), depot(280), depot(290)
  built_buffer.name = "jatz-buffer-depot"
  fire("on_robot_built_entity", { entity = built, tags = saved[1].tags })
  fire("on_robot_built_entity", { entity = built_buffer, tags = saved[3].tags })
  fire("on_robot_built_entity", { entity = odd, tags = { jatz_priority = "high" } })
  check("a provider built from it gets the priority", logistics.get_priority(built) == 8)
  check("so does a buffer depot", logistics.get_priority(built_buffer) == 2)
  check("a malformed priority tag is ignored", logistics.get_priority(odd) == 5)
end

do -- Liquid depots: the same panels, beside the storage tank window, choosing a fluid.
  local logistics = require("scripts.logistics")
  local relative = element()
  local player = { index = 12, valid = true, gui = { relative = relative }, get_main_inventory = function() end }
  game.get_player = function()
    return player
  end
  storage.request_gui = {}
  local function liquid(x, name)
    local entity = depot(x)
    entity.name = name
    entity.get_fluid_count = function()
      return 0
    end
    entity.get_fluid_contents = function()
      return {}
    end
    entity.get_fluid_capacity = function()
      return 25000
    end
    fire("on_built_entity", { entity = entity })
    return entity
  end
  local request = liquid(300, "jatz-liquid-request-depot")
  check("a liquid request depot gets a truck chest", surface.created[#surface.created].name == "jatz-truck-chest")
  fire("on_gui_opened", { player_index = 12, entity = request })
  local frame = relative.jatz_request_frame
  -- Factorio 2.1 has no storage_tank_gui (removed in 2.1): storage tanks open the pipe window.
  check(
    "its panel is beside the storage tank's window, a pipe window",
    frame.anchor.gui == "relative_gui_type.pipe_gui"
  )
  check("titled for a liquid request depot", frame.caption[1] == "jatz-gui.liquid-request-title")
  local inner = frame.children[1]
  local chooser = inner.request_row.jatz_request_item
  check("it chooses a fluid", chooser.elem_type == "fluid")
  -- FluidPrototypeFilter's filters in the 2.1 API; anything else is an error when the panel opens.
  local fluid_filters = {
    hidden = true,
    name = true,
    subgroup = true,
    ["default-temperature"] = true,
    ["max-temperature"] = true,
    ["heat-capacity"] = true,
    ["fuel-value"] = true,
    ["emissions-multiplier"] = true,
    ["gas-temperature"] = true,
  }
  local valid, parameters_hidden = true, false
  for _, filter in ipairs(chooser.elem_filters) do
    valid = valid and fluid_filters[filter.filter] == true
    parameters_hidden = parameters_hidden
      or (filter.filter == "subgroup" and filter.subgroup == "parameters" and filter.invert)
  end
  check("with only filters fluids have", valid)
  check("leaving out blueprint parameter fluids", parameters_hidden)
  check("with the request-from-buffers checkbox", inner.jatz_request_from_buffers ~= nil)
  check("and the full-loads-only checkbox", inner.jatz_request_full_loads ~= nil)
  check("and no priority", inner.priority_row == nil)
  check("and a freighter slot", inner.freighter_row and inner.freighter_row.jatz_request_freighters)
  check(
    "and its freighters' fuel under it",
    inner.freighter_fuel
      and inner.freighter_fuel.visible
      and inner.freighter_fuel.caption[1] == "jatz-gui.freighter-fuel-none"
      and inner.freighter_fuel.tooltip[1] == "jatz-gui.freighter-fuel-tooltip"
  )
  chooser.elem_value = "water"
  fire("on_gui_elem_changed", { player_index = 12, element = chooser })
  local request_set = logistics.get_request(request)
  check("a fluid chosen starts at 1000", request_set and request_set.item == "water" and request_set.count == 1000)
  local amount = inner.request_row.jatz_request_count
  amount.text = "1000000"
  fire("on_gui_text_changed", { player_index = 12, element = amount, text = amount.text })
  check(
    "an amount above the tank's size is its size, in the field too",
    logistics.get_request(request).count == 25000 and amount.text == "25000"
  )

  local buffer = liquid(310, "jatz-liquid-buffer-depot")
  fire("on_gui_opened", { player_index = 12, entity = buffer })
  inner = relative.jatz_request_frame.children[1]
  check("a liquid buffer depot has its priority above its request", inner.children[1] == inner.priority_row)
  local provider = liquid(320, "jatz-liquid-provider-depot")
  fire("on_gui_opened", { player_index = 12, entity = provider })
  frame = relative.jatz_request_frame
  check(
    "a liquid provider depot gets the priority panel",
    frame.caption[1] == "jatz-gui.liquid-provider-title" and frame.children[1].priority_row ~= nil
  )
  nth[30]()
  check("which refresh leaves alone", relative.jatz_request_frame == frame)

  -- Blueprints: the request and freighters as tags, no insert plan (a storage tank has no chest);
  -- the depot built from it asks robots for its freighters into its truck chest.
  local saved
  local blueprint = {
    valid = true,
    object_name = "LuaItemStack",
    valid_for_read = true,
    is_blueprint = true,
    get_blueprint_entities = function()
      return { { entity_number = 1, name = "jatz-liquid-request-depot", position = { x = 0, y = 0 } } }
    end,
    set_blueprint_entities = function(entities)
      saved = entities
    end,
  }
  local slot = script_inventory()
  slot[1].count = 4 -- four freighters in its slot
  storage.depots[request.unit_number].trucks = slot
  logistics.setup_blueprint(blueprint, { request })
  local tags = saved[1].tags
  check("a liquid request depot's blueprint keeps its request", tags and tags.jatz_request.item == "water")
  local settings = saved[2] and saved[2].control_behavior.decider_conditions.conditions[1]
  check(
    "and its request settings, as a fluid",
    saved[2].name == "jatz-depot-settings"
      and settings.first_signal.type == "fluid"
      and settings.first_signal.name == "water"
      and settings.constant == 25000
  )
  check("and how many freighters", tags.jatz_freighters == 4)
  local freighter_settings = saved[2] and saved[2].control_behavior.decider_conditions.conditions[2]
  check(
    "in its request settings too, as a number with no signal",
    freighter_settings and freighter_settings.first_signal == nil and freighter_settings.constant == 4
  )
  check("without an insert plan", saved[1].items == nil)
  local asked
  local match = logistics.match_freighters
  logistics.match_freighters = function(entity, count)
    asked = { entity = entity, count = count }
  end
  local built = liquid(330, "jatz-liquid-request-depot")
  built.valid = true
  fire("on_robot_built_entity", { entity = built, tags = tags })
  logistics.match_freighters = match
  check("the depot built from it asks robots for them", asked and asked.entity == built and asked.count == 4)
  check("and requests the fluid", logistics.get_request(built).item == "water")
end

do -- Mining Drones' mining depot: a provider depot that lays road behind it, with a priority panel.
  local logistics = require("scripts.logistics")
  local registered = false
  for _, filter in ipairs(filters.on_built_entity) do
    registered = registered or filter.name == "mining-depot"
  end
  check("building a mining depot is handled", registered)
  -- 5 by 8 tiles, facing north: its loading zone is the tile (400, 4), behind its southern end.
  local mine = depot(400)
  mine.name, mine.type, mine.position = "mining-depot", "assembling-machine", { x = 400.5, y = 0 }
  cell(400, 4).name = "concrete"
  fire("on_built_entity", { entity = mine })
  check("it lays road behind it", cell(400, 4).name == "jatz-depot-road")
  check("and is a provider depot", logistics.get_priority(mine) == 5)
  local relative = element()
  local player = { index = 13, valid = true, gui = { relative = relative } }
  game.get_player = function()
    return player
  end
  storage.request_gui = {}
  fire("on_gui_opened", { player_index = 13, entity = mine })
  local frame = relative.jatz_request_frame
  check(
    "whose provider panel, priority then circuit condition, is beside its assembling machine window",
    frame
      and frame.anchor.gui == "relative_gui_type.assembling_machine_gui"
      and frame.children[1].children[1] == frame.children[1].priority_row
      and #frame.children[1].children == 5
      and frame.children[1].children[5] == frame.children[1].condition_row
  )
  -- Turned east it is 8 by 5, centred on a tile edge across: its loading zone is the tile (395, 0).
  mine.direction, mine.position = defines.direction.east, { x = 400, y = 0.5 }
  fire("on_player_rotated_entity", { entity = mine })
  check("turned, its road follows", cell(395, 0).name == "jatz-depot-road" and cell(400, 4).name == "concrete")
  removed(mine)
  check("removed, the ground comes back", cell(395, 0).name == "grass-1")
end

do -- The Fuel depot's panel: its liquid fuel, which has no window of its own, and a flush button.
  local relative = element()
  local player = { index = 13, valid = true, gui = { relative = relative } }
  game.get_player = function()
    return player
  end
  storage.request_gui = {}
  local fuel = depot(400)
  fuel.name = "jatz-fuel-depot"
  fire("on_built_entity", { entity = fuel })
  local tank = surface.created[#surface.created]
  check("building a Fuel depot makes its tank, facing as it does", tank.name == "jatz-fuel-depot-tank")
  fire("on_gui_opened", { player_index = 13, entity = fuel })
  local frame = relative.jatz_request_frame
  local row = frame and frame.children[1].fuel_row
  check("a Fuel depot's window gets a panel", frame and frame.caption[1] == "jatz-gui.fuel-title")
  check("anchored to its chest window", frame.anchor.gui == "relative_gui_type.container_gui")
  check("showing the fluid in its tank", row and row.jatz_fuel_fluid.sprite == "fluid/water")
  local caption = row.jatz_fuel_amount.caption
  check("how much, and that it doesn't burn", caption[2][2] == 300 and caption[4][1] == "jatz-gui.fuel-not-burnable")
  check("with no priority", frame.children[1].priority_row == nil)
  fire("on_gui_click", { player_index = 13, element = row.jatz_fuel_flush })
  check("flush empties the tank", tank.held.amount == 0 and row.jatz_fuel_amount.caption[2] == 0)
  check("and the panel shows it empty", row.jatz_fuel_fluid.sprite == "")
  nth[30]()
  check("refresh leaves the panel in place", relative.jatz_request_frame == frame)
end

do -- Every delivery depot's panel ends with its enable/disable circuit condition.
  local logistics = require("scripts.logistics")
  local relative = element()
  local player = { index = 14, valid = true, gui = { relative = relative }, get_main_inventory = function() end }
  game.get_player = function()
    return player
  end
  storage.request_gui = {}
  local provider = depot(400)
  fire("on_built_entity", { entity = provider })
  fire("on_gui_opened", { player_index = 14, entity = provider })
  local inner = relative.jatz_request_frame.children[1]
  check("a provider depot's panel has the circuit condition", inner.circuit_row and inner.condition_row)
  local light = inner.circuit_row.jatz_circuit_status
  check("unticked, its light is grey", light.sprite == "utility/status_inactive")
  local box = inner.circuit_row.jatz_circuit_enabled
  box.state = true
  fire("on_gui_checked_state_changed", { player_index = 14, element = box })
  local row = inner.condition_row
  row.jatz_circuit_first.elem_value = { type = "virtual", name = "signal-A" }
  fire("on_gui_elem_changed", { player_index = 14, element = row.jatz_circuit_first })
  row.jatz_circuit_comparator.selected_index = 2
  fire("on_gui_selection_state_changed", { player_index = 14, element = row.jatz_circuit_comparator })
  row.jatz_circuit_constant.text = "-7"
  fire("on_gui_text_changed", { player_index = 14, element = row.jatz_circuit_constant, text = "-7" })
  local circuit = logistics.get_circuit(provider)
  check(
    "ticking it and setting the condition stores it",
    circuit.enabled
      and circuit.condition.first_signal.name == "signal-A"
      and circuit.condition.comparator == ">"
      and circuit.condition.constant == -7
  )
  check("with no wire, its light stays grey", light.sprite == "utility/status_inactive")
  row.jatz_circuit_first.elem_value = { type = "virtual", name = "signal-each" }
  fire("on_gui_elem_changed", { player_index = 14, element = row.jatz_circuit_first })
  check("each is refused and cleared", row.jatz_circuit_first.elem_value == nil)
  -- Wired, the condition decides: signal-A > -7.
  local value = 0
  provider.get_circuit_network = function(connector)
    return connector == defines.wire_connector_id.circuit_red
        and {
          get_signal = function()
            return value
          end,
        }
      or nil
  end
  row.jatz_circuit_first.elem_value = { type = "virtual", name = "signal-A" }
  fire("on_gui_elem_changed", { player_index = 14, element = row.jatz_circuit_first })
  nth[30]()
  check("wired, and holding, its light is green", light.sprite == "utility/status_working")
  value = -9
  nth[30]()
  check("not holding, red", light.sprite == "utility/status_not_working")
  -- What the condition reads: the circuit network by default, or the depot's own contents.
  local modes = inner.circuit_mode_row
  check(
    "the circuit network is chosen to start with",
    modes.jatz_circuit_mode_network.state and not modes.jatz_circuit_mode_contents.state
  )
  modes.jatz_circuit_mode_contents.state = true
  fire("on_gui_checked_state_changed", { player_index = 14, element = modes.jatz_circuit_mode_contents })
  check("choosing its own contents stores it", logistics.get_circuit(provider).mode == "contents")
  check("and shows only that choice", not modes.jatz_circuit_mode_network.state)
  -- It holds no signal-A: 0 > -7.
  check("which the light follows, wire or not", light.sprite == "utility/status_working")

  local request = depot(410)
  request.name = "jatz-request-depot"
  fire("on_built_entity", { entity = request })
  fire("on_gui_opened", { player_index = 14, entity = request })
  inner = relative.jatz_request_frame.children[1]
  check("so does a request depot's", inner.circuit_row and inner.children[#inner.children] == inner.condition_row)

  -- Copy and Paste settings, and blueprints, carry it.
  fire("on_entity_settings_pasted", { source = provider, destination = request })
  check(
    "pasting copies it",
    logistics.get_circuit(request).condition.constant == -7 and logistics.get_circuit(request).mode == "contents"
  )
  local saved
  local blueprint = {
    valid = true,
    object_name = "LuaItemStack",
    valid_for_read = true,
    is_blueprint = true,
    get_blueprint_entities = function()
      return { { entity_number = 1, name = "jatz-provider-depot", position = { x = 0, y = 0 } } }
    end,
    set_blueprint_entities = function(entities)
      saved = entities
    end,
  }
  logistics.setup_blueprint(blueprint, { provider })
  local tag = saved[1].tags and saved[1].tags.jatz_circuit
  check(
    "a blueprint keeps it as a tag",
    tag and tag.enabled and tag.condition.first_signal.name == "signal-A" and tag.mode == "contents"
  )
  local built = depot(420)
  fire("on_robot_built_entity", { entity = built, tags = saved[1].tags })
  check(
    "and a depot built from it gets it",
    logistics.get_circuit(built).enabled and logistics.get_circuit(built).mode == "contents"
  )
  -- Ticked with no condition set yet: the tick is kept.
  local ticked = depot(440)
  fire("on_built_entity", { entity = ticked })
  logistics.set_circuit(ticked, true, nil)
  logistics.setup_blueprint(blueprint, { ticked })
  local copy = depot(450)
  fire("on_robot_built_entity", { entity = copy, tags = saved[1].tags })
  check("a ticked checkbox without a condition is kept too", logistics.get_circuit(copy).enabled)
  local plain = depot(430)
  fire("on_robot_built_entity", { entity = plain, tags = { jatz_circuit = { enabled = true, condition = "x" } } })
  check("a malformed tag is ignored", not logistics.get_circuit(plain).enabled)
end

do -- The road network monitor shows what the provider and buffer depots on its road hold.
  local logistics = require("scripts.logistics")
  local road_monitor = require("scripts.road-monitor")
  check("once a second runs through control.lua", nth[60] ~= nil)
  local function holding(entity, contents)
    entity.get_inventory = function()
      return {
        get_item_count = function()
          return 0
        end,
        get_contents = function()
          return contents
        end,
      }
    end
    fire("on_built_entity", { entity = entity })
    return entity
  end
  -- P1 at x = 500 and a liquid provider at 504 joined by road; a request depot at 508 too; P3 at
  -- 520 on its own; the monitor beside P1's loading zone.
  for x = 501, 507 do
    cell(x, 2).name = "jatz-road"
  end
  local p1 = holding(depot(500), {
    { name = "iron-plate", quality = "normal", count = 10 },
    { name = "iron-plate", quality = "uncommon", count = 2 },
  })
  local liquid = depot(504)
  liquid.name = "jatz-liquid-provider-depot"
  liquid.get_fluid_contents = function()
    return { water = 1500.5 }
  end
  fire("on_built_entity", { entity = liquid })
  local request = depot(508)
  request.name = "jatz-request-depot"
  holding(request, { { name = "wood", quality = "normal", count = 5 } })
  holding(depot(520), { { name = "iron-plate", quality = "normal", count = 99 } })
  -- A mining depot (Mining Drones) loading from the same road: an assembling machine, with its ore
  -- in its output inventory and no chest. Facing north, it loads from the tile behind it, (506, 2).
  local mine = depot(506)
  mine.name, mine.type, mine.position = "mining-depot", "assembling-machine", { x = 506.5, y = -2 }
  mine.get_inventory = function()
    return nil
  end
  function mine.get_output_inventory()
    return {
      get_contents = function()
        return { { name = "iron-ore", quality = "normal", count = 4 } }
      end,
    }
  end
  fire("on_built_entity", { entity = mine })
  -- Another force's provider on the same road: deliveries never use it, nor does the monitor.
  local foreign = depot(496)
  foreign.force = "enemy"
  for x = 497, 499 do
    cell(x, 2).name = "jatz-road"
  end
  holding(foreign, { { name = "copper-plate", quality = "normal", count = 7 } })
  local sections = {}
  local behavior = {
    sections_count = 0,
    get_section = function(index)
      return sections[index]
    end,
    add_section = function()
      sections[#sections + 1] = { is_manual = true, filters = {} }
      return sections[#sections]
    end,
    remove_section = function(index)
      table.remove(sections, index)
    end,
  }
  setmetatable(behavior, {
    __index = function(_, key)
      if key == "sections_count" then
        return #sections
      end
    end,
  })
  behavior.sections_count = nil
  next_unit = next_unit + 1
  local monitor = {
    valid = true,
    name = "jatz-road-monitor",
    unit_number = next_unit,
    position = { x = 500.5, y = 3.5 },
    surface = surface,
    surface_index = 1,
    force = "player",
    operable = true,
    get_circuit_network = function()
      return nil
    end,
    get_or_create_control_behavior = function()
      return behavior
    end,
  }
  fire("on_built_entity", { entity = monitor })
  check("a monitor can be opened, to its panel", monitor.operable == true)
  road_monitor.update()
  local function shown()
    local seen = {}
    for _, section in ipairs(sections) do
      for _, filter in ipairs(section.filters) do
        seen[filter.value.type .. ":" .. filter.value.name .. ":" .. filter.value.quality] = filter.min
      end
    end
    return seen
  end
  local seen = shown()
  check(
    "it shows a provider's items, each quality its own signal",
    seen["item:iron-plate:normal"] == 10 and seen["item:iron-plate:uncommon"] == 2
  )
  check("and a liquid provider's fluid, in whole units", seen["fluid:water:normal"] == 1500)
  check("but not a request depot's items", seen["item:wood:normal"] == nil)
  check("nor another force's", seen["item:copper-plate:normal"] == nil)
  check("and a mining depot's output", seen["item:iron-ore:normal"] == 4)
  check("nor a provider on another road", #sections == 1 and #sections[1].filters == 4)
  -- What it reads is chosen in its panel, which opening it shows instead of the combinator's own
  -- window. A buffer depot holding 3 stone joins the road, and the request depot asks for 12 wood
  -- (it holds 5).
  local buffer = depot(502)
  buffer.name = "jatz-buffer-depot"
  holding(buffer, { { name = "stone", quality = "normal", count = 3 } })
  request.get_inventory = function()
    local chest = {
      get_item_count = function(id)
        return (type(id) == "table" and id.name or id) == "wood" and 5 or 0
      end,
      get_insertable_count = function()
        return 100
      end,
      get_contents = function()
        return { { name = "wood", quality = "normal", count = 5 } }
      end,
    }
    -- Its 48 slots, which #chest counts.
    for index = 1, 48 do
      chest[index] = { valid_for_read = false }
    end
    return chest
  end
  check("setup: the request depot asks for 12 wood", logistics.set_request(request, "wood", 12))
  local screen = element()
  local viewer = { index = 15, valid = true, gui = { relative = element(), screen = screen } }
  game.get_player = function()
    return viewer
  end
  monitor.localised_name = { "entity-name.jatz-road-monitor" }
  fire("on_gui_opened", { player_index = 15, entity = monitor })
  local panel = screen.jatz_monitor_frame
  check("opening a monitor shows its panel in place of the combinator's window", panel and viewer.opened == panel)
  check(
    "reading what provider and buffer depots hold to start with",
    panel.inner.jatz_monitor_reading_supply.state and not panel.inner.jatz_monitor_reading_providers.state
  )
  local function choose(reading)
    local button = panel.inner["jatz_monitor_reading_" .. reading]
    button.state = true
    fire("on_gui_checked_state_changed", { player_index = 15, element = button })
    road_monitor.update()
    return shown()
  end
  seen = choose("supply")
  check(
    "provider and buffer depots: the buffer's stone too",
    seen["item:stone:normal"] == 3 and seen["item:iron-plate:normal"] == 10 and seen["item:wood:normal"] == nil
  )
  seen = choose("providers")
  check(
    "provider depots only: no stone",
    seen["item:stone:normal"] == nil and seen["item:iron-plate:normal"] == 10 and seen["fluid:water:normal"] == 1500
  )
  check("and only that choice ticked", not panel.inner.jatz_monitor_reading_supply.state)
  seen = choose("requests")
  check(
    "request depots only: the 5 wood it holds, nothing else",
    seen["item:wood:normal"] == 5 and seen["item:iron-plate:normal"] == nil and seen["item:stone:normal"] == nil
  )
  seen = choose("needs")
  check(
    "what request depots still need: 12 less the 5 held",
    seen["item:wood:normal"] == 7 and #sections[1].filters == 1
  )
  check("kept on the monitor", road_monitor.get_reading(monitor) == "needs")
  -- Blueprints, Copy and Paste settings and clones carry it.
  local saved
  local blueprint = {
    valid = true,
    object_name = "LuaItemStack",
    valid_for_read = true,
    is_blueprint = true,
    get_blueprint_entities = function()
      return { { entity_number = 1, name = "jatz-road-monitor", position = { x = 0, y = 0 } } }
    end,
    set_blueprint_entities = function(entities)
      saved = entities
    end,
  }
  logistics.setup_blueprint(blueprint, { monitor })
  check("a blueprint keeps it as a tag", saved and saved[1].tags and saved[1].tags.jatz_monitor_reading == "needs")
  local function another()
    next_unit = next_unit + 1
    local copy = {}
    for key, value in pairs(monitor) do
      copy[key] = value
    end
    copy.unit_number, copy.position = next_unit, { x = 900.5, y = 3.5 }
    copy.get_or_create_control_behavior = function() end
    return copy
  end
  local built = another()
  fire("on_robot_built_entity", { entity = built, tags = saved[1].tags })
  check("a monitor built from it reads the same", road_monitor.get_reading(built) == "needs")
  local pasted = another()
  fire("on_built_entity", { entity = pasted })
  check("a new monitor reads providers and buffers", road_monitor.get_reading(pasted) == "supply")
  fire("on_entity_settings_pasted", { source = monitor, destination = pasted })
  check("pasting settings copies it", road_monitor.get_reading(pasted) == "needs")
  local cloned = another()
  fire("on_entity_cloned", { source = monitor, destination = cloned })
  check("so does cloning", road_monitor.get_reading(cloned) == "needs")
  -- A clone keeps the original's signals, which it never counted: a depot reading the wire would
  -- take them for stock elsewhere. Cleared as the clone is registered, in the tick it is made,
  -- they never reach the wire (Pullfrog's review of 99acef3).
  local inherited = {
    {
      is_manual = true,
      filters = {
        { value = { type = "item", name = "iron-plate", quality = "normal", comparator = "=" }, min = 10 },
      },
    },
  }
  local copied = another()
  local copied_behavior = {
    enabled = true,
    sections_count = 1,
    get_section = function(index)
      return inherited[index]
    end,
    add_section = function() end,
    remove_section = function() end,
  }
  copied.get_or_create_control_behavior = function()
    return copied_behavior
  end
  fire("on_entity_cloned", { source = monitor, destination = copied })
  local record = storage.road_monitors[copied.unit_number]
  check("a clone's inherited signals are cleared as it is registered", #inherited[1].filters == 0)
  check(
    "and what it counted starts empty, this tick",
    record and record.counted and next(record.counted) == nil and record.counted_tick == game.tick
  )
  check("keeping the original's reading", road_monitor.get_reading(copied) == "needs")
  check("the remote interface refuses another reading", not road_monitor.set_reading(monitor, "everything"))
  fire("on_gui_closed", { player_index = 15, element = panel })
  check("E or Esc closes the panel", screen.jatz_monitor_frame == nil)
  -- Back to providers and buffers, without the buffer, for the rest.
  check("setup", road_monitor.set_reading(monitor, "supply"))
  removed(buffer)
  -- Copy and Paste settings from a constant combinator brings its state with it (probed on 2.1.24):
  -- its switch off, and a section switched off, multiplied by 3, and in a named group, whose filters
  -- every member shares. The monitor must take its output back without writing that group
  -- (Pullfrog's review of 5f5c385).
  road_monitor.update()
  local group = { { value = { type = "virtual", name = "signal-A", quality = "normal", comparator = "=" }, min = 123 } }
  local state = { group = "shared", active = false, multiplier = 3, own = {} }
  sections[1] = setmetatable({ is_manual = true }, {
    __index = function(_, key)
      if key == "filters" then
        return state.group ~= "" and group or state.own
      end
      return state[key]
    end,
    __newindex = function(_, key, value)
      if key == "filters" and state.group ~= "" then
        group = value
      elseif key == "filters" then
        state.own = value
      else
        state[key] = value
      end
    end,
  })
  behavior.enabled = false
  fire("on_entity_settings_pasted", {
    source = { valid = true, name = "constant-combinator", unit_number = 99999 },
    destination = monitor,
  })
  check(
    "pasting a combinator's settings leaves its shared group alone",
    #group == 1 and group[1].value.name == "signal-A" and group[1].min == 123
  )
  check("the monitor shows its own reading again at once", shown()["item:iron-plate:normal"] == 10)
  check(
    "in a section of its own, active, multiplied by 1, and switched on",
    state.group == "" and state.active and state.multiplier == 1 and behavior.enabled
  )
  road_monitor.update()
  check("nor does its next update write the group", #group == 1 and group[1].value.name == "signal-A")
  -- P1 switched off by its circuit condition: left out.
  p1.get_circuit_network = function(connector)
    return connector == defines.wire_connector_id.circuit_green
        and {
          get_signal = function()
            return 0
          end,
        }
      or nil
  end
  logistics.set_circuit(p1, true, { first_signal = { type = "virtual", name = "signal-A" }, comparator = ">" })
  road_monitor.update()
  check("a depot switched off by its condition isn't counted", shown()["item:iron-plate:normal"] == nil)
  logistics.set_circuit(p1, false, nil)
  road_monitor.update()
  -- P1 wired (green) to the monitor, reading the circuit network: of the 10 iron plates the monitor
  -- shows, all are P1's own, which its condition leaves out. A tick later the wire carries them.
  game.tick = game.tick + 1
  local green = {
    network_id = 7,
    get_signal = function(id)
      return shown()[(id.type or "item") .. ":" .. id.name .. ":" .. (id.quality or "normal")] or 0
    end,
  }
  local function on_green(connector)
    return connector == defines.wire_connector_id.circuit_green and green or nil
  end
  p1.get_circuit_network, monitor.get_circuit_network = on_green, on_green
  local plate = { type = "item", name = "iron-plate" }
  logistics.set_circuit(p1, true, { first_signal = plate, comparator = ">", constant = 5 })
  check("setup: the condition is iron plate > 5", logistics.get_circuit(p1).condition.first_signal.name == "iron-plate")
  check("setup: the wire carries the monitor's 10 plates", green.get_signal(plate) == 10)
  check("a depot reading the monitor leaves out its own plates", not logistics.get_circuit(p1).fulfilled)
  road_monitor.update()
  game.tick = game.tick + 1
  check("and stays off once the monitor no longer counts it", not logistics.get_circuit(p1).fulfilled)
  logistics.set_circuit(p1, true, nil, "contents")
  check("reading its own contents, it has its 10", logistics.get_circuit(p1).fulfilled)
  logistics.set_circuit(p1, false, nil, "network")
  -- The road between them is mined: the liquid provider is on another network now.
  cell(502, 2).name = "grass-1"
  fire(
    "on_player_mined_tile",
    { surface_index = 1, tiles = { { position = { x = 502, y = 2 }, old_tile = { name = "jatz-road" } } } }
  )
  road_monitor.update()
  seen = shown()
  check(
    "cutting the road leaves out what is beyond",
    seen["fluid:water:normal"] == nil and seen["item:iron-plate:normal"] == 10
  )
  -- Forces change without the road changing (game.merge_forces, a script setting the force): the
  -- other force's provider becomes the player's, and the next update counts its copper, with
  -- nothing marking the surface changed (Pullfrog's review of 08bed57).
  check("setup: no road change pending", next(storage.road_monitor_dirty) == nil)
  foreign.force = "player"
  road_monitor.update()
  check("a depot whose force merges into the monitor's counts at once", shown()["item:copper-plate:normal"] == 7)
  -- Removed: forgotten.
  monitor.valid = false
  fire("on_object_destroyed", { type = defines.target_type.entity, useful_id = monitor.unit_number })
  check("a removed monitor is forgotten", storage.road_monitors[monitor.unit_number] == nil)
end

do -- Research finished or undone reaches the freighters (tests/lua/logistics.lua checks what it does).
  local logistics = require("scripts.logistics")
  check("finished research is handled", handlers.on_research_finished == logistics.on_research_changed)
  check("so is research undone", handlers.on_research_reversed == logistics.on_research_changed)
  fire("on_research_finished", { research = { name = "automation", force = { index = 1 } } })
  check("other research changes nothing", true)
end

do -- A save from before research keeps its recipes; a new game, or a save the mod is added to, doesn't.
  local research = require("scripts.research")
  -- Each force's unlocking technologies, unresearched, as Factorio leaves them after resetting the
  -- technology effects of a save from before research.
  local function forces()
    local list = {}
    for _, name in ipairs({ "player", "enemy" }) do
      local technologies = {}
      for _, technology in ipairs(research.unlocks) do
        technologies[technology] = { researched = false }
      end
      list[name] = { technologies = technologies }
    end
    return list
  end
  local function researched(list)
    local count = 0
    for _, force in pairs(list) do
      for _, technology in ipairs(research.unlocks) do
        count = count + (force.technologies[technology].researched and 1 or 0)
      end
    end
    return count
  end
  local before = storage
  storage = {}
  game.forces = forces()
  lifecycle.init()
  check("a new game researches nothing", researched(game.forces) == 0)
  lifecycle.configuration_changed()
  check("nor does a later mod change", researched(game.forces) == 0)
  storage = { depots = {} }
  game.forces = forces()
  lifecycle.configuration_changed()
  check("a save from before research gets every unlock, for every force", researched(game.forces) == 6)
  game.forces = forces()
  lifecycle.configuration_changed()
  check("once only", researched(game.forces) == 0)
  storage = before
end

do -- Undo: a depot a player removes keeps its settings, as they were when it went, on that
  -- removal's undo action, and the ghost undoing it brings back gets them, so the depot built from
  -- it has its request and asks for its freighters.
  local logistics = require("scripts.logistics")
  local loading_zone = require("scripts.loading-zone")
  -- Every event the undo handling listens to reaches every depot and the monitor, and nothing else.
  local expected = { ["jatz-road-monitor"] = true }
  for name in pairs(loading_zone.depots) do
    expected[name] = true
  end
  for _, event in ipairs({
    "on_marked_for_deconstruction",
    "on_cancelled_deconstruction",
    "on_robot_pre_mined",
    "on_space_platform_pre_mined",
    "on_pre_player_mined_item",
    "on_player_mined_entity",
  }) do
    local names, count = {}, 0
    for _, filter in ipairs(filters[event] or {}) do
      assert(filter.filter == "name", "FAILED: " .. event .. " filters by name only")
      names[filter.name] = true
      count = count + 1
    end
    local all = count == 0 and false or true
    for name in pairs(expected) do
      all = all and names[name] == true
    end
    for name in pairs(names) do
      all = all and expected[name] == true
    end
    check(event .. " reaches every depot and the monitor, and nothing else", all)
  end
  for _, name in ipairs({ "jatz-request-depot", "jatz-buffer-depot", "jatz-liquid-request-depot" }) do
    check("including " .. name, expected[name])
  end

  -- The player's undo stack (LuaUndoRedoStack, runtime-api.json 2.1.24): items most recent first,
  -- each a list of actions, whose tags (AnyBasic) set_undo_tag(item_index, action_index, tag_name,
  -- tag) keeps and get_undo_tag(item_index, action_index, tag_name) reads, within range, and the undo
  -- event then carries. `reads` counts get_undo_item: each read builds every action of the item.
  local items, reads = {}, 0
  local BASIC = { string = true, number = true, boolean = true, table = true }
  local function action_at(item, action)
    local entry = items[item] and items[item][action]
    assert(entry, "FAILED: no undo action " .. tostring(item) .. "/" .. tostring(action))
    return entry
  end
  local undo_stack = {
    get_undo_item_count = function()
      return #items
    end,
    get_undo_item = function(index)
      assert(items[index], "FAILED: no undo item " .. tostring(index))
      reads = reads + 1
      return items[index]
    end,
    get_undo_tag = function(item, action, name)
      assert(type(name) == "string", "FAILED: get_undo_tag(item, action, tag_name)")
      local entry = action_at(item, action)
      return entry.tags and entry.tags[name]
    end,
    set_undo_tag = function(item, action, name, tag)
      local entry = action_at(item, action)
      assert(type(name) == "string" and BASIC[type(tag)], "FAILED: set_undo_tag(item, action, tag_name, tag)")
      entry.tags = entry.tags or {}
      entry.tags[name] = tag
    end,
  }
  -- Factorio keeps the 100 latest undo items: one more pushes the oldest out.
  local function new_item(actions)
    table.insert(items, 1, actions)
    if #items > 100 then
      table.remove(items)
    end
  end
  local function removal(name, x, y)
    return { type = "removed-entity", surface_index = 1, target = { name = name, position = { x = x, y = y } } }
  end
  local player = { index = 20, valid = true, undo_redo_stack = undo_stack }
  game.get_player = function()
    return player
  end
  -- Only the undo part of on_tick here: deliveries have their own checks (tests/lua/logistics.lua).
  local deliveries = {}
  for _, name in ipairs({ "sample_circuits", "on_tick_share", "on_impact_share" }) do
    deliveries[name] = logistics[name]
    logistics[name] = function() end
  end
  -- `count` freighters in a depot's slot, and `in_chest` in its chest (counted as the game does).
  local function freighters_in(target, count, in_chest)
    local trucks = script_inventory()
    local slot = trucks[1]
    slot.name, slot.count, slot.valid_for_read = "jatz-quinityn-freighter", count, true
    function slot.clear()
      slot.count, slot.valid_for_read = 0, false
    end
    function trucks.destroy()
      trucks.valid = false
    end
    storage.depots[target.unit_number].trucks = trucks
    local chest = target.get_inventory()
    chest.get_item_count_filtered = function()
      return in_chest or 0
    end
    target.get_inventory = function()
      return chest
    end
    return slot, function(n)
      in_chest = n
    end
  end
  -- Ghosts the undo brings back; the search finds one only by its name and where it stands.
  local ghosts = {}
  surface.find_entities_filtered = function(filter)
    local found = {}
    for _, ghost in ipairs(ghosts) do
      local at = filter.position
      local x, y = at.x or at[1], at.y or at[2]
      -- A 3x3 depot's ghost collides with points within 1.5 tiles of its centre.
      if
        filter.ghost_name == ghost.ghost_name
        and math.abs(ghost.position.x - x) < 1.5
        and math.abs(ghost.position.y - y) < 1.5
      then
        found[#found + 1] = ghost
      end
    end
    return found
  end
  local function ghost_at(x, y)
    local ghost =
      { valid = true, ghost_name = "jatz-request-depot", position = { x = x, y = y }, tags = { other_mod = 1 } }
    ghosts[#ghosts + 1] = ghost
    return ghost
  end
  -- A player mining it by hand: before, the mining (its freighters to the player), then gone.
  local function hand_mine(entity)
    fire("on_pre_player_mined_item", { entity = entity, player_index = 20 })
    fire("on_player_mined_entity", {
      entity = entity,
      player_index = 20,
      buffer = {
        insert = function(stack)
          return stack.count
        end,
      },
    })
    removed(entity)
  end
  local function robot_takes(entity)
    fire("on_robot_pre_mined", { entity = entity })
    local carried = 0
    fire("on_robot_mined_entity", {
      entity = entity,
      buffer = {
        insert = function(stack)
          carried = carried + stack.count
          return stack.count
        end,
      },
    })
    removed(entity)
    return carried
  end

  -- Cut: marked by the player, its undo action made just after; robots take it later. Cut with two
  -- more depots, all in one undo item.
  local entity = depot(600)
  entity.name = "jatz-request-depot"
  fire("on_built_entity", { entity = entity })
  assert(logistics.set_request(entity, "wood", 5))
  local _, chest_holds = freighters_in(entity, 3)
  local others = {}
  for index, x in ipairs({ 602, 604 }) do
    others[index] = depot(x)
    others[index].name = "jatz-request-depot"
    fire("on_built_entity", { entity = others[index] })
    freighters_in(others[index], index)
  end
  game.tick = 1000
  fire("on_marked_for_deconstruction", { entity = entity, player_index = 20 })
  for _, other in ipairs(others) do
    fire("on_marked_for_deconstruction", { entity = other, player_index = 20 })
  end
  new_item({
    removal("wooden-chest", 1.5, 1.5),
    removal("jatz-request-depot", 600.5, 0.5),
    removal("jatz-request-depot", 602.5, 0.5),
    removal("jatz-request-depot", 604.5, 0.5),
  })
  fire("on_tick", { tick = 1000 })
  check("its undo action, made just after the marking, is looked for that tick", reads == 1)
  check("the cut's undo item read once for all three depots", storage.undo_locating == nil)
  fire("on_tick", { tick = 1001 })
  check(
    "nothing is saved at marking: its settings may change before it goes",
    items[1][2].tags and items[1][2].tags.jatz_settings == nil and items[1][2].tags.jatz_removal_of ~= nil
  )
  fire("on_tick", { tick = 1002 })
  check("and not read again", reads == 1 and storage.undo_locating == nil)
  -- Before the robots come: a bigger request, and 2 more freighters put in its chest.
  assert(logistics.set_request(entity, "wood", 8))
  chest_holds(2)
  -- Something else the player did since: the removal's item is no longer the newest.
  new_item({ removal("wooden-chest", 9.5, 9.5) })
  game.tick = 1600
  local carried = robot_takes(entity)
  for _, other in ipairs(others) do
    robot_takes(other)
  end
  check("robots taking them read no undo item: each goes to its action", reads == 1)
  check(
    "the others' actions keep theirs",
    items[2][3].tags.jatz_settings.jatz_freighters == 1 and items[2][4].tags.jatz_settings.jatz_freighters == 2
  )
  local settings = items[2][2].tags and items[2][2].tags.jatz_settings
  check("robots taking it tag the marking player's removal action at once", settings ~= nil)
  check("with its settings as it went: the request then", settings.jatz_request.count == 8)
  check("and every freighter, the 2 in its chest too", settings.jatz_freighters == 5)
  check("not the chest's, nor the newer item's", items[2][1].tags == nil and items[1][1].tags == nil)
  check("robots took the slot's freighters", carried == 3)
  check("nothing is left waiting", storage.undo_pending == nil and storage.undo_marked == nil)
  -- Undo: its ghost comes back, bare; the undo event carries the action as the stack kept it.
  local ghost = ghost_at(600.5, 0.5)
  local elsewhere = ghost_at(600.5, 9.5)
  fire("on_undo_applied", { player_index = 20, actions = items[2] })
  check(
    "undo gives its ghost the settings, keeping its other tags",
    ghost.tags.jatz_request.count == 8 and ghost.tags.jatz_freighters == 5 and ghost.tags.other_mod == 1
  )
  check("and no other ghost", elsewhere.tags.jatz_request == nil)
  local built = depot(610)
  built.name = "jatz-request-depot"
  local asked
  local match = logistics.match_freighters
  logistics.match_freighters = function(entity_, count)
    asked = { entity = entity_, count = count }
  end
  fire("on_robot_built_entity", { entity = built, tags = ghost.tags })
  logistics.match_freighters = match
  check("the depot built from it has its request back", logistics.get_request(built).count == 8)
  check("and asks robots for its freighters", asked and asked.entity == built and asked.count == 5)

  -- Deconstruction cancelled: nothing waits for robots any more.
  local kept = depot(620)
  kept.name = "jatz-request-depot"
  fire("on_built_entity", { entity = kept })
  freighters_in(kept, 1)
  fire("on_marked_for_deconstruction", { entity = kept, player_index = 20 })
  fire("on_cancelled_deconstruction", { entity = kept, player_index = 20 })
  check("a cancelled deconstruction forgets who marked it", storage.undo_marked == nil)
  -- Marked, then a mining attempt that leaves it standing (by hand with a full inventory, or by a
  -- robot): it is still marked, and robots taking it later still save its settings as it goes.
  local survivor = depot(625)
  survivor.name = "jatz-request-depot"
  fire("on_built_entity", { entity = survivor })
  freighters_in(survivor, 1)
  assert(logistics.set_request(survivor, "wood", 5))
  fire("on_marked_for_deconstruction", { entity = survivor, player_index = 20 })
  new_item({ removal("jatz-request-depot", 625.5, 0.5) })
  game.tick = 1700
  fire("on_pre_player_mined_item", { entity = survivor, player_index = 20 })
  fire("on_robot_pre_mined", { entity = survivor })
  check("a mining attempt that leaves it standing keeps who marked it", storage.undo_marked ~= nil)
  assert(logistics.set_request(survivor, "wood", 7))
  freighters_in(survivor, 4)
  game.tick = 1800
  robot_takes(survivor)
  local survivor_settings = items[1][1].tags and items[1][1].tags.jatz_settings
  check(
    "robots taking it later save its settings as it went",
    survivor_settings and survivor_settings.jatz_request.count == 7 and survivor_settings.jatz_freighters == 4
  )
  check("its removal then forgets who marked it", storage.undo_marked == nil)
  check("the failed hand mining leaves nothing waiting", storage.undo_pending == nil)
  fire("on_tick", { tick = 1801 })
  check(
    "so nothing older overwrites what the robots saved",
    items[1][1].tags.jatz_settings.jatz_request.count == 7 and items[1][1].tags.jatz_settings.jatz_freighters == 4
  )
  -- Marked by a script, with no player: no undo action of a player's to tag.
  fire("on_marked_for_deconstruction", { entity = kept })
  robot_takes(kept)
  check("a removal no player marked waits for nothing", storage.undo_pending == nil)

  -- Mined by hand: its chest's freighters count, and its undo item comes after the mining.
  local mined = depot(630)
  mined.name = "jatz-request-depot"
  fire("on_built_entity", { entity = mined })
  local slot = freighters_in(mined, 1, 2)
  game.tick = 2000
  hand_mine(mined)
  check("mining still hands its freighters over", not slot.valid_for_read)
  check("its settings wait for its undo item, made just after the mining", #storage.undo_pending[20] == 1)
  new_item({ removal("jatz-request-depot", 630.5, 0.5) })
  fire("on_tick", { tick = 2000 })
  check(
    "which the next tagging finds, that same tick too, with every freighter it had, the 2 in its chest too",
    items[1][1].tags and items[1][1].tags.jatz_settings.jatz_freighters == 3
  )
  check("and nothing is left waiting", storage.undo_pending == nil)

  -- Undone before its action was tagged: the undo takes the settings still waiting.
  local quick = depot(640)
  quick.name = "jatz-request-depot"
  fire("on_built_entity", { entity = quick })
  freighters_in(quick, 4)
  game.tick = 3000
  hand_mine(quick)
  local quick_ghost = ghost_at(640.5, 0.5)
  fire("on_undo_applied", { player_index = 20, actions = { removal("jatz-request-depot", 640.5, 0.5) } })
  check("an undo before the tag still brings the settings back", quick_ghost.tags.jatz_freighters == 4)
  check("and takes them off the waiting list", #storage.undo_pending[20] == 0)
  fire("on_tick", { tick = 3001 })
  check("which is then cleared", storage.undo_pending == nil)

  -- Two removals at the same spot before their actions are tagged: each gets its own.
  local first = depot(650)
  first.name = "jatz-request-depot"
  fire("on_built_entity", { entity = first })
  freighters_in(first, 1)
  game.tick = 4000
  hand_mine(first)
  new_item({ removal("jatz-request-depot", 650.5, 0.5) })
  local second = depot(650)
  second.name = "jatz-request-depot"
  fire("on_built_entity", { entity = second })
  -- The newer one bare: nothing to keep, but its own snapshot, so the order holds.
  freighters_in(second, 0)
  hand_mine(second)
  new_item({ removal("jatz-request-depot", 650.5, 0.5) })
  fire("on_tick", { tick = 4001 })
  check(
    "two removals at one spot each tag their own action, the newest the newest, a bare one too",
    next(items[1][1].tags.jatz_settings) == nil and items[2][1].tags.jatz_settings.jatz_freighters == 1
  )

  -- Mined by hand but not removed after all: nothing waits, so no later removal at that spot is
  -- given its settings.
  local stays = depot(660)
  stays.name = "jatz-request-depot"
  fire("on_built_entity", { entity = stays })
  freighters_in(stays, 1)
  game.tick = 5000
  fire("on_pre_player_mined_item", { entity = stays, player_index = 20 })
  check("a mining attempt that removes nothing leaves nothing waiting", storage.undo_pending == nil)
  -- A removal whose undo action never turns up is given up after a second, without tagging later.
  local lost = depot(670)
  lost.name = "jatz-request-depot"
  fire("on_built_entity", { entity = lost })
  freighters_in(lost, 1)
  hand_mine(lost)
  fire("on_tick", { tick = 5030 })
  check("a removal with no undo action yet still waits for a while", #storage.undo_pending[20] == 1)
  new_item({ removal("jatz-request-depot", 670.5, 0.5) })
  fire("on_tick", { tick = 5060 })
  check("and is given up after a second", storage.undo_pending == nil)
  check("without tagging an action that turns up later", items[1][1].tags == nil)

  -- A robot attempt saves its settings, and leaves it standing; set back to as every new depot is,
  -- robots taking it then save that, replacing what the attempt saved.
  local reset = depot(680)
  reset.name = "jatz-request-depot"
  fire("on_built_entity", { entity = reset })
  freighters_in(reset, 2)
  assert(logistics.set_request(reset, "wood", 5))
  game.tick = 6000
  fire("on_marked_for_deconstruction", { entity = reset, player_index = 20 })
  new_item({ removal("jatz-request-depot", 680.5, 0.5) })
  fire("on_tick", { tick = 6001 })
  fire("on_robot_pre_mined", { entity = reset })
  check("a robot attempt saves its settings", items[1][1].tags.jatz_settings.jatz_freighters == 2)
  assert(logistics.set_request(reset, nil))
  freighters_in(reset, 0)
  robot_takes(reset)
  check("robots taking it bare save nothing to keep, replacing that", next(items[1][1].tags.jatz_settings) == nil)
  local bare_ghost = ghost_at(680.5, 0.5)
  fire("on_undo_applied", { player_index = 20, actions = items[1] })
  check("so undo leaves its ghost as it is", bare_ghost.tags.jatz_freighters == nil and bare_ghost.tags.other_mod == 1)

  -- A space platform takes a liquid depot in the tick it was marked, before its action was looked
  -- for: the removal finds it itself.
  local platform_depot = depot(690)
  platform_depot.name = "jatz-liquid-request-depot"
  fire("on_built_entity", { entity = platform_depot })
  freighters_in(platform_depot, 2)
  game.tick = 6500
  fire("on_marked_for_deconstruction", { entity = platform_depot, player_index = 20 })
  new_item({ removal("jatz-liquid-request-depot", 690.5, 0.5) })
  local before = reads
  fire("on_space_platform_pre_mined", { entity = platform_depot })
  check("a platform taking it tags its action", items[1][1].tags.jatz_settings.jatz_freighters == 2 and reads > before)
  fire("on_space_platform_mined_entity", {
    entity = platform_depot,
    buffer = {
      insert = function(stack)
        return stack.count
      end,
    },
  })
  removed(platform_depot)
  fire("on_tick", { tick = 6501 })
  check("and nothing is left to look for", storage.undo_locating == nil and storage.undo_marked == nil)

  -- Its action located, then the stack trimmed at its oldest under it: the mark no longer matches,
  -- and the removal finds its action itself.
  local shifted = depot(700)
  shifted.name = "jatz-request-depot"
  fire("on_built_entity", { entity = shifted })
  freighters_in(shifted, 3)
  game.tick = 7000
  fire("on_marked_for_deconstruction", { entity = shifted, player_index = 20 })
  new_item({ removal("jatz-request-depot", 700.5, 0.5) })
  fire("on_tick", { tick = 7001 })
  new_item({ removal("wooden-chest", 9.5, 9.5) })
  table.remove(items)
  robot_takes(shifted)
  check("a stack that moved under it still gets its settings", items[2][1].tags.jatz_settings.jatz_freighters == 3)

  -- Mined by hand, then a bare replacement at the same spot marked for deconstruction before the
  -- mining's action is tagged: each removal keeps its own action. In the mining's tick (located
  -- before the tagging, marked as the replacement's), and in the tagging's tick (not yet located).
  for round, marked_tick in ipairs({ 8000, 8101 }) do
    local x = 710 + round * 2
    local mined_first = depot(x)
    mined_first.name = "jatz-request-depot"
    fire("on_built_entity", { entity = mined_first })
    freighters_in(mined_first, 4)
    assert(logistics.set_request(mined_first, "wood", 6))
    local start = marked_tick == 8000 and 8000 or 8100
    game.tick = start
    hand_mine(mined_first)
    new_item({ removal("jatz-request-depot", x + 0.5, 0.5) })
    local mining_item = #items
    local replacement = depot(x)
    replacement.name = "jatz-request-depot"
    fire("on_built_entity", { entity = replacement })
    freighters_in(replacement, 0)
    game.tick = marked_tick
    fire("on_marked_for_deconstruction", { entity = replacement, player_index = 20 })
    new_item({ removal("jatz-request-depot", x + 0.5, 0.5) })
    fire("on_tick", { tick = start + 1 })
    local mining_action = items[#items - mining_item + 1][1]
    check(
      "the mined depot's own action keeps its settings, the replacement marked "
        .. (round == 1 and "in its tick" or "while it is tagged"),
      ((mining_action.tags or {}).jatz_settings or {}).jatz_freighters == 4
    )
    check("and the replacement's action doesn't take them", not (items[1][1].tags and items[1][1].tags.jatz_settings))
    -- Cancelled before robots came: its action undone brings no ghost back, and leaves alone what
    -- is still waiting for others.
    fire("on_cancelled_deconstruction", { entity = replacement, player_index = 20 })
  end
  -- A removal still waiting for its action, and the deconstruction of a replacement at its spot
  -- undone before then: no ghost comes back, so the waiting settings stay for their own action.
  local waiting_depot = depot(720)
  waiting_depot.name = "jatz-request-depot"
  fire("on_built_entity", { entity = waiting_depot })
  freighters_in(waiting_depot, 2)
  game.tick = 8200
  hand_mine(waiting_depot)
  fire("on_undo_applied", { player_index = 20, actions = { removal("jatz-request-depot", 720.5, 0.5) } })
  check("an undo bringing no ghost back leaves the waiting settings", #storage.undo_pending[20] == 1)
  new_item({ removal("jatz-request-depot", 720.5, 0.5) })
  fire("on_tick", { tick = 8201 })
  check("for their own action", items[1][1].tags.jatz_settings.jatz_freighters == 2)
  -- Undoing what isn't ours, or ours with nothing to keep, searches for no ghost.
  local searches = 0
  local search = surface.find_entities_filtered
  surface.find_entities_filtered = function(filter)
    searches = searches + 1
    return search(filter)
  end
  fire("on_undo_applied", {
    player_index = 20,
    actions = {
      removal("wooden-chest", 1.5, 1.5),
      {
        type = "removed-entity",
        surface_index = 1,
        target = { name = "jatz-request-depot", position = { x = 730.5, y = 0.5 } },
        tags = { jatz_settings = {} },
      },
    },
  })
  check("undoing what isn't ours, or ours with nothing to keep, searches for no ghost", searches == 0)
  surface.find_entities_filtered = search

  -- At the history's limit (100 items), where pushing one drops the oldest, so places in the
  -- history move under every removal.
  local function fill_history()
    while #items < 100 do
      new_item({ removal("wooden-chest", 50.5, 50.5) })
    end
  end
  local function kept_at(x)
    local found = {}
    for _, actions in ipairs(items) do
      for _, action in ipairs(actions) do
        if action.target.name == "jatz-request-depot" and action.target.position.x == x then
          local saved = action.tags and action.tags.jatz_settings
          found[#found + 1] = saved and (saved.jatz_freighters or 0) or "untagged"
        end
      end
    end
    return found
  end
  -- Two hand minings at one spot in a tick, the first from 99 items (Pullfrog's repro).
  fill_history()
  table.remove(items)
  local first_mined = depot(740)
  first_mined.name = "jatz-request-depot"
  fire("on_built_entity", { entity = first_mined })
  freighters_in(first_mined, 2)
  game.tick = 9000
  hand_mine(first_mined)
  new_item({ removal("jatz-request-depot", 740.5, 0.5) })
  local bare_mined = depot(740)
  bare_mined.name = "jatz-request-depot"
  fire("on_built_entity", { entity = bare_mined })
  freighters_in(bare_mined, 0)
  hand_mine(bare_mined)
  new_item({ removal("jatz-request-depot", 740.5, 0.5) })
  fire("on_tick", { tick = 9001 })
  local both = kept_at(740.5)
  check("at the history's limit, two hand minings at one spot each keep their own", both[1] == 0 and both[2] == 2)
  -- A hand mining, then a replacement at its spot marked in the tagging's tick, at the limit.
  local at_limit = depot(750)
  at_limit.name = "jatz-request-depot"
  fire("on_built_entity", { entity = at_limit })
  freighters_in(at_limit, 3)
  game.tick = 9100
  hand_mine(at_limit)
  new_item({ removal("jatz-request-depot", 750.5, 0.5) })
  local marked_later = depot(750)
  marked_later.name = "jatz-request-depot"
  fire("on_built_entity", { entity = marked_later })
  freighters_in(marked_later, 0)
  game.tick = 9101
  fire("on_marked_for_deconstruction", { entity = marked_later, player_index = 20 })
  new_item({ removal("jatz-request-depot", 750.5, 0.5) })
  fire("on_tick", { tick = 9101 })
  local mined_and_marked = kept_at(750.5)
  check(
    "and a replacement marked at a mined depot's spot before its tagging leaves it its own",
    mined_and_marked[1] == "untagged" and mined_and_marked[2] == 3
  )
  -- Robots take the replacement after more items pushed the oldest out: its action is found by
  -- its mark, reading no undo item.
  for _ = 1, 5 do
    new_item({ removal("wooden-chest", 50.5, 50.5) })
  end
  local reads_before = reads
  robot_takes(marked_later)
  local taken = kept_at(750.5)
  check("robots taking a marked depot at the limit find its action by its mark", taken[1] == 0 and taken[2] == 3)
  check("reading no undo item", reads == reads_before)

  -- A depot with 2 freighters mined by hand at one tick, a bare one at its spot the next, before
  -- that tick's tagging: each keeps its own, not swapped.
  local earlier = depot(760)
  earlier.name = "jatz-request-depot"
  fire("on_built_entity", { entity = earlier })
  freighters_in(earlier, 2)
  game.tick = 9300
  hand_mine(earlier)
  new_item({ removal("jatz-request-depot", 760.5, 0.5) })
  local later = depot(760)
  later.name = "jatz-request-depot"
  fire("on_built_entity", { entity = later })
  freighters_in(later, 0)
  game.tick = 9301
  hand_mine(later)
  new_item({ removal("jatz-request-depot", 760.5, 0.5) })
  fire("on_tick", { tick = 9301 })
  fire("on_tick", { tick = 9302 })
  local adjacent = kept_at(760.5)
  check("two hand minings at one spot in adjacent ticks each keep their own", adjacent[1] == 0 and adjacent[2] == 2)

  for name, handler in pairs(deliveries) do
    logistics[name] = handler
  end
  surface.find_entities_filtered = function()
    return {}
  end
end

print("all control event checks passed")
