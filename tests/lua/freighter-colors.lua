-- SPDX-License-Identifier: LGPL-3.0-only
-- The freighter's cargo paint for each item and fluid (prototypes/freighter-colors.lua, with the
-- palette in scripts/freighter-paint.lua), worked out from a small fake of data.raw.
-- Run from the repository root with Lua 5.2 (tools/test_mod_setup.py does): lua5.2 tests/lua/freighter-colors.lua
package.path = "./?.lua;" .. package.path

local paint = require("scripts.freighter-paint")
local colors = require("prototypes.freighter-colors")

local function check(name, condition)
  if not condition then
    error("FAILED: " .. name, 2)
  end
  print("ok   " .. name)
end

local function item(name)
  return { type = "item", name = name, stack_size = 50 }
end

local function recipe(name, ingredients, results, extra)
  local self = { type = "recipe", name = name, ingredients = ingredients, results = results }
  for key, value in pairs(extra or {}) do
    self[key] = value
  end
  return self
end

local function I(name, amount)
  return { type = "item", name = name, amount = amount or 1 }
end

local function F(name, amount)
  return { type = "fluid", name = name, amount = amount or 10 }
end

local raw = {
  fluid = {
    water = { name = "water", base_color = { 0, 0.34, 0.6 } },
    ["crude-oil"] = { name = "crude-oil", base_color = { r = 0, g = 0, b = 0 } },
    goo = { name = "goo", base_color = { r = 255, g = 0, b = 255 } },
    ["parameter-0"] = { name = "parameter-0", base_color = { 1, 1, 0 }, parameter = true },
  },
  resource = {
    ["blue-ore"] = { minable = { result = "blue-ore" }, map_color = { 0.415, 0.525, 0.58 } },
    ["red-ore"] = {
      minable = { results = { { type = "item", name = "red-ore", amount = 1 } } },
      map_color = { r = 0.803, g = 0.388, b = 0.215 },
    },
    ["crude-oil"] = { minable = { results = { { type = "fluid", name = "crude-oil" } } }, map_color = { 1, 1, 1 } },
    -- An overhaul's ore: results win over result, as in the engine.
    rutile = {
      minable = { result = "salt", results = { { type = "item", name = "rutile", amount = 1 } } },
      map_color = { 0.6, 0, 0.6 },
    },
    -- An overhaul gives a base game ore another color, and makes copper ore from its own ore.
    ["iron-ore"] = { minable = { result = "iron-ore" }, map_color = { 1, 1, 1 } },
  },
  item = {},
  ammo = { bullets = item("bullets") },
  recipe = {},
}
for _, name in ipairs({
  "blue-ore",
  "red-ore",
  "blue-plate",
  "blue-steel",
  "red-wire",
  "sulfur",
  "barrel",
  "crude-oil-barrel",
  "gadget",
  "salt",
  "rutile",
  "titanium",
  "iron-ore",
  "copper-ore",
  "copper-plate",
  "electronic-circuit",
  "goo-cube",
  "loop-a",
  "loop-b",
  "scrap",
  "scrapped",
  "recycled",
}) do
  raw.item[name] = item(name)
