-- SPDX-License-Identifier: LGPL-3.0-only
local constants = require("prototypes.constants")

-- Placeholder group and order: data-final-fixes.lua moves this row directly above the
-- vanilla car and tank row once every mod has finished changing the data.
data:extend({
  {
    type = "item-subgroup",
    name = constants.subgroup,
    group = "logistics",
    order = "f",
  },
})
