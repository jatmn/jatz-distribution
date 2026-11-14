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
-- The mod's source at the repository root. pipecoverspictures and the circuit connector helpers
-- are data-stage helpers defined by the base game and core; mods lists the active mods.
files["data*.lua"].globals = {"data"}
files["settings*.lua"].globals = {"data"}
files["prototypes/**"].globals = {"data"}
files["prototypes/**"].read_globals = {
  "pipecoverspictures", "circuit_connector_definitions", "universal_connector_template",
  "default_circuit_wire_max_distance", "mods",
}
files["control.lua"].globals = {"game", "storage"}
files["control.lua"].read_globals = {"script", "prototypes", "helpers", "remote", "rendering", "commands"}
files["scripts/**"].globals = {"game", "storage"}
files["scripts/**"].read_globals = {"script", "prototypes", "helpers", "remote", "rendering"}
-- Migration scripts run once in the runtime stage when a save loads the new version.
files["migrations/**"].globals = {"game", "storage"}
files["migrations/**"].read_globals = {"script", "prototypes", "helpers", "remote", "rendering"}

-- Lua unit tests run outside Factorio and stand in for its runtime globals.
files["tests/lua/**"].globals = {"defines", "prototypes", "script", "storage", "game", "remote", "commands", "rendering"}

-- Artwork test fixtures: each tests/factorio/<mod>/ is a complete mod with the same stage split.
-- pipecoverspictures is a data-stage helper defined by the base game.
files["tests/factorio/*/data*.lua"].globals = {"data"}
files["tests/factorio/*/data*.lua"].read_globals = {"pipecoverspictures"}
files["tests/factorio/*/control.lua"].globals = {"game", "storage"}
files["tests/factorio/*/control.lua"].read_globals = {"script", "prototypes", "helpers", "remote", "rendering"}
-- Scenarios a test mod ships (run with --test-scenario <mod>/<name>) are runtime scripts too.
files["tests/factorio/*/scenarios/*/control.lua"].globals = {"game", "storage"}
files["tests/factorio/*/scenarios/*/control.lua"].read_globals = {"script", "prototypes", "helpers", "remote", "rendering"}
