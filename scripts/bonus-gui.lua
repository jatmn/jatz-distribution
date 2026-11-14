-- SPDX-License-Identifier: LGPL-3.0-only
-- What research gives freighters, beside the game's Bonuses window. Freighter upgrades are
-- scripted (`nothing` modifiers, scripts/research.lua), and the window lists only the game's own
-- modifiers, so this panel, anchored to it, lists ours: built afresh for the player's force each
-- time the window opens (on_gui_opened with defines.gui_type.bonus, probed on 2.1.24), and left
-- out while nothing is researched, as the game leaves out bonuses it doesn't have.
-- scripts/request-gui.lua passes it the opened event (control.lua keeps one handler per event).
local research = require("scripts.research")

local bonus_gui = {}

local FRAME = "jatz_bonus_frame"

-- A force's freighter bonuses, one localised line each, only those it has researched.
function bonus_gui.lines(force)
  local lines = {}
  local speed = research.levels(force, research.speed)
  if speed > 0 then
    lines[#lines + 1] = { "jatz-bonus.freighter-speed", math.floor(research.speed_bonus * speed * 100 + 0.5) }
  end
  local stacks = research.extra_stacks(force)
  if stacks > 0 then
    lines[#lines + 1] = { "jatz-bonus.freighter-item-capacity", stacks }
  end
  local fluid = research.extra_fluid(force)
  if fluid > 0 then
    lines[#lines + 1] = { "jatz-bonus.freighter-fluid-capacity", fluid }
  end
  return lines
end

-- The Bonuses window opened: our panel beside it. Returns whether the event was that window's.
function bonus_gui.on_gui_opened(event)
  if event.gui_type ~= defines.gui_type.bonus then
    return false
  end
  local player = game.get_player(event.player_index)
  if not player then
    return true
  end
  local old = player.gui.relative[FRAME]
  if old then
    old.destroy()
  end
  local lines = bonus_gui.lines(player.force)
  if #lines == 0 then
    return true
  end
  local frame = player.gui.relative.add({
    type = "frame",
    name = FRAME,
    caption = { "jatz-bonus.title" },
    direction = "vertical",
    anchor = { gui = defines.relative_gui_type.bonus_gui, position = defines.relative_gui_position.right },
  })
  local inner = frame.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  inner.add({ type = "sprite", sprite = "item/jatz-quinityn-freighter" })
  for _, line in ipairs(lines) do
    inner.add({ type = "label", caption = line })
  end
  return true
end

return bonus_gui
