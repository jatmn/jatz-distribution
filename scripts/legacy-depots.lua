-- SPDX-License-Identifier: LGPL-3.0-only
-- Item provider and buffer depots from before they were logistic containers (scripts/robot-access.lua).
-- Factorio rebuilds an entity whose prototype changed type facing north, with a new unit number,
-- drops its ghosts, and forgets its direction in blueprints (probed on 2.1.24). So the migration
-- (migrations/2026-11-07-logistic-depots.json) renames them, in saves, ghosts and blueprints, to
-- the hidden containers they were (`jatz-provider-depot-legacy`, `jatz-buffer-depot-legacy`,
-- prototypes/depots.lua), which keep everything, and this replaces each with the depot: at once on
-- configuration changes (control.lua's setup, before deliveries look at the depots), and as a
-- ghost of one is placed (a blueprint from before) or one is built. The new depot stands where the
-- old one stood, facing the same way, flipped the same, with its force, quality, health, last
-- user, contents (as stacks, so item data stays), inventory limit, wires, circuit reading and
-- deconstruction mark, and everything the mod kept by its unit number (logistics.replaced,
-- depot_road.replaced): its settings, freighters, trips and the promises made to it. Robots stay
-- out of it, as of every depot until it lets them.
local logistics = require("scripts.logistics")
local depot_road = require("scripts.depot-road")
local robot_access = require("scripts.robot-access")
local road_monitor = require("scripts.road-monitor")

local legacy_depots = {}

local REPLACEMENT = {
  ["jatz-provider-depot-legacy"] = "jatz-provider-depot",
  ["jatz-buffer-depot-legacy"] = "jatz-buffer-depot",
}
-- Legacy name to the depot's, for undo (scripts/undo.lua), whose actions name the legacy depot.
legacy_depots.replacement = REPLACEMENT
legacy_depots.names = {}
for name in pairs(REPLACEMENT) do
  legacy_depots.names[#legacy_depots.names + 1] = name
end
table.sort(legacy_depots.names)

-- The entity's wires to other entities: { id = its connector, target = the other end's, origin }.
local function wires_of(entity)
  local wires = {}
  for id, connector in pairs(entity.get_wire_connectors(false)) do
    for _, connection in pairs(connector.connections) do
      if connection.target.owner ~= entity then
        wires[#wires + 1] = { id = id, target = connection.target, origin = connection.origin }
      end
    end
  end
  return wires
end

local function connect(entity, wires)
  for _, wire in ipairs(wires) do
    if wire.target.valid then
      entity.get_wire_connector(wire.id, true).connect_to(wire.target, false, wire.origin)
    end
  end
end

-- What a new depot or ghost is made from: the old one's place, facing and owner.
local function spec(entity, name, inner_name)
  return {
    name = name,
    inner_name = inner_name,
    position = entity.position,
    direction = entity.direction,
    mirror = entity.mirroring,
    force = entity.force,
    quality = entity.quality,
    -- No `player`: that would put the replacement on their undo queue (last_user is set after).
    create_build_effect_smoke = false,
    preserve_ghosts_and_corpses = true,
  }
end

-- Replace a ghost of a legacy depot with a ghost of the depot, keeping its tags (a blueprint's
-- settings) and insert plan. Returns the new ghost.
local function replace_ghost(ghost)
  local surface = ghost.surface
  local made = spec(ghost, "entity-ghost", REPLACEMENT[ghost.ghost_name])
  local tags, plan, wires, user = ghost.tags, ghost.insert_plan, wires_of(ghost), ghost.last_user
  ghost.destroy()
  local new = surface.create_entity(made)
  if not new then
    return nil
  end
  new.last_user = user
  new.tags = tags
  if plan and #plan > 0 then
    new.insert_plan = plan
  end
  connect(new, wires)
  return new
end

-- Replace a legacy depot with the depot. Returns the new depot, or nil if it couldn't be made
-- (its contents are then spilled where it stood).
local function replace(entity)
  local surface, old_id = entity.surface, entity.unit_number
  local made = spec(entity, REPLACEMENT[entity.name])
  local held = entity.get_inventory(defines.inventory.chest)
  local kept = game.create_inventory(#held)
  for index = 1, #held do
    kept[index].transfer_stack(held[index])
  end
  local bar = held.supports_bar() and held.get_bar() or nil
  local behavior = entity.get_control_behavior()
  local reading = behavior
    and {
      read_contents = behavior.read_contents,
      read_empty_slots = behavior.read_empty_slots,
      empty_slots_signal = behavior.empty_slots_signal,
    }
  local wires, health, marked = wires_of(entity), entity.health, entity.to_be_deconstructed()
  local user = entity.last_user
  entity.destroy()
  local new = surface.create_entity(made)
  if not new then
    surface.spill_inventory({ position = made.position, inventory = kept })
    kept.destroy()
    return nil
  end
  new.health, new.last_user = health, user
  local inventory = new.get_inventory(defines.inventory.chest)
  for index = 1, math.min(#kept, #inventory) do
    inventory[index].transfer_stack(kept[index])
  end
  kept.destroy()
  if bar and inventory.supports_bar() then
    inventory.set_bar(bar)
  end
  connect(new, wires)
  if reading then
    local now = new.get_or_create_control_behavior()
    now.read_contents = reading.read_contents
    now.read_empty_slots = reading.read_empty_slots
    now.empty_slots_signal = reading.empty_slots_signal
  end
  if marked then
    new.order_deconstruction(new.force)
  end
  robot_access.set(new, false)
  logistics.replaced(old_id, new)
  depot_road.replaced(old_id, new)
  road_monitor.replaced(old_id, new.unit_number)
  return new
end

-- A legacy depot, or a ghost of one, just built or placed: replaced at once. Returns the depot
-- (nil for a ghost, or if it couldn't be made), or the entity itself if it is neither.
function legacy_depots.built(entity)
  if REPLACEMENT[entity.name] then
    return replace(entity)
  elseif entity.type == "entity-ghost" and REPLACEMENT[entity.ghost_name] then
    replace_ghost(entity)
    return nil
  end
  return entity
end

-- Every legacy depot and ghost of one in the game (on configuration changes).
function legacy_depots.replace_all()
  for _, surface in pairs(game.surfaces) do
    for _, ghost in pairs(surface.find_entities_filtered({ type = "entity-ghost", ghost_name = legacy_depots.names })) do
      replace_ghost(ghost)
    end
    for _, entity in pairs(surface.find_entities_filtered({ name = legacy_depots.names })) do
      replace(entity)
    end
  end
end

return legacy_depots
