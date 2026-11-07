-- SPDX-License-Identifier: LGPL-3.0-only
-- The truck chest: an invisible chest under each request and buffer depot, item and liquid.
-- Construction robots bring freighters into it, never into the depot itself: liquid depots are
-- storage tanks, which have no item inventory, and inserters unloading an item depot's chest would
-- take freighters out of it before they reach the slot. scripts/logistics.lua makes one at the
-- depot's centre and asks robots to bring freighters into it, from where they move into the
-- depot's freighter slot. It can't be seen, selected, mined, built or blueprinted, collides with
-- nothing, and inserters ignore it; it goes with its depot.
local util = require("util")
local constants = require("prototypes.constants")

data:extend({
  {
    type = "container",
    name = constants.truck_chest,
    icon = constants.freighter_icon,
    icon_size = constants.icon_size,
    hidden = true,
    flags = {
      "placeable-off-grid",
      "not-on-map",
      "not-blueprintable",
      "not-deconstructable",
      "not-repairable",
      "not-flammable",
      "hide-alt-info",
      "no-automated-item-removal",
      "no-automated-item-insertion",
      "no-copy-paste",
    },
    selectable_in_game = false,
    allow_copy_paste = false,
    max_health = 100,
    collision_box = { { -0.1, -0.1 }, { 0.1, 0.1 } },
    collision_mask = { layers = {} },
    -- Twenty stacks of freighters (they stack to 10): room to ask for a depot's whole slot (100) a
    -- stack at a time, even with stacks already taken by part-stacks requested or leaving.
    inventory_size = 20,
    picture = util.empty_sprite(),
  },
})
