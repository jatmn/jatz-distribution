-- SPDX-License-Identifier: LGPL-3.0-only
-- The road depots lay under their loading zone (scripts/depot-road.lua), against a small fake of
-- the Factorio runtime: turning, mining and covering by hand, and save upgrades, which the
-- headless check mod can't do without a player.
-- Run from the repository root with Lua 5.2 (tools/test_mod_setup.py does): lua5.2 tests/lua/depot-road.lua
package.path = "./?.lua;" .. package.path

defines = { direction = { north = 0, east = 4, south = 8, west = 12 } }
script = { register_on_object_destroyed = function() end }

local surface, next_unit

local function key(x, y)
  return x .. "," .. y
end

local function reset()
  next_unit = 0
  local tiles = {}
  surface = { index = 1, tiles = tiles }
  local function cell(x, y)
    tiles[key(x, y)] = tiles[key(x, y)] or { name = "grass-1" }
    return tiles[key(x, y)]
  end
  function surface.get_tile(x, y)
    local tile = cell(x, y)
    return {
      valid = true,
      name = tile.name,
      collides_with = function(layer)
        return layer == "water_tile" and tile.name == "water"
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
  surface.cell = cell
  storage = {}
  game = { surfaces = { [1] = surface } }
  function surface.find_entities_filtered()
    return surface.entities or {}
  end
  package.loaded["scripts.depot-road"] = nil
  return require("scripts.depot-road")
end

-- An unrotated depot at (0.5, 0.5): its loading zone is the tile (0, 2).
local function depot(x, y, direction)
  next_unit = next_unit + 1
  return {
    valid = true,
    unit_number = next_unit,
    position = { x = x or 0.5, y = y or 0.5 },
    direction = direction or defines.direction.north,
    surface = surface,
  }
end

local function name_at(x, y)
  return surface.cell(x, y).name
end

local function check(name, condition)
  if not condition then
    error("FAILED: " .. name, 2)
  end
  print("ok   " .. name)
end

do -- Laid on build, restored exactly on removal, hidden tiles included.
  local roads = reset()
  local cell = surface.cell(0, 2)
  cell.name, cell.hidden, cell.double = "concrete", "landfill", "water"
  local entity = depot()
  check("road is laid under the loading zone", roads.lay(entity) == 1 and name_at(0, 2) == "jatz-depot-road")
  check("removal reports the road gone", roads.lift(entity.unit_number) == 1)
  check(
    "and puts back the tile and both hidden tiles",
    cell.name == "concrete" and cell.hidden == "landfill" and cell.double == "water"
  )
end

do -- Ground without hidden tiles gets none from the road's stay.
  local roads = reset()
  local entity = depot()
  roads.lay(entity)
  surface.cell(0, 2).hidden = "grass-1" -- the engine hides the grass under the road
  roads.lift(entity.unit_number)
  check(
    "grass comes back with nothing hidden under it",
    name_at(0, 2) == "grass-1" and surface.cell(0, 2).hidden == nil
  )
end

do -- Turning a depot moves its road: the old spot gets its ground back.
  local roads = reset()
  local entity = depot()
  roads.lay(entity)
  entity.direction = defines.direction.east -- loading zone moves to (-2, 0)
  local laid, removed = roads.lay(entity)
  check("a turned depot lays road at its new loading zone", laid == 1 and name_at(-2, 0) == "jatz-depot-road")
  check("and lifts the old one", removed == 1 and name_at(0, 2) == "grass-1")
end

do -- Road or water already there: nothing is laid, and nothing is removed later.
  local roads = reset()
  surface.cell(0, 2).name = "jatz-road"
  local on_road = depot()
  check("nothing is laid over the player's road", roads.lay(on_road) == nil and name_at(0, 2) == "jatz-road")
  roads.lift(on_road.unit_number)
  check("and the player's road stays when the depot goes", name_at(0, 2) == "jatz-road")
  surface.cell(10, 2).name = "water"
  local on_water = depot(10.5, 0.5)
  check("nothing is laid on water", roads.lay(on_water) == nil and name_at(10, 2) == "water")
  surface.platform = {}
  check("nothing is laid on a space platform", roads.lay(depot(20.5, 0.5)) == nil and name_at(20, 2) == "grass-1")
end

do -- Two depots on one loading tile: the road stays until the last goes.
  local roads = reset()
  surface.cell(0, 2).name = "concrete"
  local first, second = depot(0.5, 0.5), depot(0.5, 4.5, defines.direction.south)
  roads.lay(first)
  roads.lay(second)
  check("the first removal keeps a shared road", roads.lift(first.unit_number) == nil)
  check("still road", name_at(0, 2) == "jatz-depot-road")
  check("the last removal puts back the concrete", roads.lift(second.unit_number) == 1 and name_at(0, 2) == "concrete")
end

do -- Covered by the player: theirs, kept on removal, and not laid again on reload.
  local roads = reset()
  local entity = depot()
  surface.entities = { entity }
  roads.lay(entity)
  surface.cell(0, 2).name = "stone-path"
  roads.covered(1, { x = 0, y = 2 })
  roads.lift(entity.unit_number)
  check("a tile placed over depot road stays when the depot goes", name_at(0, 2) == "stone-path")
  local other = depot(10.5, 0.5)
  roads.lay(other)
  surface.cell(10, 2).name = "stone-path"
  roads.covered(1, { x = 10, y = 2 })
  surface.entities = { other }
  check("a covered depot gets no new road on reload", next(roads.lay_all({})) == nil)
end

do -- Mined by hand: the ground it covered comes back, not just the hidden tile.
  local roads = reset()
  local cell = surface.cell(0, 2)
  cell.name, cell.hidden = "concrete", "grass-1"
  local entity = depot()
  surface.entities = { entity }
  roads.lay(entity)
  cell.name = "grass-1" -- mining reveals the hidden tile, losing the concrete
  roads.mined(1, { x = 0, y = 2 })
  check("mining the depot's road puts back the concrete", cell.name == "concrete" and cell.hidden == "grass-1")
  check("and the depot doesn't lay it again on reload", next(roads.lay_all({})) == nil)
end

do -- Depot road nobody owns (a cloned area): adopted, with its hidden tile as the ground.
  local roads = reset()
  local cell = surface.cell(0, 2)
  cell.name, cell.hidden = "jatz-depot-road", "dirt-1"
  local entity = depot()
  roads.lay(entity)
  check("adopted road is removed with its new depot", roads.lift(entity.unit_number) == 1 and cell.name == "dirt-1")
end

do -- A save from before depots laid road: existing depots get theirs once.
  local roads = reset()
  local entity = depot()
  surface.entities = { entity }
  check("existing depots get road on load", roads.lay_all({})[1] and name_at(0, 2) == "jatz-depot-road")
  check("only once", next(roads.lay_all({})) == nil)
end

do -- Mining it by hand puts back every layer, double-hidden tile included.
  local roads = reset()
  local cell = surface.cell(0, 2)
  cell.name, cell.hidden, cell.double = "concrete", "landfill", "water"
  roads.lay(depot())
  cell.name = "landfill" -- mining reveals the hidden tile
  roads.mined(1, { 0, 2 }) -- positions from scripts may be arrays
  check(
    "mining restores tile, hidden and double-hidden tiles",
    cell.name == "concrete" and cell.hidden == "landfill" and cell.double == "water"
  )
end

do -- A shared tile with no hidden tile keeps none, even if one lies deeper.
  local roads = reset()
  local cell = surface.cell(0, 2)
  cell.name = "concrete"
  local first, second = depot(0.5, 0.5), depot(0.5, 4.5, defines.direction.south)
  roads.lay(first)
  cell.double = "water" -- something deeper appears; the record says there was no hidden tile
  roads.lay(second)
  roads.lift(first.unit_number)
  roads.lift(second.unit_number)
  check("the shared record's missing hidden tile stays missing", cell.name == "concrete" and cell.hidden == nil)
end

do -- Records of depots whose road the player took are dropped when those depots go.
  local roads = reset()
  for index = 1, 3 do
    local entity = depot(index * 10 + 0.5, 0.5)
    roads.lay(entity)
    roads.covered(1, { x = index * 10, y = 2 })
    roads.lift(entity.unit_number)
  end
  check("no records are left behind", next(storage.depot_roads) == nil)
end

print("all depot road checks passed")
