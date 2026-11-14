-- SPDX-License-Identifier: LGPL-3.0-only
-- Saved freighter state and its transitions. Search and movement are independent: a new
-- provider may be sought while the current tunnel crossing must still finish.
local state = {}

function state.cancel_search(owner)
  owner.search = nil
end

function state.begin_search(owner, kind, token, tick)
  owner.search = { kind = kind, phase = "pending", token = token, since = tick }
  if owner.drone then
    -- A search decides where it goes: no longer waiting for a plan to drive one (drive).
    owner.planning = nil
    state.travel(owner)
  end
end

function state.retry_search(owner, tick)
  local search = owner.search
  if search then
    search.phase, search.token, search.since = "retry", nil, tick
  end
end

function state.owns_search(owner, token)
  local search = owner and owner.search
  return search and search.phase == "pending" and search.token == token
end

function state.travel(trip)
  trip.service = nil
end

function state.begin_service(trip, tick)
  local kind = trip.refuel and "refueling" or (trip.state == "to-provider" and "loading" or "unloading")
  trip.service = { kind = kind, since = tick }
end

-- Mission changes and their ledger update have one owner. The caller settles the cargo first.
function state.mission(trip, mission, promise)
  trip.state = mission
  state.travel(trip)
  promise(trip)
end

function state.clear_route_search(trip)
  state.cancel_search(trip)
  trip.refuel, trip.planning = nil, nil
  state.travel(trip)
end

function state.begin_leg(trip)
  trip.fuel_check = "unchecked"
end

function state.fuel_checked(trip)
  state.cancel_search(trip)
  trip.refuel, trip.fuel_check = nil, "checked"
end

function state.move(trip, phase, tunnel)
  trip.movement, trip.tunnel = phase, tunnel
end

function state.road(trip, tunnel)
  state.travel(trip)
  state.move(trip, tunnel and "approaching-tunnel" or "road", tunnel)
end

-- Only this boundary touches the retired representation. Also used by add_all before events
-- can inspect old trips; safe to repeat on a new save or after configuration changes.
function state.upgrade_search(owner)
  if not owner.search and owner.searching then
    owner.search = {
      kind = owner.fuel_search and "fuel" or "provider",
      phase = owner.search_token and "pending" or "retry",
      token = owner.search_token,
      since = owner.searching,
    }
  end
  owner.searching, owner.search_token, owner.fuel_search = nil, nil, nil
end

function state.upgrade(trip)
  if trip.lifecycle_version == 1 then
    return
  end
  state.upgrade_search(trip)
  if not trip.movement then
    local tunnel = trip.tunnel
    trip.movement = trip.departing and "departing"
      or (tunnel and (tunnel.started and "underground" or "approaching-tunnel"))
      or (trip.coming_out and "exiting-tunnel")
      or "road"
  end
  if trip.loading and not trip.search then
    state.begin_service(trip, game.tick)
  end
  trip.fuel_check = trip.refueled and "checked" or "unchecked"
  trip.departing, trip.coming_out, trip.loading, trip.refueled = nil, nil, nil, nil
  if trip.tunnel then
    trip.tunnel.under, trip.tunnel.started = nil, nil
  end
  trip.lifecycle_version = 1
end

-- Repainting changes the engine identity, never the logical reservation key.
function state.rebind(trip, old_id, drone, home_trips)
  storage.trips[old_id], storage.trips[drone.unit_number] = nil, trip
  if home_trips then
    home_trips[old_id], home_trips[drone.unit_number] = nil, true
  end
  trip.id, trip.drone = drone.unit_number, drone
end

-- Detach before destroying engine objects: their later destruction events become no-ops.
function state.finish(trip, id, promise)
  storage.trips[id] = nil
  promise(trip, true)
  state.clear_route_search(trip)
  state.move(trip, "ended")
end

return state
