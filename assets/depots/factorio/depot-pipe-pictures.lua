-- Engine pipe pictures are positioned at the neighboring pipe center.
-- Move back one tile to register this master's internal-anchor origin.
-- Keep this scale independent of the depot's 3x3/1x1 body scale.
-- By default the sheets are expected in graphics/depots/connectors/; pass directory
-- (relative to the mod root, ending in "/") to load them elsewhere.
return function(mod_name, directory)
  local pictures = {}
  local origins = { { 0, 1 }, { -1, 0 }, { 0, -1 }, { 1, 0 } }
  for index, direction in ipairs({ "north", "east", "south", "west" }) do
    local function layer(name, shadow)
      return {
        filename = "__" .. mod_name .. "__/" .. (directory or "graphics/depots/connectors/") .. name .. ".png",
        width = 512,
        height = 512,
        x = (index - 1) * 512,
        y = 0,
        scale = 0.15625,
        shift = { origins[index][1], origins[index][2] + (shadow and 0 or 0.2295584412271571) },
        draw_as_shadow = shadow,
      }
    end
    pictures[direction] = { layers = { layer("shadow", true), layer("base", false) } }
  end
  return pictures
end
