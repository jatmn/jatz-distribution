-- SPDX-License-Identifier: LGPL-3.0-only
-- A sticker like fire, hitting every 10 ticks, mild enough not to upset the deliveries: the check
-- mod sticks it to a freighter on its way to load, and loading must leave it, and the freighter it
-- is stuck to, as they were (scripts/logistics.lua, repaint).
data:extend({
  {
    type = "sticker",
    name = "jatz-check-sticker",
    hidden = true,
    duration_in_ticks = 1200,
    damage_interval = 10,
    target_movement_modifier = 0.9,
    damage_per_tick = { amount = 0.1, type = "acid" },
  },
  -- An item stacking to 100 million, as a mod can make: a request depot's 48 stacks of it (4.8
  -- billion) let a request pass a condition's int32 constant, which no base item can.
  {
    type = "item",
    name = "jatz-check-crate",
    hidden = true,
    icon = "__base__/graphics/icons/wooden-chest.png",
    stack_size = 100000000,
  },
})
