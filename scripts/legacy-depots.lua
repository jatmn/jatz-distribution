-- SPDX-License-Identifier: LGPL-3.0-only
-- Item provider and buffer depots from before they were logistic containers (scripts/robot-access.lua).
-- Factorio rebuilds an entity whose prototype changed type facing north, with a new unit number,
-- drops its ghosts, and forgets its direction in blueprints (probed on 2.1.24). So the migration
-- (migrations/2026-11-07-logistic-depots.json) renames them, in saves, ghosts and blueprints, to
-- the hidden containers they were (`jatz-provider-depot-legacy`, `jatz-buffer-depot-legacy`,
-- prototypes/depots.lua), which keep everything, and this replaces each with the depot: at once on
-- configuration changes (control.lua's setup, before deliveries look at the depots), and as a
-- ghost of one is placed (a blueprint from before) or one is built. The new depot, or ghost, stands
-- where the old one stood, facing the same way, flipped the same, with its force, quality, last
-- user, wires and chest settings (`chest_settings`: its inventory limit and what it sends on its
-- wires); a depot also with its health, contents (as stacks, so item data stays), deconstruction
-- mark, and everything the mod kept by its unit number (logistics.replaced, depot_road.replaced,
-- road_monitor.replaced): its settings, freighters, trips and the promises made to it; a ghost with
-- its tags (a blueprint's settings) and insert plan. Robots stay out of it, as of every depot until
-- it lets them.
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

-- The settings a chest has of its own, which its ghost keeps too and the game hands on as the ghost
-- is built: its inventory limit, and its circuit reading, every setting a container's control
-- behavior and a logistic container's share (LuaContainerControlBehavior, and LuaControlBehavior's
-- output_networks, which wire colours it sends on). Read from a depot or its ghost alike (the
-- inventory's bar through LuaEntity::get_inventory_bar, which works for both). Every field in
-- READING is written back, nil too: a player can clear the empty-slot signal, and skipping it
-- would leave the new chest's default signal-E sending its empty slots. A chest with no control
-- behavior at all (never wired) gives the new one none either, so it keeps the same defaults.
local CHEST = defines.inventory.chest
local READING = { "read_contents", "read_empty_slots", "empty_slots_signal", "output_networks" }

local function chest_settings(entity)
  local settings = {}
  if entity.inventory_supports_bar(CHEST) then
    settings.bar = entity.get_inventory_bar(CHEST)
  end
  local behavior = entity.get_control_behavior()
  if behavior then
    settings.reading = {}
    for _, field in ipairs(READING) do
      settings.reading[field] = behavior[field]
    end
  end
  return settings
end

local function apply_chest_settings(entity, settings)
  if settings.bar and entity.inventory_supports_bar(CHEST) then
    entity.set_inventory_bar(CHEST, settings.bar)
  end
  if settings.reading then
    local behavior = entity.get_or_create_control_behavior()
    for _, field in ipairs(READING) do
      behavior[field] = settings.reading[field]
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

-- Replace a ghost of a legacy depot with a ghost of the depot. Returns the new ghost.
local function replace_ghost(ghost)
  local surface = ghost.surface
  local made = spec(ghost, "entity-ghost", REPLACEMENT[ghost.ghost_name])
  local tags, plan, wires, user = ghost.tags, ghost.insert_plan, wires_of(ghost), ghost.last_user
  local settings = chest_settings(ghost)
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
  apply_chest_settings(new, settings)
  return new
end

-- Replace a legacy depot with the depot. Returns the new depot, or nil if it couldn't be made
-- (its contents are then spilled where it stood).
local function replace(entity)
  local surface, old_id = entity.surface, entity.unit_number
  local made = spec(entity, REPLACEMENT[entity.name])
  local held = entity.get_inventory(CHEST)
  local kept = game.create_inventory(#held)
  for index = 1, #held do
    kept[index].transfer_stack(held[index])
  end
  local settings = chest_settings(entity)
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
  local inventory = new.get_inventory(CHEST)
  for index = 1, math.min(#kept, #inventory) do
    inventory[index].transfer_stack(kept[index])
  end
  kept.destroy()
  connect(new, wires)
  apply_chest_settings(new, settings)
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
