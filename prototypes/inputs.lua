-- SPDX-License-Identifier: LGPL-3.0-only
-- Key bindings the request panel listens to. Linked to the game's own controls, so they follow the
-- player's key settings and don't appear as separate controls.
data:extend({
  {
    -- Pipette (Q by default) over the freighter slot picks up a freighter, or its ghost in remote
    -- view, like over any inventory slot (scripts/request-gui.lua).
    type = "custom-input",
    name = "jatz-pipette",
    key_sequence = "",
    linked_game_control = "pipette",
    consuming = "none",
  },
})
