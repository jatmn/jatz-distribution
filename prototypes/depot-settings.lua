-- SPDX-License-Identifier: LGPL-3.0-only
-- Depot request settings: a decider combinator that lives only in blueprints. Factorio's blueprint
-- parametrisation rewrites only the game's own entity settings, never a mod's tags, so a blueprint
-- of a request or buffer depot with a request or freighters also holds one of these at the depot's
-- centre (scripts/depot-settings.lua): its request as a condition comparing the item or fluid to
-- the amount, and its freighters as a condition with no signal, only the number. The game can then
-- turn the request's item or fluid and amount, and the freighters' number, into parameters, without
-- offering an item for the freighters (a constant combinator's slot needs one). Its ghost, built
-- with the depot's, hands them (parametrised or not) to the depot's ghost or depot and goes at
-- once, so none ever stands in the world. It can't be seen, selected or crafted, and collides with
-- nothing; the hidden item only lets blueprints hold it (the game refuses entities no item places).
local util = require("util")
local constants = require("prototypes.constants")

local name = constants.depot_settings
local icon = string.format(constants.depot_icon, "request")

local entity = table.deepcopy(data.raw["decider-combinator"]["decider-combinator"])
entity.name = name
entity.icon = icon
entity.icon_size = constants.icon_size
entity.icons = nil
entity.hidden = true
entity.flags = {
  "placeable-off-grid",
  "player-creation",
  "not-on-map",
  "not-deconstructable",
  "not-repairable",
  "not-flammable",
  "hide-alt-info",
  "no-copy-paste",
}
entity.selectable_in_game = false
entity.allow_copy_paste = false
entity.minable = nil
entity.fast_replaceable_group = nil
entity.next_upgrade = nil
entity.corpse = nil
entity.dying_explosion = nil
entity.collision_mask = { layers = {} }
for _, sprites in ipairs({
  "sprites",
  "activity_led_sprites",
  "equal_symbol_sprites",
  "greater_or_equal_symbol_sprites",
  "greater_symbol_sprites",
  "less_or_equal_symbol_sprites",
  "less_symbol_sprites",
  "not_equal_symbol_sprites",
}) do
  entity[sprites] = util.empty_sprite()
end
entity.activity_led_light = nil
entity.screen_light = nil
entity.placeable_by = { item = name, count = 1 }

data:extend({
  entity,
  {
    type = "item",
    name = name,
    icon = icon,
    icon_size = constants.icon_size,
    hidden = true,
    stack_size = 1,
    place_result = name,
  },
})
