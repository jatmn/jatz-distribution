-- SPDX-License-Identifier: LGPL-3.0-only
-- Depot settings in blueprints, copy and paste and undo: what a blueprint entry keeps of a depot
-- (its tags), and a depot built from a ghost taking them back. Split out of scripts/logistics.lua,
-- whose main chunk had reached Lua's limit of 200 locals (issue #69). logistics.lua keeps the entry
-- points (`logistics.setup_blueprint`, `logistics.apply_tags` and the others), and hands this
-- module the helpers it shares with it when it loads (blueprints.install).
local depot_circuit = require("scripts.depot-circuit")
local robot_requests = require("scripts.freighter-requests")
local robot_access = require("scripts.robot-access")
local switching = require("scripts.circuit-switch")

local blueprints = {}

local item_name, freighter_total = robot_requests.item_name, robot_requests.freighter_total

-- scripts/logistics.lua, and its helpers, from blueprints.install.
local logistics, request_depot, supplying_depot, PRIORITY_DEFAULT, FREIGHTER, LIQUID

function blueprints.install(owner, shared)
  logistics = owner
  request_depot, supplying_depot = shared.request_depot, shared.supplying_depot
  PRIORITY_DEFAULT, FREIGHTER, LIQUID = shared.priority_default, shared.freighter, shared.liquid
end

-- Blueprints (and copy and paste) of request depots keep their request and their freighters (in
-- the slot, out and coming) as tags: the depot built from the ghost asks robots for the freighters
-- into its truck chest (apply_tags), and they move into the slot. Blueprints from before also hold
-- them as an insert plan into the chest, which the depot built asks of its truck chest instead
-- (see trim_freighter_requests).
local REQUEST_TAG = "jatz_request"
local FREIGHTERS_TAG = "jatz_freighters"
local FROM_BUFFERS_TAG = "jatz_from_buffers"
local PRIORITY_TAG = "jatz_priority"
-- { enabled = true or nil, condition = CircuitCondition, mode = "contents" or nil }, when any is set.
local CIRCUIT_TAG = "jatz_circuit"
blueprints.request_tag = REQUEST_TAG
blueprints.freighters_tag = FREIGHTERS_TAG

-- A delivery depot's circuit settings as a blueprint tag, or nil if it has none.
local function circuit_tag(depot)
  local condition = depot.circuit_condition
  if not depot.circuit_enabled and not (condition and condition.first_signal) and not depot.circuit_mode then
    return nil
  end
  -- Always with a condition, so a ticked checkbox without one yet is kept too.
  return {
    enabled = depot.circuit_enabled or nil,
    condition = depot_circuit.condition(condition or {}),
    mode = depot.circuit_mode,
  }
end

