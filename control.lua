-- SPDX-License-Identifier: LGPL-3.0-only
-- Jat'z Distribution runtime. Dispatch and cargo transfer will live in scripts/ too.
local loading_zone = require("scripts.loading-zone")

loading_zone.register()
script.on_init(loading_zone.clear_all)
script.on_configuration_changed(loading_zone.clear_all)
