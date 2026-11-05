-- SPDX-License-Identifier: LGPL-3.0-only
-- Jat'z Distribution settings stage. The tank sizes are startup settings because they are
-- prototype values (prototypes/depots.lua reads them); the liquid request depot keeps 25,000.
-- Whether players can place the freighter as a car is one too (prototypes/freighter.lua).
data:extend({
  {
    type = "int-setting",
    name = "jatz-liquid-provider-depot-capacity",
    setting_type = "startup",
    default_value = 25000,
    minimum_value = 1000,
    maximum_value = 1000000,
    order = "a[liquid]-a[provider]",
  },
  {
    type = "int-setting",
    name = "jatz-liquid-buffer-depot-capacity",
    setting_type = "startup",
    default_value = 25000,
    minimum_value = 1000,
    maximum_value = 1000000,
    order = "a[liquid]-b[buffer]",
  },
  {
    type = "bool-setting",
    name = "jatz-freighter-drivable",
    setting_type = "startup",
    default_value = false,
    order = "b[freighter]",
  },
})
