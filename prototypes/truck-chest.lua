-- SPDX-License-Identifier: LGPL-3.0-only
-- The truck chest: an invisible ten-slot chest under each liquid request and liquid buffer depot.
-- Liquid depots are storage tanks, which have no item inventory, so construction robots have
-- nowhere to bring freighters to. scripts/logistics.lua makes one of these at the depot's centre
-- and asks robots to bring freighters into it, from where they move into the depot's freighter
-- slot, exactly as with a request depot's own chest. It can't be seen, selected, mined, built or
-- blueprinted, collides with nothing, and inserters ignore it; it goes with its depot.
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
    -- Ten stacks of freighters (they stack to 10): a depot's whole slot.
    inventory_size = 10,
    picture = util.empty_sprite(),
  },
})
