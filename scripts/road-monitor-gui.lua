-- SPDX-License-Identifier: LGPL-3.0-only
-- The road network monitor's panel: opening a monitor shows this instead of the constant
-- combinator's own window, so players choose what it reads (scripts/road-monitor.lua) but can't
-- edit its signals, which it sets itself. A small window in the middle of the screen with one
-- radio button per reading; it is the player's opened GUI, so E and Esc close it.
-- scripts/request-gui.lua passes the GUI events on to it (control.lua keeps one handler per event).
local road_monitor = require("scripts.road-monitor")

local monitor_gui = {}

local FRAME = "jatz_monitor_frame"
-- One radio button per reading: "jatz_monitor_reading_supply", "..._providers", and so on.
local READING = "jatz_monitor_reading_"

local function close(player)
  local frame = player and player.valid and player.gui.screen[FRAME]
  if frame then
    frame.destroy()
  end
  if storage.monitor_gui and player then
    storage.monitor_gui[player.index] = nil
  end
end

-- Tick the monitor's reading, and only that.
local function show(frame, entity)
  local reading = road_monitor.get_reading(entity)
  for _, name in ipairs(road_monitor.readings) do
    frame.inner[READING .. name].state = name == reading
  end
end

function monitor_gui.open(player, entity)
  close(player)
  local frame = player.gui.screen.add({
    type = "frame",
    name = FRAME,
    direction = "vertical",
    caption = entity.localised_name,
  })
  frame.auto_center = true
  local inner = frame.add({
    type = "frame",
    name = "inner",
    style = "inside_shallow_frame_with_padding",
    direction = "vertical",
  })
  inner.add({ type = "label", caption = { "jatz-gui.monitor-reading" }, style = "caption_label" })
  for _, name in ipairs(road_monitor.readings) do
    inner.add({
      type = "radiobutton",
      name = READING .. name,
      state = false,
      caption = { "jatz-gui.monitor-reading-" .. name },
      tooltip = { "jatz-gui.monitor-reading-" .. name .. "-tooltip" },
    })
  end
  storage.monitor_gui = storage.monitor_gui or {}
  storage.monitor_gui[player.index] = entity
  show(frame, entity)
  -- Closes the combinator's own window, which the game opened first.
  player.opened = frame
end

-- A monitor opened: its panel instead. Returns whether the event was the monitor's.
function monitor_gui.on_gui_opened(event)
  local entity = event.entity
  if not (entity and entity.valid and entity.name == road_monitor.name) then
    return false
  end
  local player = game.get_player(event.player_index)
  if player then
    monitor_gui.open(player, entity)
  end
  return true
end

-- The panel closed (E, Esc or opening something else). Returns whether it was the panel.
function monitor_gui.on_gui_closed(event)
  local element = event.element
  if not (element and element.valid and element.name == FRAME) then
    return false
  end
  close(game.get_player(event.player_index))
  return true
end

-- A reading chosen. Returns whether the event was the panel's.
function monitor_gui.on_gui_checked_state_changed(event)
  local reading = event.element.name:match("^" .. READING .. "(%a+)$")
  if not reading then
    return false
  end
  local player = game.get_player(event.player_index)
  local entity = storage.monitor_gui and storage.monitor_gui[event.player_index]
  if entity and entity.valid then
    road_monitor.set_reading(entity, reading)
    show(player.gui.screen[FRAME], entity)
  else
    -- The monitor is gone.
    close(player)
  end
  return true
end

return monitor_gui
