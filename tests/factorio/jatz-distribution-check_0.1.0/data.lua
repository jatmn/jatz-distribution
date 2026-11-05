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
})
