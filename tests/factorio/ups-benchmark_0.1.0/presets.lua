-- SPDX-License-Identifier: LGPL-3.0-only
-- Benchmark map sizes. tools/benchmark_ups.py picks one by writing selected-preset.lua; the
-- engine-free emulator reads them too. Change a preset only together with the recorded baseline in
-- docs/benchmark.md, since results are only comparable on the same map.
local common = {
  seed = 20261104,
  -- Junctions 16 tiles apart; every 8th grid line is a 5-tile-wide road.
  cell = 16,
  arterial = 8,
  -- Share of the wide lines' links that exist (the rest are gaps to drive around), of the other
  -- non-maze links added back as crossings, and of junctions with a dead-end spur.
  arterial_share = 0.7,
  loops = 0.12,
  spurs = 0.15,
  provider_share = 0.5,
  -- Share of request depots facing a provider across the same road tile.
  across_share = 0.1,
  -- Freighters (drones) per request depot, lowest and highest.
  freighters = { 5, 100 },
  -- Every this-many-th provider keeps a minimum: a circuit condition reading its own contents
  -- switches it on only while it holds more than `minimum_share` of a full chest (for mods that
  -- have circuit conditions: Transport Drones' providers stay plain).
  minimum_every = 4,
  minimum_share = 0.5,
  -- Fuel depots, as a share of the depots above (built only for mods whose freighters fill up at
  -- them: Transport Drones keeps its drones' fuel in the request depot).
  fuel_share = 0.1,
}

local function preset(values)
  local result = {}
  for name, value in pairs(common) do
    result[name] = value
  end
  for name, value in pairs(values) do
    result[name] = value
  end
  return result
end

return {
  -- A smoke test and the emulator's default: one surface, 160 x 160 tiles.
  quick = preset({ surfaces = 1, grid = 11, depots = 40, warmup = 1800, ticks = 1800 }),
  -- What a pull request runs before and after its change: two surfaces of 352 x 352 tiles (depots
  -- up to about 500 tiles apart), 160 depots.
  standard = preset({ surfaces = 2, grid = 23, depots = 80, warmup = 7200, ticks = 3600 }),
  -- The baseline: hundreds of depots and thousands of freighters on three surfaces.
  stress = preset({ surfaces = 3, grid = 23, depots = 200, warmup = 7200, ticks = 3600 }),
}
