-- SPDX-License-Identifier: LGPL-3.0-only
-- Jat'z Distribution runtime: loading zones (scripts/loading-zone.lua), deliveries between
-- provider and request depots (scripts/logistics.lua) and the request panel
-- (scripts/request-gui.lua).
local loading_zone = require("scripts.loading-zone")
local logistics = require("scripts.logistics")
local request_gui = require("scripts.request-gui")

local function on_built(event)
  local entity = event.entity or event.destination
  if entity and entity.valid then
    if loading_zone.depots[entity.name] then
      loading_zone.clear(entity)
    end
    logistics.add(entity)
  end
end

-- Turning or flipping a depot moves its loading zone.
local function on_turned(event)
  local entity = event.entity
  if entity and entity.valid and loading_zone.depots[entity.name] then
    loading_zone.clear(entity)
  end
end

local filters = {}
for name in pairs(loading_zone.depots) do
  filters[#filters + 1] = { filter = "name", name = name }
end
-- Every way a depot can be built: by hand, robots, other mods' scripts, revived ghosts, platforms.
for _, event in ipairs({
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive,
  defines.events.on_space_platform_built_entity,
}) do
  script.on_event(event, on_built, filters)
end
local clone_filters = { { filter = "name", name = logistics.drone } }
for _, filter in ipairs(filters) do
  clone_filters[#clone_filters + 1] = filter
end
-- Another mod cloning a depot (or a whole area): the clone is a new depot with the original's
-- request. A cloned freighter has no trip, so it is removed.
script.on_event(defines.events.on_entity_cloned, function(event)
  local entity = event.destination
  if entity.valid then
    if loading_zone.depots[entity.name] then
      loading_zone.clear(entity)
    end
    logistics.on_cloned(event.source, entity)
  end
end, clone_filters)
script.on_event(defines.events.on_player_rotated_entity, on_turned)
script.on_event(defines.events.on_player_flipped_entity, on_turned)
script.on_event(defines.events.on_entity_settings_pasted, logistics.on_entity_settings_pasted)
logistics.register()
request_gui.register()

local function setup()
  logistics.init()
  loading_zone.clear_all()
end
script.on_init(setup)
script.on_configuration_changed(setup)
