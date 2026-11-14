-- SPDX-License-Identifier: LGPL-3.0-only
-- The freighter bonuses beside the game's Bonuses window (scripts/bonus-gui.lua), against the real
-- engine with a player: tools/test_mod.py runs it with `--test-scenario jatz-distribution-check/bonuses`.
-- Opened with nothing researched, the window gets no panel; opened again after two speed levels,
-- three item capacity levels and one fluid capacity level, the panel beside it lists each.
-- Writes script-output/jatz-bonuses-check.json.
local FRAME = "jatz_bonus_frame"

-- What the panel shows: its anchor and the localised string of each line.
local function panel(player)
  local frame = player.gui.relative[FRAME]
  if not frame then
    return "none"
  end
  local lines = {}
  for _, element in ipairs(frame.children[1].children) do
    if element.type == "label" then
      local caption = element.caption
      lines[#lines + 1] = { caption[1], caption[2] }
    end
  end
  return {
    beside_bonuses = frame.anchor.gui == defines.relative_gui_type.bonus_gui,
    title = frame.caption[1],
    lines = lines,
  }
end

script.on_event(defines.events.on_tick, function(event)
  local player = game.get_player(1)
  if not player then
    return
  end
  if event.tick == 1 then
    storage.result = {}
    player.opened = defines.gui_type.bonus
    storage.result.unresearched = panel(player)
    player.opened = nil
    local technologies = player.force.technologies
    for _, name in ipairs({
      "jatz-freighter-speed-1",
      "jatz-freighter-speed-2",
      "jatz-freighter-item-capacity-1",
      "jatz-freighter-item-capacity-2",
      "jatz-freighter-item-capacity-3",
      "jatz-freighter-fluid-capacity-1",
    }) do
      technologies[name].researched = true
    end
  elseif storage.result and event.tick == 2 then
    player.opened = defines.gui_type.bonus
    storage.result.researched = panel(player)
    player.opened = nil
    helpers.write_file("jatz-bonuses-check.json", helpers.table_to_json(storage.result))
    script.finish_test(true)
  end
end)
