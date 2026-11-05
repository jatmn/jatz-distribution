-- SPDX-License-Identifier: LGPL-3.0-only
-- A sticker like acid splash, mild enough not to upset the deliveries: the check mod sticks it to
-- a freighter on its way out, and it must still be on the freighter, hurting it, after loading
-- swaps it for a painted one (scripts/logistics.lua, repaint).
data:extend({
  {
    type = "sticker",
    name = "jatz-check-sticker",
    hidden = true,
    duration_in_ticks = 1200,
    target_movement_modifier = 0.9,
    damage_per_tick = { amount = 0.1, type = "acid" },
  },
})
