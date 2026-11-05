-- SPDX-License-Identifier: LGPL-3.0-only
-- Runs after every mod's data and data-updates stage.
require("prototypes.placement")
require("prototypes.off-road")
-- Each item's and fluid's freighter paint, once every mod's items exist.
require("prototypes.freighter-colors").extend()
