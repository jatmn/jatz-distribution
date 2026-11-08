-- SPDX-License-Identifier: LGPL-3.0-only
-- Jat'z Distribution settings stage. Depot slot counts and tank sizes are startup settings because
-- they are prototype values (prototypes/depots.lua reads them); the liquid request depot keeps 25,000.
-- Slots stop at 1,000: deliveries and refuelling look through a depot's chest stack by stack.
-- Whether players can place the freighter as a car is one too (prototypes/freighter.lua).
-- Freighter fuel is runtime: scripts/logistics.lua reads it as freighters drive and refuel.
data:extend({
  {
    type = "int-setting",
    name = "jatz-provider-depot-slots",
    setting_type = "startup",
    default_value = 48,
    minimum_value = 1,
    maximum_value = 1000,
    order = "a[cargo]-a[provider]",
  },
  {
    type = "int-setting",
    name = "jatz-request-depot-slots",
    setting_type = "startup",
    default_value = 48,
    minimum_value = 1,
    maximum_value = 1000,
    order = "a[cargo]-b[request]",
  },
  {
    type = "int-setting",
    name = "jatz-buffer-depot-slots",
    setting_type = "startup",
    default_value = 48,
    minimum_value = 1,
    maximum_value = 1000,
    order = "a[cargo]-c[buffer]",
  },
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
    type = "int-setting",
    name = "jatz-fuel-depot-slots",
    setting_type = "startup",
    default_value = 48,
    minimum_value = 1,
    maximum_value = 1000,
    order = "a[refuel]-a[slots]",
  },
  {
    type = "int-setting",
    name = "jatz-fuel-depot-capacity",
    setting_type = "startup",
    default_value = 25000,
    minimum_value = 1000,
    maximum_value = 1000000,
    order = "a[refuel]-b[tank]",
  },
  {
    type = "bool-setting",
    name = "jatz-freighter-drivable",
    setting_type = "startup",
    default_value = false,
    order = "b[freighter]",
  },
  {
    -- In MJ. With the default use, a full tank lasts 2,000 tiles: what Transport Drones' default
    -- fuel per drone lasts (50 fuel at 0.025 a tile).
    type = "double-setting",
    name = "jatz-freighter-fuel-capacity",
    setting_type = "runtime-global",
    default_value = 20,
    minimum_value = 0.1,
    maximum_value = 100000,
    order = "b[fuel]-a[capacity]",
  },
  {
    -- In kJ per tile driven; 0 turns fuel off.
    type = "double-setting",
    name = "jatz-freighter-fuel-per-tile",
    setting_type = "runtime-global",
    default_value = 10,
    minimum_value = 0,
    maximum_value = 100000,
    order = "b[fuel]-b[use]",
  },
})
