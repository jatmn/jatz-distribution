"""Validate the freighter game atlases: tint neutrality, alpha composition and layout.

The committed game atlases (sheets/) are always checked. Render intermediates
(masters/exr, masters/layers, masters/shadow-silhouettes and frames) are not
tracked in Git. When they exist locally after a render and package run, they
are checked as well, including frame-to-atlas equality.
"""
import hashlib
import json

import numpy as np
from PIL import Image

from package_sprites import LAYERS, ROOT, over

DIRECTIONS = 64
CELL = 512
INTERMEDIATES = ("masters/exr", "masters/layers", "masters/shadow-silhouettes", "frames")


def check_direction(images, size, label):
    """Check one heading's layer set and return its alpha reconstruction error."""
    arrays = {}
    for layer in LAYERS:
        image = images[layer]
        assert image.size == (size, size), (label, layer, image.size)
        assert image.mode == "RGBA", (label, layer, image.mode)
        array = np.array(image, dtype=np.float32) / 255
        alpha = array[..., 3]
        assert np.any(alpha > 0), (label, layer, "empty layer")
        edge = max(alpha[0].max(), alpha[-1].max(), alpha[:, 0].max(), alpha[:, -1].max())
        assert edge < .005, (label, layer, "clipped boundary")
        if layer.startswith("mask-"):
            assert np.array_equal(array[..., 0], array[..., 1]), (label, layer, "colored mask")
            assert np.array_equal(array[..., 1], array[..., 2]), (label, layer, "colored mask")
        arrays[layer] = array
    combined = arrays["base"]
    for layer in ["mask-cab", "mask-trim", "mask-cargo"]:
        combined = over(arrays[layer], combined)
    error = float(np.abs(combined[..., 3] - arrays["preview"][..., 3]).max())
    assert error < 3 / 255, (label, error)
    return error


checks = []
sheets = {layer: Image.open(ROOT / "sheets" / f"freighter-{layer}.png") for layer in LAYERS}
for layer, sheet in sheets.items():
    assert sheet.size == (8 * CELL, 8 * CELL), (layer, sheet.size)


def cell(sheet, direction):
    x, y = (direction % 8) * CELL, (direction // 8) * CELL
    return sheet.crop((x, y, x + CELL, y + CELL))


for direction in range(DIRECTIONS):
    images = {layer: cell(sheet, direction) for layer, sheet in sheets.items()}
    error = check_direction(images, CELL, f"atlas cell {direction}")
    checks.append({"source": "sheets", "size": CELL, "direction": direction, "quantized_alpha_max_error": error})

present = [name for name in INTERMEDIATES if (ROOT / name).is_dir()]
if "masters/layers" in present:
    for direction in range(DIRECTIONS):
        images = {layer: Image.open(ROOT / "masters" / "layers" / f"{layer}-{direction:02d}.png") for layer in LAYERS}
        error = check_direction(images, 1024, f"master layer {direction}")
        checks.append({"source": "masters/layers", "size": 1024, "direction": direction, "quantized_alpha_max_error": error})
if "frames" in present:
    for layer, sheet in sheets.items():
        for direction in range(DIRECTIONS):
            frame = Image.open(ROOT / "frames" / f"{layer}-{direction:02d}.png")
            assert np.array_equal(np.array(frame), np.array(cell(sheet, direction))), (layer, direction, "atlas mismatch")
for directory, pattern in [("masters/exr", "*.exr"), ("masters/shadow-silhouettes", "*.png")]:
    if directory in present:
        assert len(list((ROOT / directory).glob(pattern))) == DIRECTIONS, (directory, "incorrect direction count")

summary = {"status": "passed", "directions": DIRECTIONS, "game_frame_size": CELL, "atlas_size": 8 * CELL,
           "tint_masks": 3, "atlas_cells_checked": DIRECTIONS * len(LAYERS),
           "local_intermediates_checked": present,
           "max_quantized_alpha_error": max(c["quantized_alpha_max_error"] for c in checks),
           "checks": checks}
(ROOT / "asset-validation.json").write_text(json.dumps(summary, indent=2) + "\n")

# Hash the tracked deliverables only; local render intermediates are excluded.
manifest = {}
for path in sorted(ROOT.rglob("*")):
    relative = path.relative_to(ROOT).as_posix()
    if any(relative.startswith(name + "/") for name in INTERMEDIATES):
        continue
    if path.is_file() and path.suffix in {".png", ".blend", ".lua", ".py", ".webp"}:
        manifest[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
(ROOT / "checksums.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(json.dumps({k: v for k, v in summary.items() if k != "checks"}, indent=2))