end
raw.item["parameter-0"] = { type = "item", name = "parameter-0", parameter = true }
for _, entry in ipairs({
  recipe("blue-plate", { I("blue-ore") }, { I("blue-plate") }),
  -- A tinted recipe with another name: the one named after the item comes first.
  recipe(
    "blue-plate-from-goo",
    { F("goo") },
    { I("blue-plate") },
    { crafting_machine_tint = { primary = { 1, 0, 0 } } }
  ),
  recipe("blue-steel", { I("blue-plate", 5) }, { I("blue-steel") }),
  recipe("red-plate", { I("red-ore") }, { I("red-wire", 2) }),
  recipe("sulfur", { F("water"), F("crude-oil") }, { I("sulfur") }, {
    crafting_machine_tint = { primary = { r = 1, g = 0.995, b = 0.089, a = 1 } },
  }),
  recipe("crude-oil-barrel", { I("barrel"), F("crude-oil") }, { I("crude-oil-barrel") }),
  recipe("empty-crude-oil-barrel", { I("crude-oil-barrel") }, { I("barrel"), F("crude-oil") }),
  recipe("gadget", { I("blue-plate"), I("red-wire", 3) }, { I("gadget") }),
  recipe("salt", { F("water") }, { I("salt") }),
  recipe("titanium", { I("salt", 5), I("rutile", 2) }, { I("titanium") }),
  recipe("copper-ore-from-blue", { I("blue-ore") }, { I("copper-ore") }),
  recipe("copper-plate", { I("copper-ore") }, { I("copper-plate") }),
  recipe("electronic-circuit", { I("blue-plate"), I("red-wire") }, { I("electronic-circuit") }),
  recipe("goo-cube", { F("goo") }, { I("goo-cube") }),
  recipe("loop-a", { I("loop-b") }, { I("loop-a") }),
  recipe("loop-b", { I("loop-a") }, { I("loop-b") }),
  -- Several products: none is made by it, unless it names a main product.
  recipe("scrap-sorting", { I("scrap") }, { I("blue-plate"), I("scrapped") }),
  recipe("scrap-main", { I("red-ore") }, { I("scrapped"), I("sulfur") }, { main_product = "scrapped" }),
  recipe("bullets", { I("blue-plate") }, { I("bullets") }),
  recipe("recycled", { I("sulfur") }, { I("recycled") }, { categories = { "recycling" } }),
}) do
  raw.recipe[entry.name] = entry
end

local items, fluids = colors.derive(raw, { "item", "ammo" })

check("palette: 216 painted freighters", #paint.palette() == 216)
check("plus the empty and the unknown", #paint.names() == 218 and paint.is_drone("jatz-freighter-drone-loaded"))
check("not other units", not paint.is_drone("small-biter"))
check("a color rounds to the nearest paint", paint.drone_for({ 0.41, 0.53, 0.58 }) == "jatz-freighter-drone-233")
check("0-255 colors are scaled", paint.drone_for({ r = 255, g = 102, b = 0 }) == "jatz-freighter-drone-520")

check(
  "fluids take their base color",
  fluids.water == "jatz-freighter-drone-023" and fluids.goo == "jatz-freighter-drone-505"
)
check("ores take their resource's map color", items["blue-ore"] == "jatz-freighter-drone-233")
check("from results too", items["red-ore"] == "jatz-freighter-drone-421")
check("a plate takes its ore's color, before another recipe's tint", items["blue-plate"] == items["blue-ore"])
check("through several steps", items["blue-steel"] == items["blue-ore"])
check("a product named differently from its recipe", items["red-wire"] == items["red-ore"])
check("a crafting tint colors its product", items.sulfur == "jatz-freighter-drone-550")
check("a barrel takes its fluid's color", items["crude-oil-barrel"] == "jatz-freighter-drone-000")
check("the empty barrel has none of its own", items.barrel == nil)
check("an item made from one fluid takes its color", items["goo-cube"] == fluids.goo)
check("an item made from several ingredients takes its main one's color", items.gadget == items["red-ore"])
check("a mined ingredient first, however few", items.titanium == "jatz-freighter-drone-303")
check("results win over result", items.salt ~= items.rutile and items.rutile == "jatz-freighter-drone-303")
check(
  "base game ores and plates keep their colors in an overhaul",
  items["iron-ore"] == "jatz-freighter-drone-233"
    and items["copper-ore"] == "jatz-freighter-drone-421"
    and items["copper-plate"] == items["copper-ore"]
)
check(
  "unless it has a color of its own",
  items["electronic-circuit"] == paint.drone_for(colors.own["electronic-circuit"])
)
check("a recipe loop gives no color", items["loop-a"] == nil and items["loop-b"] == nil)
check("a recipe with several products makes its main product", items.scrapped == items["red-ore"])
check("and nothing else", items.sulfur == "jatz-freighter-drone-550")
check("recycling makes nothing", items.recycled == nil)
check("every item type counts", items.bullets == items["blue-ore"])
check("parameters get no paint", items["parameter-0"] == nil and fluids["parameter-0"] == nil)
for name, drone in pairs(items) do
  check("item " .. name .. " gets a real freighter", paint.is_drone(drone))
end

print("all freighter color checks passed")
