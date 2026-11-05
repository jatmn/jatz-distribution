-- SPDX-License-Identifier: LGPL-3.0-only
-- Which paint a freighter wears for each item and fluid it can carry (scripts/freighter-paint.lua),
-- worked out from every mod's data in data-final-fixes and handed to the runtime as the mod-data
-- prototype "jatz-freighter-colors": { items = { [item] = drone }, fluids = { [fluid] = drone } }.
-- Anything not listed gets the artwork's slate blue.
--
-- This works from the data alone, so the items of overhaul mods (Bob's, Angel's, Krastorio 2)
-- get colors as well as the base game's. It aims at what freighters haul: ores, plates and other
-- intermediates, and fluids. Buildings often come out slate blue, which matters less.
--
-- Fluids have their own color (base_color, as fluid bars and wagons show it). Items have none, so
-- an item's color is the first of:
-- 1. A color of its own below: base game ores and plates (whatever an overhaul does to their
--    recipes, their icons don't change), and base game and Space Age items no rule colors well.
-- 2. The map color of the resource it is mined from (iron ore blue-grey, copper ore orange).
-- 3. The fluid it holds: a barrel, emptied by a recipe giving back the fluid and the container.
-- 4. A recipe making it: the recipe's crafting tint (sulfur yellow, plastic white), as a chemical
--    plant shows its recipe; otherwise the color of its one item ingredient (iron plate from iron
--    ore, copper cable from copper plate), or of its one fluid ingredient if it has no item ones;
--    otherwise its main item ingredient's: a mined one first (titanium plate from rutile ore, not
--    from the calcium chloride beside it), then the largest amount (brass from its copper), the
--    first with a color. Recipes are tried with the one named after the item first, then by
--    name, until one gives a color. Recycling recipes, and recipes with several products (but for
--    their main product), don't count.
local paint = require("scripts.freighter-paint")

local colors = {}

