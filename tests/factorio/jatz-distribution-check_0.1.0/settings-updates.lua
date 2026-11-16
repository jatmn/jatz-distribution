-- SPDX-License-Identifier: LGPL-3.0-only
-- luacheck: globals data
-- The check runs with the depots' slot and tank size settings at different, non-default values,
-- so each must reach its own depot (control.lua: slot_counts, tank_sizes). Item depots get more
-- slots than the default 48, so every delivery check still has room; the Fuel depot fewer.
data.raw["int-setting"]["jatz-liquid-provider-depot-capacity"].default_value = 40000
data.raw["int-setting"]["jatz-liquid-request-depot-capacity"].default_value = 35000
data.raw["int-setting"]["jatz-liquid-buffer-depot-capacity"].default_value = 15000
data.raw["int-setting"]["jatz-fuel-depot-capacity"].default_value = 30000
data.raw["int-setting"]["jatz-provider-depot-slots"].default_value = 60
data.raw["int-setting"]["jatz-request-depot-slots"].default_value = 52
data.raw["int-setting"]["jatz-buffer-depot-slots"].default_value = 56
data.raw["int-setting"]["jatz-fuel-depot-slots"].default_value = 24
-- Exercise upward buffer transfers in the engine; the Lua tests also cover the disabled default.
assert(data.raw["bool-setting"]["jatz-buffer-priority-pull"].default_value == false)
data.raw["bool-setting"]["jatz-buffer-priority-pull"].default_value = true
