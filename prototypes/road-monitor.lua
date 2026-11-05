-- SPDX-License-Identifier: LGPL-3.0-only
-- The road network monitor: a constant combinator, built on or beside road, that puts on its red
-- and green wires what the provider and buffer depots on that road network hold, like a roboport
-- reading its logistic network's contents. scripts/road-monitor.lua sets its signals once a
-- second; players can't edit them. It uses the base game's combinator graphics, with the road
-- icon in the corner of its own icon.
local constants = require("prototypes.constants")

local name = constants.road_monitor
local icons = {
  { icon = "__base__/graphics/icons/constant-combinator.png", icon_size = 64 },
  {
    icon = "__jatz-distribution__/" .. constants.road_art .. "pslag_icon.png",
    icon_size = 32,
    scale = 0.5,
    shift = { 8, 8 },
  },
}

local entity = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
entity.name = name
entity.icon = nil
entity.icons = icons
entity.minable = { mining_time = 0.1, result = name }
-- Not swapped for a constant combinator by building over it, nor upgraded into one.
entity.fast_replaceable_group = nil
entity.next_upgrade = nil

data:extend({
  entity,
  {
    type = "item",
    name = name,
    icons = icons,
    subgroup = constants.subgroup,
    -- After the road ("d[road]"): last in our row.
    order = "e[road-monitor]",
    place_result = name,
    stack_size = 50,
  },
  {
    -- Free while the mod is in development.
    type = "recipe",
    name = name,
    enabled = true,
    energy_required = 0.5,
    ingredients = {},
    results = { { type = "item", name = name, amount = 1 } },
  },
})
