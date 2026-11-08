-- SPDX-License-Identifier: LGPL-3.0-only
-- Blueprint parametrisation for request and buffer depots. The game's parametrisation rewrites only
-- its own entity settings, never a mod's tags, so a blueprint of a depot with a request or
-- freighters holds them a second time: in a decider combinator that only blueprints hold
-- (prototypes/depot-settings.lua), at the depot's centre, where the game can turn them into
-- parameters. The request is a condition comparing its item or fluid to its amount; the
-- freighters a condition with no signal, only their number, so parametrising offers the number
-- and no item to swap for the freighter. Its ghost, placed with the depot's, hands them
-- (parametrised or not) to the depot's ghost as its tags, or to a depot already there, and goes at
-- once, so none stays in the world and saves need nothing new. Blueprints from before keep working
-- from their tags alone.
local logistics = require("scripts.logistics")

local depot_settings = {}
local NAME = "jatz-depot-settings"
depot_settings.name = NAME
-- A condition's constant is an int32 (DeciderCombinatorCondition.constant); a request above it
-- stays in its tag only, so the blueprint can still be made.
local COUNT_MAX = 2147483647

local function key(position)
  return (position.x or position[1]) .. "," .. (position.y or position[2])
end

-- A blueprint's entries (`entities`) with request settings for the depots in `requests`
-- (entry -> { request = depot.request, fluid = depot.fluid, freighters = n }): any from setting it
-- up before at those depots go, and each depot with a request or freighters gets one.
function depot_settings.plan(entities, requests)
  local at, last = {}, 0
  for planned, depot in pairs(requests) do
    at[key(planned.position)] = depot
  end
  local kept = {}
  for _, planned in pairs(entities) do
    last = math.max(last, planned.entity_number)
    if not (planned.name == NAME and at[key(planned.position)]) then
      kept[#kept + 1] = planned
    end
  end
  for planned, depot in pairs(requests) do
    local conditions = {}
    local request = depot.request
    if request and request.count <= COUNT_MAX then
      conditions[#conditions + 1] = {
        first_signal = { type = depot.fluid and "fluid" or "item", name = request.item },
        comparator = "=",
        constant = request.count,
      }
    end
    if depot.freighters > 0 then
      conditions[#conditions + 1] = { comparator = "=", constant = math.min(depot.freighters, COUNT_MAX) }
    end
    if #conditions > 0 then
      last = last + 1
      kept[#kept + 1] = {
        entity_number = last,
        name = NAME,
        position = planned.position,
        control_behavior = { decider_conditions = { conditions = conditions, outputs = {} } },
      }
    end
  end
  return kept
end

-- What request settings (or their ghost) hold: the request ({ item = name, count = n }), from the
-- condition with a signal, and the freighters (a number), from the one with only a constant;
-- either nil without its condition.
local function settings_of(entity)
  local behavior = entity.get_control_behavior()
  local parameters = behavior and behavior.parameters
  local request, freighters
  for _, condition in ipairs(parameters and parameters.conditions or {}) do
    local signal = condition.first_signal
    if signal and type(signal.name) == "string" then
      request = request or { item = signal.name, count = condition.constant or 0 }
    elseif not condition.second_signal and condition.constant then
      freighters = freighters or math.max(0, condition.constant)
    end
  end
  return request, freighters
end

-- What the request settings built at once beside a depot gave it this tick, before its own build
-- event (by unit number). Nothing outlives the tick.
local function given_now()
  local given = storage.depot_settings_given
  if not (given and given.tick == game.tick) then
    given = { tick = game.tick }
    storage.depot_settings_given = given
  end
  return given
end

-- The request settings (or their ghost) of the depot's force at the centre of a depot built from
-- a blueprint, taken: their request and freighters, removing them; or what such settings gave
-- the depot this tick, if their build event came first. Returns nil without any.
function depot_settings.take(entity)
  local surface, position, force = entity.surface, entity.position, entity.force
  local found = surface.find_entities_filtered({ position = position, name = NAME, force = force })[1]
    or surface.find_entities_filtered({ position = position, ghost_name = NAME, force = force })[1]
  if not found then
    local given = storage.depot_settings_given
    local settings = given and given.tick == game.tick and given[entity.unit_number]
    if settings then
      return settings.request, settings.freighters
    end
    return nil, nil
  end
  local request, freighters = settings_of(found)
  found.destroy()
  return request, freighters
end

-- Request settings built from a blueprint (their ghost, or themselves if built at once, as in the
-- editor): the request and freighters go to the request or buffer depot's ghost of their force at
-- their position, as its tags, or to such a depot already there, and they go. A blueprint's ghosts
-- are all placed before their build events (probed on 2.1.24), so the depot's ghost is there
-- already; with no depot to take them, they just go.
function depot_settings.built(entity)
  local surface, position, force = entity.surface, entity.position, entity.force
  local request, freighters = settings_of(entity)
  entity.destroy()
  if not (request or freighters) then
    return
  end
  local here = key(position)
  for _, found in pairs(surface.find_entities_filtered({ position = position, force = force })) do
    if key(found.position) == here then
      if found.type == "entity-ghost" and logistics.requesting[found.ghost_name] then
        local tags = found.tags or {}
        tags[logistics.request_tag] = request or tags[logistics.request_tag]
        tags[logistics.freighters_tag] = freighters or tags[logistics.freighters_tag]
        found.tags = tags
        return
      elseif logistics.requesting[found.name] then
        if request then
          logistics.set_request(found, request.item, request.count)
        end
        if freighters then
          logistics.match_freighters(found, freighters)
        end
        -- Built at once with the depot, whose own build event may come next: its tags hold what
        -- the blueprint had before parametrising, so it takes these instead (take).
        given_now()[found.unit_number] = { request = request, freighters = freighters }
        return
      end
    end
  end
end

-- Blueprint setup and depots built from blueprints call these (logistics.setup_blueprint,
-- logistics.apply_tags); logistics.lua can't require this file itself (the game allows require only
-- while loading).
logistics.plan_request_settings = depot_settings.plan
logistics.take_request_settings = depot_settings.take

return depot_settings
