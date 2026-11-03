-- SPDX-License-Identifier: LGPL-3.0-only
-- Put the Jat'z Distribution row directly above the row with the car and tank (the "transport"
-- subgroup) in the crafting menu and Factoriopedia, wherever other mods have moved that row.
local constants = require("prototypes.constants")

-- An order string that sorts immediately before `order`: after every other string below it.
-- Orders compare as plain strings, so lowering the last character and appending "~" (the
-- highest printable ASCII character) sorts after every string with that lowered prefix.
local function just_before(order)
  local last = order:byte(-1)
  if not last or last <= 32 then
    return nil
  end
  return order:sub(1, -2) .. string.char(last - 1) .. "~"
end

local ours = data.raw["item-subgroup"][constants.subgroup]
local transport = data.raw["item-subgroup"]["transport"]
local order = transport and just_before(transport.order or "")
if order then
  ours.group = transport.group
  ours.order = order
end
