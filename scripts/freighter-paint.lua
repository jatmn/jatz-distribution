-- SPDX-License-Identifier: LGPL-3.0-only
-- The delivering freighter's cargo paint: light grey while it is empty, and the color of what it
-- carries once it has loaded, as a chemical plant's tank or a pipe window shows its fluid.
-- Factorio has no per-entity color for units (LuaEntity::color covers cars, trains and a few
-- others), so each paint is its own drone prototype: the same unit with the artwork's cargo mask
-- tinted differently (prototypes/freighter-drone.lua). scripts/logistics.lua swaps a freighter
-- for the one in the right paint when it loads.
--
-- The paints are a fixed palette rather than one per item, so the prototypes never change with
-- the mods installed and a freighter on the road is never removed by a mod change. Each color
-- channel is rounded to one of six steps (0, 0.2, ... 1): 216 painted drones, plus the empty one
-- and one in the artwork's own slate blue for cargo with no known color.
-- Shared by the data stage (prototypes) and the runtime (scripts/logistics.lua).
local paint = {}

-- The empty freighter keeps the original prototype name, so freighters in older saves stay valid.
paint.empty = "jatz-freighter-drone"
paint.empty_color = { r = 0.8, g = 0.8, b = 0.8, a = 1 }
-- Loaded with something no rule gives a color to: the artwork's default cargo paint.
paint.unknown = paint.empty .. "-loaded"
-- The mod-data prototype holding each item's and fluid's paint (prototypes/freighter-colors.lua).
paint.colors = "jatz-freighter-colors"

local STEPS = 5

-- A Factorio Color (a table with r, g and b, or an array; 0 to 255 if any value is above 1) as
-- r, g and b from 0 to 1.
function paint.normalize(color)
  if type(color) ~= "table" then
    return nil
  end
  local r = tonumber(color.r or color[1]) or 0
  local g = tonumber(color.g or color[2]) or 0
  local b = tonumber(color.b or color[3]) or 0
  if r > 1 or g > 1 or b > 1 then
    r, g, b = r / 255, g / 255, b / 255
  end
  local function clamp(value)
    return math.max(0, math.min(1, value))
  end
  return clamp(r), clamp(g), clamp(b)
end

local function step(value)
  return math.floor(value * STEPS + 0.5)
end

local function name_of(r, g, b)
  return string.format("%s-%d%d%d", paint.empty, r, g, b)
end

-- The painted drone nearest to `color`, or nil if it isn't a color.
function paint.drone_for(color)
  local r, g, b = paint.normalize(color)
  if not r then
    return nil
  end
  return name_of(step(r), step(g), step(b))
end

-- Every painted drone: { name = ..., color = { r, g, b, a } }.
function paint.palette()
  local list = {}
  for r = 0, STEPS do
    for g = 0, STEPS do
      for b = 0, STEPS do
        list[#list + 1] = { name = name_of(r, g, b), color = { r = r / STEPS, g = g / STEPS, b = b / STEPS, a = 1 } }
      end
    end
  end
  return list
end

-- Every delivering freighter's prototype name: empty, unknown and painted.
function paint.names()
  local names = { paint.empty, paint.unknown }
  for _, entry in ipairs(paint.palette()) do
    names[#names + 1] = entry.name
  end
  return names
end

local DRONES = {}
for _, name in ipairs(paint.names()) do
  DRONES[name] = true
end

function paint.is_drone(name)
  return DRONES[name] == true
end

-- Runtime: the drone for a load of item or fluid `name` (fluid if `fluid` is set). Read once from
-- the mod-data prototype; prototypes are the same for every player, so this cache is too.
local colors
function paint.drone_for_cargo(fluid, name)
  if not colors then
    local found = prototypes.mod_data[paint.colors]
    colors = found and found.data or {}
  end
  local kind = colors[fluid and "fluids" or "items"]
  return kind and kind[name] or paint.unknown
end

return paint
