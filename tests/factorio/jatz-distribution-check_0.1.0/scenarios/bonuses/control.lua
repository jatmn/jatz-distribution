-- SPDX-License-Identifier: LGPL-3.0-only
-- The freighter bonuses beside the game's Bonuses window (scripts/bonus-gui.lua), against the real
-- engine with a player: tools/test_mod.py runs it with `--test-scenario jatz-distribution-check/bonuses`.
-- Opened with nothing researched, the window gets no panel. Kept open while two speed levels, three
-- item capacity levels and one fluid capacity level finish, the panel beside it lists each; while
-- an item capacity level is undone, one stack fewer; opened again, the same; while the force is
-- reset, none. Closed, it is left alone when research finishes. Open again, it shows another force's
-- research once the player is moved to it, and the first force's again once the two are merged (at
-- the end of the tick, so read on the next).
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
  if event.tick == 2 and storage.result then
    local result = storage.result
    result.merged = panel(player)
    helpers.write_file("jatz-bonuses-check.json", helpers.table_to_json(result))
    script.finish_test(true)
    return
  end
  if event.tick ~= 1 then
    return
  end
  local result = {}
  local force = player.force
  local technologies = force.technologies
  player.opened = defines.gui_type.bonus
  result.unresearched = panel(player)
  -- Each one raises on_research_finished (by script) while the window stays open.
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
  result.researched = panel(player)
  technologies["jatz-freighter-item-capacity-3"].researched = false
  result.reversed = panel(player)
  player.opened = nil
  player.opened = defines.gui_type.bonus
  result.reopened = panel(player)
  force.reset()
  result.reset = panel(player)
  player.opened = nil
  technologies["jatz-freighter-speed-1"].researched = true
  result.closed = panel(player)
  -- Another force, with item capacity instead of speed.
  local other = game.create_force("jatz-bonuses-other")
  other.technologies["jatz-freighter-item-capacity-1"].researched = true
  player.opened = defines.gui_type.bonus
  player.force = other
  result.moved = panel(player)
  -- Opened again there, so the merge must change what it shows.
  player.opened = nil
  player.opened = defines.gui_type.bonus
  game.merge_forces(other, force)
  storage.result = result
end)
