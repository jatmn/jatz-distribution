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
local nth = {}
script = {
  on_event = function(event, handler)
    handlers[event] = handler
  end,
  on_nth_tick = function(ticks, handler)
    nth[ticks] = handler
  end,
  on_init = function() end,
  on_configuration_changed = function() end,
  register_on_object_destroyed = function() end,
}
remote = { add_interface = function() end }
prototypes = { decorative = {}, item = {}, entity = {} }

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
function surface.find_decoratives_filtered()
  return {}
end
function surface.find_entities_filtered()
  return {}
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
    is_empty = function()
      return slot.count == 0
    end,
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
    get_inventory = function()
      return {
        get_item_count = function()
          return 0
        end,
      }
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
  prototypes.item[freighter] = { name = freighter }
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

do -- A panel opened before an update that changed its layout is rebuilt, with its status light.
  -- A minimal GUI: elements with children by name, add and destroy.
  local function element(spec, parent)
    local self = { children = {}, style = {}, parent = parent }
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

do -- The line beside the freighter slot: how many are out on the road, always.
  local caption = require("scripts.request-gui").freighter_caption
  local none, some = caption(0), caption(3)
  -- Exactly the one localised "N out", nothing before or after it.
  check("none out still says so", #none == 2 and none[1] == "jatz-gui.freighters-out" and none[2] == 0)
  check("three out", #some == 2 and some[1] == "jatz-gui.freighters-out" and some[2] == 3)
end

do -- Copy and paste: settings, blueprints, and depots built from blueprint ghosts.
  local logistics = require("scripts.logistics")
  prototypes.item.wood = { name = "wood" }
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
  check(
    "and the freighters as an insert plan into the chest",
    planned.items[1].id.name == "jatz-quinityn-freighter" and planned.items[1].items.in_inventory[1].count == 3
  )

  -- A depot built from that ghost takes the request from its tags.
  local built = depot(100)
  built.name = "jatz-request-depot"
  fire("on_robot_built_entity", { entity = built, tags = planned.tags })
  local request = logistics.get_request(built)
  check(
    "a depot built from a blueprint ghost has its request",
    request and request.item == "wood" and request.count == 7
  )
end

print("all control event checks passed")
