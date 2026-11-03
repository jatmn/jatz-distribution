-- SPDX-License-Identifier: LGPL-3.0-only
-- Shared names and asset locations for the data stage.
return {
  mod_name = "jatz-distribution",
  subgroup = "jatz-distribution",
  freighter_sheets = "assets/quinityn-freighter/sheets/",
  -- string.format pattern taking (role, size), relative to the mod root.
  depot_sheets = "assets/depots/%s/%d/sheets/",
  connector_sheets = "assets/depots/connectors/sheets/",
}
