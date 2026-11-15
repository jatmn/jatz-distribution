-- SPDX-License-Identifier: LGPL-3.0-only
-- The shortcut bar button that opens and closes the freighter network window
-- (scripts/network-gui.lua). Its icon is the freighter's.
local constants = require("prototypes.constants")

data:extend({
  {
    type = "shortcut",
    name = "jatz-network",
    localised_name = { "shortcut-name.jatz-network" },
    order = "z[jatz]-a[network]",
    action = "lua",
    toggleable = true,
    technology_to_unlock = "jatz-freight-system",
    icon = constants.freighter_icon,
    icon_size = constants.icon_size,
    small_icon = constants.freighter_icon,
    small_icon_size = constants.icon_size,
  },
})
