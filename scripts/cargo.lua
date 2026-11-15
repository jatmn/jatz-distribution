-- SPDX-License-Identifier: LGPL-3.0-only
-- Moving cargo: items stack by stack between inventories, fluid between a liquid depot's tank and a
-- freighter, and cargo left on the ground. Split out of scripts/logistics.lua so its main chunk
-- stays well below Lua's limit of 200 locals (issue #69). logistics.lua decides what moves when,
-- and hands this module what it shares with it when it loads (transfer.install).
local transfer = {}

-- scripts/logistics.lua's quality of cargo, from transfer.install.
local QUALITY

function transfer.install(_, shared)
  QUALITY = shared.quality
end

local load, load_fluid, unload_fluid

-- An item's stack size, read from its prototype once (prototypes don't change while the game runs;
-- reading one makes a new object every time).
local stack_sizes = {}
local function stack_size_of(item)
  local size = stack_sizes[item]
  if not size then
    size = prototypes.item[item].stack_size
    stack_sizes[item] = size
  end
  return size
end

-- Move up to `limit` items of `item` from one inventory into another, stack by stack, keeping each
-- stack's data. Returns how many moved.
-- `leave`, if given, maps `from` stack indices to how many items to leave in that stack. `grade`:
-- the quality that moves (cargo of a request's quality, scripts/quality.lua), normal if nil, or
-- true for every quality (freighters into a depot's slot).
function load(from, to, item, limit, leave, grade)
  local wanted = grade == nil and QUALITY or grade
  local moved = 0
  local size = stack_size_of(item)
  -- Each `to` stack looked at is an object for Lua to collect, so later stacks start after the
  -- leading ones that can take nothing more: full, or holding another item. A stack of `item` with
  -- room is looked at again, though it refused one stack: stacks merge only when their quality and
  -- data (health, tags, durability...) match, so it can still take a later one.
  local first = 1
  for index = 1, #from do
    if moved >= limit then
      break
    end
    local stack = from[index]
    if stack.valid_for_read and stack.name == item and (wanted == true or stack.quality.name == wanted) then
      local kept = leave and leave[index] or 0
      for slot = first, #to do
        local movable = (stack.valid_for_read and stack.count or 0) - kept
        if moved >= limit or movable <= 0 then
          break
        end
        local into = to[slot]
        if not into.valid_for_read or into.name == item then
          local before = stack.count
          into.transfer_stack(stack, math.min(movable, limit - moved))
          moved = moved + before - (stack.valid_for_read and stack.count or 0)
        end
        if slot == first and into.valid_for_read and (into.name ~= item or into.count >= size) then
          first = slot + 1
        end
      end
    end
  end
  return moved
end

-- Insert all cargo into an inventory, keeping each stack's data; what doesn't fit stays aboard.
local function unload(cargo, into)
  for index = 1, #cargo do
    local stack = cargo[index]
    if stack.valid_for_read then
      local inserted = into.insert(stack)
      if inserted >= stack.count then
        stack.clear()
      elseif inserted > 0 then
        stack.count = stack.count - inserted
      end
    end
  end
end

-- Pump up to `limit` of a fluid trip's fluid out of a liquid depot's tank (its one fluid storage),
-- at the tank's temperature.
function load_fluid(entity, trip, limit)
  local held = entity.get_fluid(1)
  if limit <= 0 or not held or held.name ~= trip.item then
    return 0
  end
  local removed = entity.remove_fluid(1, limit)
  local taken = removed and removed.amount or 0
  if taken > 0 then
    local had = trip.fluid.amount
    local temperature = trip.fluid.temperature or removed.temperature
    trip.fluid.temperature = (temperature * had + removed.temperature * taken) / (had + taken)
    trip.fluid.amount = had + taken
  end
  return taken
end

-- Pump a fluid trip's fluid into a liquid depot's tank, as far as it fits; the rest stays aboard.
function unload_fluid(trip, entity)
  if trip.fluid.amount <= 0 then
    return 0
  end
  local put =
    entity.insert_fluid({ name = trip.item, amount = trip.fluid.amount, temperature = trip.fluid.temperature })
  trip.fluid.amount = trip.fluid.amount - put
  return put
end

-- Leave anything still aboard on the ground, marked for deconstruction so construction robots
-- can collect it.
local function spill(trip, position)
  if trip.fluid then
    -- Fluid can't be left on the ground: it is lost.
    trip.fluid.amount = 0
    return
  end
  if not (trip.cargo and trip.cargo.valid) then
    return
  end
  local surface, force = trip.drone.surface, trip.drone.force
  for index = 1, #trip.cargo do
    local stack = trip.cargo[index]
    if stack.valid_for_read then
      surface.spill_item_stack({
        position = position or trip.drone.position,
        stack = stack,
        enable_looted = true,
        force = force,
        allow_belts = false,
      })
      stack.clear()
    end
  end
end

transfer.stack_size_of = stack_size_of
transfer.load = load
transfer.unload = unload
transfer.load_fluid = load_fluid
transfer.unload_fluid = unload_fluid
transfer.spill = spill

return transfer
