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
script = {
  on_event = function(event, handler)
    handlers[event] = handler
  end,
  on_nth_tick = function() end,
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
game = { tick = 0, surfaces = { [1] = surface } }

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

print("all control event checks passed")
