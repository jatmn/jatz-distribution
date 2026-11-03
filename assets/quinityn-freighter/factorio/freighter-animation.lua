-- Factorio 2.1 RotatedAnimation definition for the supplied 64-direction sheets.
-- By default the sheets are expected in your mod's graphics/freighter/ directory;
-- pass directory (relative to the mod root, ending in "/") to load them elsewhere.
-- All colors are freely configurable. The PNG masks themselves are grayscale.
return function(mod_name, palette, directory)
  palette = palette or {}
  local prefix = "__" .. mod_name .. "__/" .. (directory or "graphics/freighter/") .. "freighter-"
  local function layer(name, tint, shadow)
    return {
      filename = prefix .. name .. ".png",
      width = 512,
      height = 512,
      line_length = 8,
      frame_count = 1,
      direction_count = 64,
      -- Revision 2: 20% smaller; keep every body/mask/shadow layer identical.
      scale = 0.395,
      shift = { 0, 0 },
      -- Frames already use equal world-space angles in the Blender camera.
      apply_projection = false,
      draw_as_shadow = shadow or false,
      apply_runtime_tint = false,
      tint = tint or { r = 1, g = 1, b = 1, a = 1 },
    }
  end
  return {
    layers = {
      layer("shadow", nil, true),
      layer("base"),
      layer("mask-cab", palette.cab or { r = 0.48, g = 0.26, b = 0.58, a = 1 }),
      layer("mask-trim", palette.trim or { r = 0.78, g = 0.43, b = 0.14, a = 1 }),
      layer("mask-cargo", palette.cargo or { r = 0.36, g = 0.46, b = 0.57, a = 1 }),
    },
  }
end
