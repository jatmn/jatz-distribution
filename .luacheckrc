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
-- The mod's source at the repository root. pipecoverspictures is a data-stage helper
-- defined by the base game.
files["data*.lua"].globals = {"data"}
files["settings*.lua"].globals = {"data"}
files["prototypes/**"].globals = {"data"}
files["prototypes/**"].read_globals = {"pipecoverspictures"}
files["control.lua"].globals = {"game", "storage"}
files["control.lua"].read_globals = {"script", "prototypes", "helpers", "remote", "rendering"}
files["scripts/**"].globals = {"game", "storage"}
files["scripts/**"].read_globals = {"script", "prototypes", "helpers", "remote", "rendering"}

-- Lua unit tests run outside Factorio and stand in for its runtime globals.
files["tests/lua/**"].globals = {"defines", "prototypes", "script", "storage", "game"}

-- Artwork test fixtures: each tests/factorio/<mod>/ is a complete mod with the same stage split.
-- pipecoverspictures is a data-stage helper defined by the base game.
files["tests/factorio/*/data*.lua"].globals = {"data"}
files["tests/factorio/*/data*.lua"].read_globals = {"pipecoverspictures"}
files["tests/factorio/*/control.lua"].globals = {"game", "storage"}
files["tests/factorio/*/control.lua"].read_globals = {"script", "prototypes", "helpers", "remote", "rendering"}