-- Put an entity's settings on its blueprint entry (`planned`), as tags: a delivery depot's, or a
-- road network monitor's. Returns whether it has any to keep.
local function plan_settings(planned, entity)
  local depot = entity and entity.valid and request_depot(entity)
  local supplying = entity and entity.valid and supplying_depot(entity)
  local changed = false
  -- A road network monitor (scripts/road-monitor.lua): its reading.
  local tag, value
  if entity and entity.valid and not (depot or supplying) and logistics.monitor_tag then
    tag, value = logistics.monitor_tag(entity)
  end
  if tag then
    planned.tags = planned.tags or {}
    planned.tags[tag] = value
    if next(planned.tags) == nil then
      planned.tags = nil
    end
    changed = true
  end
  if supplying and not depot then
    -- A provider depot: its priority, unless it's the one every new depot has.
    planned.tags = planned.tags or {}
    planned.tags[PRIORITY_TAG] = supplying.priority ~= PRIORITY_DEFAULT and supplying.priority or nil
    planned.tags[robot_access.tag] = robot_access.get(entity) or nil
    planned.tags[CIRCUIT_TAG] = circuit_tag(supplying)
    if next(planned.tags) == nil then
      planned.tags = nil
    end
    changed = true
  end
  if depot then
    -- The depot's settings as they are now, replacing any from setting this blueprint up
    -- before; other tags and other items' insert plans are kept.
    planned.tags = planned.tags or {}
    planned.tags[PRIORITY_TAG] = supplying and supplying.priority ~= PRIORITY_DEFAULT and supplying.priority or nil
    planned.tags[robot_access.tag] = robot_access.get(entity) or nil
    planned.tags[REQUEST_TAG] = depot.request and { item = depot.request.item, count = depot.request.count } or nil
    -- Its own tag, so it's kept even with no item requested.
    planned.tags[FROM_BUFFERS_TAG] = depot.from_buffers or nil
    -- Kept off too: the depot built from it starts as the startup setting says where it is built
    -- (logistics.add), which needn't be what it was here.
    planned.tags["jatz_full_loads"] = depot.full_loads == true
    local freighters = freighter_total(entity)
    planned.tags[FREIGHTERS_TAG] = freighters > 0 and freighters or nil
    planned.tags[CIRCUIT_TAG] = circuit_tag(depot)
    if next(planned.tags) == nil then
      planned.tags = nil
    end
    -- Its freighters go by their tag (and the blueprint's request settings,
    -- scripts/depot-settings.lua), which the depot built asks robots for (apply_tags), never as
    -- an insert plan: blueprint parametrisation offers an insert plan's item to swap, and robots
    -- would then bring the item chosen as cargo, which trimming can't tell from anything else
    -- (Copilot's review of db40d7c). A freighter plan from before goes; other items' are kept.
    local items = {}
    for _, plan in pairs(planned.items or {}) do
      if item_name(plan.id.name) ~= FREIGHTER then
        items[#items + 1] = plan
      end
    end
    planned.items = #items > 0 and items or nil
    changed = true
  end
  return changed
end

-- An entity's settings as a blueprint keeps them in its tags, or nil if it has none to keep: for
-- its undo action when a player removes it (scripts/undo.lua). Its freighters are the
-- `jatz_freighters` tag, which a depot built from a ghost asks robots for (apply_tags).
function blueprints.settings_tags(entity)
  local planned = {}
  plan_settings(planned, entity)
  return planned.tags
end

function blueprints.setup_blueprint(blueprint, mapping)
  local entities = blueprint and mapping and blueprint.get_blueprint_entities()
  if not entities then
    return 0
  end
  local changed = 0
  -- Request depots' requests and freighters by blueprint entry, as their tags now hold them, for
  -- parametrisation (scripts/depot-settings.lua).
  local requests = {}
  for _, planned in pairs(entities) do
    local entity = mapping[planned.entity_number]
    if plan_settings(planned, entity) then
      changed = changed + 1
      local depot = request_depot(entity)
      if depot then
        local tags = planned.tags or {}
        requests[planned] = { request = tags[REQUEST_TAG], fluid = depot.fluid, freighters = tags[FREIGHTERS_TAG] or 0 }
      end
    end
  end
  if changed > 0 then
    -- (logistics.plan_request_settings is scripts/depot-settings.lua's, set when it loads.)
    blueprint.set_blueprint_entities(
      logistics.plan_request_settings and logistics.plan_request_settings(entities, requests) or entities
    )
  end
  return changed
end

-- The blueprint being set up: a library record, the stack the event names, the one being set up,
-- or the cursor (copy and paste), whichever holds the blueprint's entities.
local function blueprint_of(candidate)
  if not (candidate and candidate.valid) then
    return nil
  end
  if candidate.object_name == "LuaItemStack" then
    if not (candidate.valid_for_read and candidate.is_blueprint) then
      return nil
    end
  elseif candidate.type ~= "blueprint" then
    return nil
  end
  local entities = candidate.get_blueprint_entities()
  return entities and #entities > 0 and candidate or nil
end

function blueprints.on_player_setup_blueprint(event)
  local player = game.get_player(event.player_index)
  local mapping = event.mapping and event.mapping.valid and event.mapping.get()
  if not (player and mapping) then
    return
  end
  -- Any of these may be nil, so not ipairs (it stops at the first nil).
  local sources = { event.record, event.stack, player.blueprint_to_setup, player.cursor_stack }
  for index = 1, 4 do
    local blueprint = blueprint_of(sources[index])
    if blueprint then
      return logistics.setup_blueprint(blueprint, mapping)
    end
  end
end

-- A depot built from a blueprint ghost takes its settings from the ghost's tags: any delivery
-- depot its circuit condition, a provider or buffer depot its priority, a request or buffer depot
-- its request and freighters. Called for every depot built, tags or not.
function blueprints.apply_tags(entity, tags)
  local request, freighters
  if request_depot(entity) then
    -- The ghost's insert plan for freighters, into an item depot's own chest: asked of its truck
    -- chest instead at once, before robots bring any (a ghost built without its tags too).
    logistics.trim_freighter_requests(entity)
    -- Built from a blueprint with its request settings (scripts/depot-settings.lua): what they
    -- hold, which parametrisation may have changed, comes before the tags' (a request of false:
    -- the blueprint's depot had none). Taken with or without tags, so they never stay.
    if logistics.take_request_settings then
      request, freighters = logistics.take_request_settings(entity)
    end
  end
  if not (tags or request ~= nil or freighters) then
    return
  end
  tags = tags or {}
  -- Tags can come from anywhere (other mods, edited blueprint strings): use them only if well formed.
  if type(tags[PRIORITY_TAG]) == "number" then
    logistics.set_priority(entity, tags[PRIORITY_TAG])
  end
  if tags[robot_access.tag] == true then
    robot_access.set(entity, true)
  end
  local circuit = tags[CIRCUIT_TAG]
  if type(circuit) == "table" and type(circuit.condition) == "table" then
    logistics.set_circuit(
      entity,
      circuit.enabled == true,
      circuit.condition,
      depot_circuit.mode(circuit.mode) or depot_circuit.network
    )
  end
  local depot = request_depot(entity)
  if not depot then
    return
  end
  if request == nil then
    request = tags[REQUEST_TAG]
  end
  if request == false then
    logistics.set_request(entity, nil)
  elseif type(request) == "table" and type(request.item) == "string" and type(request.count) == "number" then
    logistics.set_request(entity, request.item, request.count)
  end
  if type(tags[FROM_BUFFERS_TAG]) == "boolean" then
    logistics.set_from_buffers(entity, tags[FROM_BUFFERS_TAG])
  end
  if type(tags["jatz_full_loads"]) == "boolean" then
    logistics.set_full_loads(entity, tags["jatz_full_loads"])
  end
  freighters = freighters or tags[FREIGHTERS_TAG]
  if type(freighters) == "number" and freighters >= 0 then
    -- An item depot's ghost from a blueprint from before asked for them by its insert plan too:
    -- trimming above made that its target, so they aren't asked for twice.
    logistics.match_freighters(entity, freighters)
  end
end

-- Copy one depot's settings onto another (Copy and Paste settings, and clones): any delivery
-- depot's circuit condition, a request depot's request, and a provider or buffer depot's priority.
local function copy_request(source, destination)
  local from = switching.delivery_depot(source)
  if from and switching.delivery_depot(destination) then
    logistics.set_circuit(
      destination,
      from.circuit_enabled,
      from.circuit_condition or {},
      from.circuit_mode or depot_circuit.network
    )
  end
  -- Items and fluids don't mix: nothing else is copied between an item depot and a liquid depot.
  if (LIQUID[source.name] or false) ~= (LIQUID[destination.name] or false) then
    return
  end
  if request_depot(source) and request_depot(destination) then
    local request = logistics.get_request(source)
    logistics.set_request(destination, request and request.item, request and request.count)
    logistics.set_from_buffers(destination, logistics.get_from_buffers(source))
    logistics.set_full_loads(destination, logistics.get_full_loads(source))
  end
  if supplying_depot(source) and supplying_depot(destination) then
    logistics.set_priority(destination, logistics.get_priority(source))
    local access = robot_access.get(source)
    if access ~= nil then
      robot_access.set(destination, access)
    end
  end
end

-- Copy and Paste settings: the request, and the freighters. The destination asks robots for as
-- many more freighters as it takes to match the source's (in its slot, out and coming); a player
-- can fill them in by hand instead.
function blueprints.on_entity_settings_pasted(event)
  copy_request(event.source, event.destination)
  if
    request_depot(event.source)
    and request_depot(event.destination)
    and (LIQUID[event.source.name] or false) == (LIQUID[event.destination.name] or false)
  then
    -- All the source has or will have: slot, out, chest (not leaving) and coming.
    logistics.match_freighters(event.destination, logistics.freighter_total(event.source))
  end
end

blueprints.copy_request = copy_request

return blueprints
