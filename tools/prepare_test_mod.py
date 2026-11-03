"""Assemble the isolated Factorio artwork fixture from tracked source assets."""
import argparse
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = ROOT / ".local" / "factorio"
MOD_NAME = "freighter-art-check_0.1.0"


def prepare(replace=False):
    marker = WORKSPACE / "jatz-test-workspace.json"
    if WORKSPACE.exists() and any(WORKSPACE.iterdir()) and not marker.exists():
        raise RuntimeError(f"Refusing to modify an unrecognized workspace: {WORKSPACE}")
    destination = WORKSPACE / "mods" / MOD_NAME
    if destination.exists() and not replace:
        raise RuntimeError("Fixture already exists. Use --replace to refresh this isolated fixture.")
    WORKSPACE.mkdir(parents=True, exist_ok=True)
    marker.write_text(json.dumps({"project": "Jat'z Distribution", "purpose": "isolated Factorio artwork tests"}) + "\n")
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(ROOT / "tests" / "factorio" / MOD_NAME, destination)
    graphics = destination / "graphics" / "freighter"
    graphics.mkdir(parents=True)
    asset = ROOT / "assets" / "quinityn-freighter"
    for layer in ["base", "mask-cab", "mask-trim", "mask-cargo", "shadow"]:
        shutil.copy2(asset / "sheets" / f"freighter-{layer}.png", graphics)
    prototypes = destination / "prototypes"
    prototypes.mkdir()
    shutil.copy2(asset / "factorio" / "freighter-animation.lua", prototypes)
    mod_list = {"mods": [{"name": "base", "enabled": True}, {"name": "freighter-art-check", "enabled": True}]}
    (WORKSPACE / "mods" / "mod-list.json").write_text(json.dumps(mod_list, indent=2) + "\n")
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--replace", action="store_true", help="Replace the generated fixture inside the owned .local workspace")
    args = parser.parse_args()
    print(prepare(args.replace))
