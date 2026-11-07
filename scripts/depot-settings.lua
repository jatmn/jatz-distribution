-- SPDX-License-Identifier: LGPL-3.0-only
-- Blueprint parametrisation for request and buffer depots. The game's parametrisation rewrites only
-- its own entity settings, never a mod's tags, so a blueprint of a depot with a request holds that
-- request a second time: as the first slot of a constant combinator that only blueprints hold
-- (prototypes/depot-settings.lua), at the depot's centre, where the game can turn its item or
-- fluid and its amount into parameters. Its ghost, placed with the depot's, hands the request
-- (parametrised or not) to the depot's ghost as its request tag, or to a depot already there, and
-- goes at once, so none stays in the world and saves need nothing new. Blueprints from before keep
-- working from their tags alone.
local logistics = require("scripts.logistics")

local depot_settings = {}
local NAME = "jatz-depot-settings"
depot_settings.name = NAME

local function key(position)
  return (position.x or position[1]) .. "," .. (position.y or position[2])
end

-- A blueprint's entries (`entities`) with request settings for the depots in `requests`
-- (entry -> { request = depot.request, fluid = depot.fluid }): any from setting it up before at
-- those depots go, and each depot with a request gets one.
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
    local request = depot.request
    if request then
      last = last + 1
      kept[#kept + 1] = {
        entity_number = last,
        name = NAME,
        position = planned.position,
        control_behavior = {
          sections = {
            sections = {
              {
                index = 1,
                filters = {
                  {
                    index = 1,
                    type = depot.fluid and "fluid" or "item",
                    name = request.item,
                    quality = "normal",
                    comparator = "=",
                    count = request.count,
                  },
                },
              },
            },
          },
        },
      }
    end
  end
  return kept
end

-- The request that request settings (or their ghost) hold: { item = name, count = n }, or nil.
local function request_of(entity)
  local behavior = entity.get_control_behavior()
  local section = behavior and behavior.sections_count > 0 and behavior.get_section(1)
  local slot = section and section.filters[1]
  local value = slot and slot.value
  if not (value and type(value.name) == "string") then
    return nil
  end
  return { item = value.name, count = slot.min or 0 }
end

-- Take the request of the request settings (or their ghost) at the centre of a depot built from a
-- blueprint, removing them. Returns the request, or nil.
function depot_settings.take(entity)
  local surface, position = entity.surface, entity.position
  local found = surface.find_entities_filtered({ position = position, name = NAME })[1]
    or surface.find_entities_filtered({ position = position, ghost_name = NAME })[1]
  if not found then
    return nil
  end
  local request = request_of(found)
  found.destroy()
  return request
end

-- Request settings built from a blueprint (their ghost, or themselves if built at once, as in the
-- editor): the request goes to the request or buffer depot's ghost at their position, as its
-- request tag, or to such a depot already there, and they go. A blueprint's ghosts are all placed
-- before their build events (probed on 2.1.24), so the depot's ghost is there already; with no
-- depot to take the request, they just go.
function depot_settings.built(entity)
  local surface, position = entity.surface, entity.position
  local request = request_of(entity)
  entity.destroy()
  if not request then
    return
  end
  local here = key(position)
  for _, found in pairs(surface.find_entities_filtered({ position = position })) do
    if key(found.position) == here then
      if found.type == "entity-ghost" and logistics.requesting[found.ghost_name] then
        local tags = found.tags or {}
        tags[logistics.request_tag] = request
        found.tags = tags
        return
      elseif logistics.requesting[found.name] then
        logistics.set_request(found, request.item, request.count)
        return
      end
    end
  end
end

-- Blueprint setup and depots built from blueprints call these (logistics.setup_blueprint,
-- logistics.apply_tags); logistics.lua can't require this file itself (it is at Lua's limit of
-- locals, and the game allows require only while loading).
logistics.plan_request_settings = depot_settings.plan
logistics.take_request_settings = depot_settings.take

return depot_settings
