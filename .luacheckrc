stds.factorio = {
  read_globals = {
    "defines", "log", "settings",
    table = {fields = {deepcopy = {}}},
  },
}
std = "lua52+factorio"
not_globals = {"io", "os", "dofile", "loadfile", "coroutine"}
max_line_length = false
exclude_files = {"build/**", ".cache/**"}

-- Factorio's data and runtime environments expose different globals.
-- Mod files at the repository root (none yet; the mod code comes next).
files["data*.lua"].globals = {"data"}
files["settings*.lua"].globals = {"data"}
files["prototypes/**"].globals = {"data"}
files["control.lua"].globals = {"game", "storage"}
files["control.lua"].read_globals = {"script", "prototypes", "helpers", "remote", "rendering"}
files["scripts/**"].globals = {"game", "storage"}
files["scripts/**"].read_globals = {"script", "prototypes", "helpers", "remote", "rendering"}

-- Artwork test fixtures: each tests/factorio/<mod>/ is a complete mod with the same stage split.
-- pipecoverspictures is a data-stage helper defined by the base game.
files["tests/factorio/*/data*.lua"].globals = {"data"}
files["tests/factorio/*/data*.lua"].read_globals = {"pipecoverspictures"}
files["tests/factorio/*/control.lua"].globals = {"game", "storage"}
files["tests/factorio/*/control.lua"].read_globals = {"script", "prototypes", "helpers", "remote", "rendering"}
