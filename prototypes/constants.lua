-- SPDX-License-Identifier: LGPL-3.0-only
-- Shared names and asset locations for the data stage.
return {
  mod_name = "jatz-distribution",
  subgroup = "jatz-distribution",
  freighter_sheets = "assets/quinityn-freighter/sheets/",
  -- The freighter is drawn at 60% of the artwork's scale (prototypes/freighter-art.lua).
  freighter_scale = 0.6,
  -- string.format pattern taking (role, size), relative to the mod root.
  depot_sheets = "assets/depots/%s/%d/sheets/",
  connector_sheets = "assets/depots/connectors/sheets/",
  -- What destroyed depots and freighters leave (prototypes/remnants.lua): a string.format pattern
  -- taking a depot wreck's name, and the freighter's wreck.
  depot_remnant_sheets = "assets/depots/remnants/%s/sheets/",
  freighter_remnant_sheets = "assets/quinityn-freighter/remnants/freighter/sheets/",
  -- 64 px icons with custom mipmaps, made by tools/make_icons.py from the game sprites.
  freighter_icon = "__jatz-distribution__/assets/quinityn-freighter/icons/quinityn-freighter.png",
  -- string.format pattern taking the depot role.
  depot_icon = "__jatz-distribution__/assets/depots/icons/%s-depot.png",
  icon_size = 64,
  -- 256 px technology icons, made by tools/make_icons.py from the same game frames.
  freighter_technology_icon = "__jatz-distribution__/assets/quinityn-freighter/technology/quinityn-freighter.png",
  liquid_technology_icon = "__jatz-distribution__/assets/depots/technology/liquid-provider-depot.png",
  monitor_technology_icon = "__jatz-distribution__/assets/depots/technology/road-monitor.png",
  technology_icon_size = 256,
  -- The 1x1 loading zone marking (assets/depots/tools/make_loading_zone.py): 64 px at scale 0.5.
  loading_zone = "__jatz-distribution__/assets/depots/loading-zone/loading-zone.png",
  -- With Space Age, the freighter's second recipe, fuelled with carbon (prototypes/freighter.lua).
  freighter_carbon_recipe = "jatz-quinityn-freighter-carbon",
  -- The road tile, its item and recipe; Yuoki slag path art (assets/roads/README.md).
  road = "jatz-road",
  -- The road a depot lays under its loading zone sign (prototypes/roads.lua, scripts/depot-road.lua).
  depot_road = "jatz-depot-road",
  road_art = "assets/roads/yuoki-railways/",
  -- Collision layer on every tile except roads; the freighter drone collides with it alone.
  off_road_layer = "jatz_off_road",
  -- Collision layer on the road tiles; buildings other than belts, pipes and tracks collide with it.
  road_layer = "jatz_road",
  -- The freighter that drives itself between depots.
  freighter_drone = "jatz-freighter-drone",
  -- The invisible chest robots bring freighters into for a liquid depot (prototypes/truck-chest.lua).
  truck_chest = "jatz-truck-chest",
  -- The hidden tank under a Fuel depot that holds its liquid fuel (prototypes/depots.lua).
  fuel_tank = "jatz-fuel-depot-tank",
  -- The combinator that reads what the depots on its road network hold (prototypes/road-monitor.lua).
  road_monitor = "jatz-road-monitor",
  -- A road tunnel's portal (prototypes/road-tunnel.lua), and how many tiles apart two may be.
  road_tunnel = "jatz-road-tunnel",
  tunnel_reach = 32,
  tunnel_technology_icon = "__jatz-distribution__/assets/depots/technology/road-tunnel.png",
  -- A blueprint's copy of a request or buffer depot's request, for parametrisation
  -- (prototypes/depot-settings.lua).
  depot_settings = "jatz-depot-settings",
}
