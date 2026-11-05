-- SPDX-License-Identifier: LGPL-3.0-only
-- luacheck: globals data
-- The check runs with the liquid provider and liquid buffer depots' tank size settings at
-- different, non-default values, so each must reach its own depot (control.lua: tank_sizes).
data.raw["int-setting"]["jatz-liquid-provider-depot-capacity"].default_value = 40000
data.raw["int-setting"]["jatz-liquid-buffer-depot-capacity"].default_value = 15000
