-- Four Sprite4Way views, all layers share a camera, canvas and ground pivot.
-- Internal cab/trim/cargo AOV names map to role/clamps/housing paint.
local definitions = require("prototypes.depot-definitions")
return function(mod_name, role, size, palette)
  local definition = definitions[role][size]
  palette = palette or {}
  local prefix = "__" .. mod_name .. "__/graphics/depots/" .. role .. "/" .. size .. "/"
  local pictures = {}
  for index, direction in ipairs({ "north", "east", "south", "west" }) do
    local function layer(name, tint, shadow)
      return {
        filename = prefix .. name .. ".png",
        width = 512,
        height = 512,
        x = (index - 1) * 512,
        y = 0,
        scale = definition.scale,
        shift = { 0, 0 },
        tint = tint or { 1, 1, 1 },
        draw_as_shadow = shadow or false,
      }
    end
    pictures[direction] = {
      layers = {
        layer("shadow", nil, true),
        layer("base"),
        layer("mask-cab", palette.role or definition.palette.role),
        layer("mask-trim", palette.clamps or definition.palette.clamps),
        layer("mask-cargo", palette.housing or definition.palette.housing),
      },
    }
  end
  return pictures
end
