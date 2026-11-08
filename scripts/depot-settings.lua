-- SPDX-License-Identifier: LGPL-3.0-only
-- Blueprint parametrisation for request and buffer depots. The game's parametrisation rewrites only
-- its own entity settings, never a mod's tags, so a blueprint of a request or buffer depot holds its
-- request and freighters a second time: in a decider combinator that only blueprints hold
-- (prototypes/depot-settings.lua), at the depot's centre, where the game can turn them into
-- parameters. The request is a condition comparing its item or fluid to its amount; the
-- freighters a condition with no signal, only their number, so parametrising offers the number
-- and no item to swap for the freighter. Its ghost, placed with the depot's, hands them
-- (parametrised or not) to the depot's ghost as its tags, or to the same depot already there, and
-- goes at once, so none stays in the world and saves need nothing new. Blueprints from before keep
-- working from their tags alone.
local logistics = require("scripts.logistics")

local depot_settings = {}
local NAME = "jatz-depot-settings"
depot_settings.name = NAME
-- The settings' own tags: the name of the depot they were made from, which only that same depot
-- takes them, as only it takes a blueprint's settings when pasted over (an item depot's over a
-- liquid one, or a request depot's over a buffer one, would otherwise hand them on: Copilot's and
-- Pullfrog's review of 4a0d9b9); and a request too large for a condition.
local SOURCE_TAG = "jatz_settings_of"
-- A condition's constant is an int32 (DeciderCombinatorCondition.constant); a request above it
-- can't be a condition, so the settings hold it as a tag instead (not parametrisable), and the
-- blueprint can still be made.
local COUNT_MAX = 2147483647

local function key(position)
  return (position.x or position[1]) .. "," .. (position.y or position[2])
end

-- A blueprint's entries (`entities`) with request settings for the depots in `requests`
-- (entry -> { request = depot.request, fluid = depot.fluid, freighters = n }): any from setting it
-- up before at those depots go, and each depot gets one. They hold the depot as it is: its request
-- or that it has none, and its freighters, none included. So pasting over the same depot sets
-- both, clearing a request the blueprint's depot doesn't have and cancelling requests for more
-- freighters, as Copy and Paste settings does.
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
    local conditions, tags = {}, { [SOURCE_TAG] = planned.name }
    local request = depot.request
    if request and request.count <= COUNT_MAX then
      conditions[#conditions + 1] = {
        first_signal = { type = depot.fluid and "fluid" or "item", name = request.item },
        comparator = "=",
        constant = request.count,
      }
    elseif request then
      tags[logistics.request_tag] = request
    end
    conditions[#conditions + 1] = { comparator = "=", constant = math.min(depot.freighters, COUNT_MAX) }
    last = last + 1
    kept[#kept + 1] = {
      entity_number = last,
      name = NAME,
      position = planned.position,
      tags = tags,
      control_behavior = { decider_conditions = { conditions = conditions, outputs = {} } },
    }
  end
  return kept
end

-- What request settings (or their ghost) with their blueprint `tags` hold, or nil without the tag
-- naming their depot (only blueprints set up since make them): { depot = its name, request =,
-- freighters = }. The request is the condition with a signal's, or else their tag's (one too large
-- for a condition), or else false: the depot had none. A request for something the depot can't
-- request (a fluid for an item depot, as parametrising could choose) is nil: no word on it, so
-- what the depot or its ghost has stays, as set_request would refuse it. The freighters are the
-- condition with only a constant's.
local function settings_of(entity, tags)
  local depot = type(tags) == "table" and tags[SOURCE_TAG]
  if not (type(depot) == "string" and logistics.requesting[depot]) then
    return nil
  end
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
  local tagged = tags[logistics.request_tag]
  if not request and type(tagged) == "table" and type(tagged.item) == "string" and type(tagged.count) == "number" then
    request = { item = tagged.item, count = tagged.count }
  end
  if request then
    local kinds = logistics.liquid[depot] and prototypes.fluid or prototypes.item
    request = kinds[request.item] and request or nil
  else
    request = false
  end
  return { depot = depot, request = request, freighters = freighters }
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

-- For a depot built from a blueprint: the request (a table, or false for none) and freighters its
-- request settings give it, either nil for no word on it. Those are the ghost of its settings
-- standing at its centre (of its force, made from that same depot), taken and removed, or what its
-- settings gave it this tick, if their build event came first. Settings built at once (not a
-- ghost) are left to their own build event, the one that carries their tags: it follows and sets
-- the depot then.
function depot_settings.take(entity)
  local surface, position, force = entity.surface, entity.position, entity.force
  local found = surface.find_entities_filtered({ position = position, ghost_name = NAME, force = force })[1]
  if not found then
    local given = storage.depot_settings_given
    local settings = given and given.tick == game.tick and given[entity.unit_number]
    if settings then
      return settings.request, settings.freighters
    end
    return nil, nil
  end
  local settings = settings_of(found, found.tags)
  -- Another depot's (or from before) never stays either: settings never stand in the world.
  found.destroy()
  if not (settings and settings.depot == entity.name) then
    return nil, nil
  end
  return settings.request, settings.freighters
end

-- Request settings built from a blueprint (their ghost, or themselves if built at once, as in the
-- editor; `tags`, the build event's, or the ghost's own): the request and freighters go to the
-- ghost of the depot they were made from, of their force, at their position, as its tags, or to
-- that depot already there, and they go. A blueprint's ghosts are all placed before their build
-- events (probed on 2.1.24), so the depot's ghost is there already; with no such depot (none, or
-- another kind, where a forced paste left the blueprint's depot out), they just go.
function depot_settings.built(entity, tags)
  local surface, position, force = entity.surface, entity.position, entity.force
  local settings = settings_of(entity, tags or entity.type == "entity-ghost" and entity.tags or nil)
  entity.destroy()
  if not settings then
    return
  end
  local request, freighters = settings.request, settings.freighters
  local here = key(position)
  for _, found in pairs(surface.find_entities_filtered({ position = position, force = force })) do
    if key(found.position) == here then
      if found.type == "entity-ghost" and found.ghost_name == settings.depot then
        local ghost_tags = found.tags or {}
        if request ~= nil then
          ghost_tags[logistics.request_tag] = request or nil
        end
        if freighters then
          ghost_tags[logistics.freighters_tag] = freighters
        end
        found.tags = ghost_tags
        return
      elseif found.name == settings.depot then
        if request then
          logistics.set_request(found, request.item, request.count)
        elseif request == false then
          logistics.set_request(found, nil)
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
