-- SPDX-License-Identifier: LGPL-3.0-only
-- Runs after every mod's data and data-updates stage.
require("prototypes.placement")
require("prototypes.off-road")
-- Freighters fill up with any fluid that burns. The base game has none, so petroleum gas burns at
-- 0.4 MJ a unit (a full 20 MJ tank is 50, Transport Drones' fuel per drone), unless another mod
-- (Krastorio 2, say) has given it a fuel value of its own.
local gas = data.raw.fluid["petroleum-gas"]
if gas and require("util").parse_energy(gas.fuel_value or "0J") == 0 then
  gas.fuel_value = "400kJ"
end
-- Each item's and fluid's freighter paint, once every mod's items exist.
require("prototypes.freighter-colors").extend()
