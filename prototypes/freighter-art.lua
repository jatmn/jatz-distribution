-- SPDX-License-Identifier: LGPL-3.0-only
-- The freighter's sprites and size as the mod draws it. The artwork's helper
-- (assets/quinityn-freighter/factorio/freighter-animation.lua) is part of the finished, checksummed
-- art, so the mod scales it here instead: both the drivable freighter and the delivering one use
-- this, so they always match.
local constants = require("prototypes.constants")
local make_animation = require("assets.quinityn-freighter.factorio.freighter-animation")

local art = {}

-- The freighter's in-game size relative to the artwork's own scale.
art.scale = constants.freighter_scale

-- `palette` (optional): { cab, trim, cargo } colors replacing the artwork's defaults.
function art.animation(palette)
  local animation = make_animation(constants.mod_name, palette, constants.freighter_sheets)
  for _, layer in pairs(animation.layers) do
    layer.scale = layer.scale * art.scale
  end
  return animation
end

-- A box measured on the artwork at its own scale, as { half width, half length } in tiles,
-- scaled to the mod's size and centred on the pivot.
function art.box(half_width, half_length)
  local x, y = half_width * art.scale, half_length * art.scale
  return { { -x, -y }, { x, y } }
end

return art
