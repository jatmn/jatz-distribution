-- SPDX-License-Identifier: LGPL-3.0-only
-- Whether logistic robots may use an item provider or buffer depot, as a passive provider or buffer
-- chest (the owner's request, November 7, 2026). The depots are logistic containers
-- (prototypes/depots.lua), and the setting is their logistic points' `enabled`
-- (LuaLogisticPoint::enabled, read and write in 2.1), which the game saves: a disabled point is
-- out of the logistic network, so robots neither take from it nor bring it anything (probed on
-- 2.1.24). Off on every new depot (scripts/logistics.lua's `add`); the depot's panel, Copy and
-- Paste settings, clones, blueprints and undo (the `jatz_robot_access` tag) and the remote
-- interface set it.
local robot_access = {}

robot_access.tag = "jatz_robot_access"

-- The entity's logistic points, if it is a depot robots can be let into, else nil.
local function points(entity)
  if not (entity and entity.valid and entity.type == "logistic-container") then
    return nil
  end
  if not (entity.name == "jatz-provider-depot" or entity.name == "jatz-buffer-depot") then
    return nil
  end
  return entity.get_logistic_point()
end

-- Whether the depot's own circuit condition (the game's logistic container "Enable/disable", in its
-- circuit settings) is switching it: then that decides, every update, overriding the setting
-- (probed on 2.1.24), and the panel's checkbox only shows it.
function robot_access.circuit_controlled(entity)
  if not points(entity) then
    return false
  end
  local behavior = entity.get_control_behavior()
  return behavior and behavior.circuit_condition_enabled or false
end

-- Whether robots may use the depot, or nil for anything else.
function robot_access.get(entity)
  local list = points(entity)
  local point = list and select(2, next(list))
  if not point then
    return nil
  end
  return point.enabled
end

-- Let robots use the depot, or not. Returns false, changing nothing, for anything else.
function robot_access.set(entity, enabled)
  local list = points(entity)
  if not list or type(enabled) ~= "boolean" then
    return false
  end
  -- A buffer depot has two: its requests and what it provides.
  for _, point in pairs(list) do
    point.enabled = enabled
  end
  return true
end

return robot_access