-- Items whose color everyone knows but no rule finds: base game ores and plates (overhauls such as
-- Angel's remove their resources or remake them from other ores), circuits and science packs made
-- from several ingredients without a crafting tint, uranium from a recipe with two products, wood
-- and Space Age's plants that grow.
local IRON, COPPER = { 0.415, 0.525, 0.58 }, { 0.803, 0.388, 0.215 }
local STONE = { 0.69, 0.611, 0.427 }
colors.own = {
  ["iron-ore"] = IRON,
  ["iron-plate"] = IRON,
  ["steel-plate"] = IRON,
  ["copper-ore"] = COPPER,
  ["copper-plate"] = COPPER,
  ["coal"] = { 0, 0, 0 },
  ["stone"] = STONE,
  ["stone-brick"] = STONE,
  ["uranium-ore"] = { 0, 0.7, 0 },
  ["wood"] = { 0.55, 0.36, 0.2 },
  ["electronic-circuit"] = { 0.2, 0.7, 0.25 },
  ["advanced-circuit"] = { 0.8, 0.2, 0.2 },
  ["processing-unit"] = { 0.2, 0.4, 0.9 },
  ["uranium-235"] = { 0.3, 0.9, 0.2 },
  ["uranium-238"] = { 0.1, 0.5, 0.1 },
  ["space-science-pack"] = { 0.9, 0.9, 0.9 },
  ["metallurgic-science-pack"] = { 1, 0.5, 0.1 },
  ["electromagnetic-science-pack"] = { 0.9, 0.2, 0.8 },
  ["holmium-ore"] = { 0.9, 0.45, 0.6 },
  ["ice"] = { 0.7, 0.85, 0.95 },
  ["yumako"] = { 0.85, 0.2, 0.2 },
  ["yumako-mash"] = { 0.8, 0.3, 0.2 },
  ["jellynut"] = { 0.6, 0.3, 0.7 },
  ["jelly"] = { 0.8, 0.4, 0.8 },
  ["spoilage"] = { 0.4, 0.4, 0.2 },
}

local function sorted_keys(map)
  local keys = {}
  for key in pairs(map or {}) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

local function entries(list)
  local found = {}
  for _, entry in ipairs(type(list) == "table" and list or {}) do
    if type(entry) == "table" and type(entry.name) == "string" then
      found[#found + 1] = entry
    end
  end
  return found
end

local function of_type(list, kind)
  local found = {}
  for _, entry in ipairs(list) do
    if entry.type == kind then
      found[#found + 1] = entry
    end
  end
  return found
end

local function recycling(recipe)
  for _, category in ipairs(type(recipe.categories) == "table" and recipe.categories or {}) do
    if category == "recycling" then
      return true
    end
  end
  return false
end

-- { [item] = drone }, { [fluid] = drone } for `raw` (data.raw). `item_types` lists the prototype
-- types that are items (the keys of defines.prototypes.item).
function colors.derive(raw, item_types)
  local fluids = {}
  for _, name in ipairs(sorted_keys(raw.fluid)) do
    if not raw.fluid[name].parameter then
      fluids[name] = paint.drone_for(raw.fluid[name].base_color)
    end
  end

  local items = {}
  for _, kind in ipairs(item_types) do
    for name, item in pairs(raw[kind] or {}) do
      if not item.parameter then
        items[name] = true
      end
    end
  end

  -- Resources by name: the first to give an item colors it.
  local mined = {}
  for _, name in ipairs(sorted_keys(raw.resource)) do
    local resource = raw.resource[name]
    local minable = resource.minable or {}
    -- As the engine does, `results` wins over `result`.
    local results = entries(minable.results)
    if #results == 0 and type(minable.result) == "string" then
      results = { { type = "item", name = minable.result } }
    end
    for _, result in ipairs(results) do
      if (result.type or "item") == "item" and resource.map_color and not mined[result.name] then
        mined[result.name] = resource.map_color
      end
    end
  end

  -- What makes each item, and which fluid each container holds.
  local makers, holds = {}, {}
  for _, name in ipairs(sorted_keys(raw.recipe)) do
    local recipe = raw.recipe[name]
    if not recycling(recipe) and not recipe.parameter then
      local ingredients, results = entries(recipe.ingredients), entries(recipe.results)
      local result_items, result_fluids = of_type(results, "item"), of_type(results, "fluid")
      if #ingredients == 1 and ingredients[1].type == "item" and #result_items == 1 and #result_fluids == 1 then
        holds[ingredients[1].name] = holds[ingredients[1].name] or result_fluids[1].name
      end
      local made
      if #results == 1 and #result_items == 1 then
        made = result_items[1].name
      elseif type(recipe.main_product) == "string" then
        for _, result in ipairs(result_items) do
          if result.name == recipe.main_product then
            made = result.name
          end
        end
      end
      if made then
        makers[made] = makers[made] or {}
        table.insert(makers[made], name)
      end
    end
  end
  for item, list in pairs(makers) do
    table.sort(list, function(a, b)
      if (a == item) ~= (b == item) then
        return a == item
      end
      return a < b
    end)
  end

  local function amount(entry)
    local value = tonumber(entry.amount)
    if not value and tonumber(entry.amount_min) and tonumber(entry.amount_max) then
      value = (entry.amount_min + entry.amount_max) / 2
    end
    return value or 1
  end

  local found, visiting = {}, {}
  local color
  -- The color of a recipe's main item ingredient: a mined one first, then the largest amount, then
  -- the first listed, the first that has a color.
  local function main_ingredient(solids)
    local order = {}
    for index, entry in ipairs(solids) do
      order[index] = { entry = entry, index = index, mined = mined[entry.name] ~= nil, amount = amount(entry) }
    end
    table.sort(order, function(a, b)
      if a.mined ~= b.mined then
        return a.mined
      end
      if a.amount ~= b.amount then
        return a.amount > b.amount
      end
      return a.index < b.index
    end)
    for _, candidate in ipairs(order) do
      local result = color(candidate.entry.name)
      if result then
        return result
      end
    end
  end

  function color(item)
    if found[item] ~= nil or visiting[item] then
      return found[item] or nil
    end
    visiting[item] = true
    local result
    if colors.own[item] then
      result = colors.own[item]
    elseif mined[item] then
      result = mined[item]
    elseif holds[item] and raw.fluid and raw.fluid[holds[item]] then
      result = raw.fluid[holds[item]].base_color
    else
      -- Each recipe in turn: its crafting tint, else its one ingredient's color.
      for _, name in ipairs(makers[item] or {}) do
        local maker = raw.recipe[name]
        local ingredients = entries(maker.ingredients)
        local solids, liquids = of_type(ingredients, "item"), of_type(ingredients, "fluid")
        if type(maker.crafting_machine_tint) == "table" and maker.crafting_machine_tint.primary then
          result = maker.crafting_machine_tint.primary
        elseif #solids == 1 then
          result = color(solids[1].name)
        elseif #solids == 0 and #liquids == 1 and raw.fluid and raw.fluid[liquids[1].name] then
          result = raw.fluid[liquids[1].name].base_color
        elseif #solids > 1 then
          result = main_ingredient(solids)
        end
        if result then
          break
        end
      end
    end
    visiting[item] = nil
    found[item] = result or false
    return result
  end

  local drones = {}
  for _, item in ipairs(sorted_keys(items)) do
    drones[item] = paint.drone_for(color(item))
  end
  return drones, fluids
end

-- Add the mod-data prototype for the runtime.
function colors.extend()
  local item_types = sorted_keys(defines.prototypes.item)
  local items, fluids = colors.derive(data.raw, item_types)
  data:extend({
    {
      type = "mod-data",
      name = paint.colors,
      data_type = "jatz-distribution.freighter-colors",
      data = { items = items, fluids = fluids },
    },
  })
end

return colors
