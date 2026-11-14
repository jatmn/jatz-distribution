-- SPDX-License-Identifier: LGPL-3.0-only
-- Quality (Factorio 2.1's Quality mod; optional). Two things, kept apart:
--
-- What a request asks for. An item request or buffer depot can ask for its item at one quality, at
-- qualities compared with one (the game's quality comparators, "=", "≠", ">", "<", "≥", "≤", by the
-- qualities' levels, as the game's own item filters compare them: probed on 2.1.24), or at any
-- quality, as the game's logistic requests can. A request stores `quality` (nil for normal) and
-- `comparator` (nil for "=", "any" for any quality, which then has no quality), so a request from
-- before, or a normal one, is exactly what it always was. Freighters fetch what the request asks
-- for, whatever the quality of the depots or the freighter: a freighter's or depot's quality is
-- never the cargo's. Where a request takes several qualities, freighters take the highest first
-- (the owner's choice, November 13, 2026). Fluids have no quality.
--
-- What a freighter's quality gives: the game's default quality bonus, +30% a level (the quality's
-- `default_multiplier`, read from the game so modded qualities count too), to its cargo stacks
-- (rounded down, as the game rounds chest slots), fluid, speed and fuel tank (the owner's choice,
-- November 13, 2026); its health comes from the game itself, as the unit is made at its quality.
--
-- Promises, what freighters bring and providers' stock are kept by `key`: the item's name for
-- normal quality (as before quality), "item/quality" otherwise (prototype names hold only letters,
-- digits, dashes and underscores, so the slash can't be part of one), a fluid's name for a fluid.
local quality = {}

local NORMAL = "normal"
quality.normal = NORMAL
-- The comparator a request with any quality stores.
local ANY = "any"
quality.any = ANY
-- The quality comparators the request panel offers, in the order of the game's comparison list,
-- then "any quality". Read back the way the game writes them ("≠", "≥", "≤"); the API's ASCII forms
-- are accepted too.
quality.comparators = { "=", "≠", ">", "<", "≥", "≤", ANY }
local COMPARATORS = {
  ["="] = "=",
  ["≠"] = "≠",
  ["!="] = "≠",
  [">"] = ">",
  ["<"] = "<",
  ["≥"] = "≥",
  [">="] = "≥",
  ["≤"] = "≤",
  ["<="] = "≤",
  [ANY] = ANY,
}
local COMPARE = {
  ["="] = function(a, b)
    return a == b
  end,
  ["≠"] = function(a, b)
    return a ~= b
  end,
  [">"] = function(a, b)
    return a > b
  end,
  ["<"] = function(a, b)
    return a < b
  end,
  ["≥"] = function(a, b)
    return a >= b
  end,
  ["≤"] = function(a, b)
    return a <= b
  end,
}

-- The qualities items can have (not hidden ones, such as the game's "quality-unknown"; normal always,
-- which the base game without the Quality mod lists as hidden), highest level first (then by order,
-- then name): read from the game once a session, as prototypes don't change while it runs.
local visible
local function qualities()
  if not visible then
    visible = {}
    for name, prototype in pairs(prototypes.quality) do
      if name == NORMAL or not prototype.hidden then
        visible[#visible + 1] = { name = name, level = prototype.level or 0, order = prototype.order or "" }
      end
    end
    table.sort(visible, function(a, b)
      if a.level ~= b.level then
        return a.level > b.level
      end
      if a.order ~= b.order then
        return a.order > b.order
      end
      return a.name > b.name
    end)
  end
  return visible
end

-- Whether qualities other than normal exist (the Quality mod, or another mod's): only then does the
-- request panel offer a quality.
local any_other
function quality.available()
  if any_other == nil then
    any_other = false
    for _, known in ipairs(qualities()) do
      if known.name ~= NORMAL then
        any_other = true
      end
    end
  end
  return any_other
end

local function level(name)
  local prototype = prototypes.quality[name or NORMAL]
  return prototype and prototype.level or 0
end
quality.level = level

-- The game's default quality bonus for a freighter of quality `name` (nil: normal), 1 for normal or
-- a quality the game no longer has.
local multipliers = {}
function quality.multiplier(name)
  name = name or NORMAL
  local known = multipliers[name]
  if not known then
    local prototype = prototypes.quality[name]
    known = prototype and prototype.default_multiplier or 1
    multipliers[name] = known
  end
  return known
end

-- A request's quality and comparator as stored, after true: nil, nil for normal "=" (a request from
-- before), a quality only where it is not normal, a comparator only where it is not "=", and "any"
-- with no quality. False alone for a quality the game doesn't have (or a hidden one), or another
-- comparator. A quality may be given as its name or its LuaQualityPrototype.
function quality.normalize(name, comparator)
  if comparator == nil then
    comparator = "="
  end
  comparator = type(comparator) == "string" and COMPARATORS[comparator]
  if not comparator then
    return false
  end
  if comparator == ANY then
    return true, nil, ANY
  end
  if name == nil then
    name = NORMAL
  end
  if type(name) == "table" and name.object_name == "LuaQualityPrototype" then
    name = name.name
  end
  local prototype = type(name) == "string" and prototypes.quality[name]
  if not prototype or (prototype.hidden and name ~= NORMAL) then
    return false
  end
  return true, name ~= NORMAL and name or nil, comparator ~= "=" and comparator or nil
end

-- Whether a request is for normal quality only: everything works as before quality there.
local function plain(request)
  return request.quality == nil and request.comparator == nil
end
quality.plain = plain

-- A request's qualities as a filter: "" for a plain request (so caches keyed by it stay as they
-- were), else quality and comparator.
function quality.filter_id(request)
  if plain(request) then
    return ""
  end
  return (request.quality or NORMAL) .. " " .. (request.comparator or "=")
end

-- The qualities a request takes, highest first (a list of names; not to be changed).
local matching = {}
local function matching_of(request)
  local id = (request.quality or NORMAL) .. " " .. (request.comparator or "=")
  local found = matching[id]
  if not found then
    found = {}
    local comparator = request.comparator or "="
    local wanted = level(request.quality)
    for _, known in ipairs(qualities()) do
      if comparator == ANY or COMPARE[comparator](known.level, wanted) then
        found[#found + 1] = known.name
      end
    end
    -- A request for a quality the game no longer lists still means that one.
    if #found == 0 and comparator == "=" then
      found[1] = request.quality or NORMAL
    end
    matching[id] = found
  end
  return found
end
quality.matching = matching_of

-- Whether a request takes items of quality `name`.
function quality.takes(request, name)
  for _, known in ipairs(matching_of(request)) do
    if known == name then
      return true
    end
  end
  return false
end

-- The key promises and stock of an item of quality `name` are kept by (see above).
local function key(item, name)
  if name == nil or name == NORMAL then
    return item
  end
  return item .. "/" .. name
end
quality.key = key

-- The item and quality of a key.
function quality.split(stock_key)
  local item, name = stock_key:match("^(.-)/(.+)$")
  if item then
    return item, name
  end
  return stock_key, NORMAL
end

-- What the game's inventory calls take for a key (ItemWithQualityID): the name for normal quality,
-- which makes no table, or a table made once and kept (passed only to the game, never changed).
-- `quality.ids` is the table of those made, for hot paths to read before calling quality.id.
local ids = {}
quality.ids = ids
function quality.id(stock_key)
  local id = ids[stock_key]
  if not id then
    local item, name = quality.split(stock_key)
    id = name == NORMAL and item or { name = item, quality = name }
    ids[stock_key] = id
  end
  return id
end

-- A request's qualities as the game's ItemFilter (for LuaInventory.get_item_count_filtered), made
-- once per item and filter and kept.
local filters = {}
function quality.item_filter(request)
  local id = request.item .. " " .. quality.filter_id(request)
  local filter = filters[id]
  if not filter then
    if request.comparator == ANY then
      filter = { name = request.item }
    else
      filter = { name = request.item, quality = request.quality or NORMAL, comparator = request.comparator or "=" }
    end
    filters[id] = filter
  end
  return filter
end

-- The circuit signal key (scripts/depot-circuit.lua's) of a key.
function quality.signal(stock_key, fluid)
  if fluid then
    return "fluid/" .. stock_key .. "/" .. NORMAL
  end
  local item, name = quality.split(stock_key)
  return "item/" .. item .. "/" .. name
end

-- A quality the game has that no stack of `item` in `counts` (quality name -> count, as
-- LuaInventory.get_item_quality_counts gives) has: a chest's room for it is its empty stacks only.
-- The game's hidden "quality-unknown" is such a quality whenever it exists. Nil if every quality is
-- there.
function quality.absent(counts)
  for name in pairs(prototypes.quality) do
    if not counts[name] then
      return name
    end
  end
  return nil
end

-- A rich text quality icon, for tooltips.
function quality.icon(name)
  return "[quality=" .. (name or NORMAL) .. "]"
end

return quality
