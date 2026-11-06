-- SPDX-License-Identifier: LGPL-3.0-only
-- Where the road network monitor's wires meet its terminal posts, their shadows, and its status
-- lens, in tiles from its centre, for each direction (north, east, south, west): the "points" in
-- assets/depots/road-monitor/1/asset.json, which assets/depots/tools/build_depots.py works out
-- from the model with the renderer's projection. Copy them again after rebuilding the model;
-- tools/test_mod_setup.py checks that they match.
return {
  wire = {
    { red = { -0.1533, -0.5171 }, green = { 0.1533, -0.5171 } },
    { red = { 0.14, -0.5305 }, green = { 0.14, -0.2238 } },
    { red = { 0.1533, -0.2371 }, green = { -0.1533, -0.2371 } },
    { red = { -0.14, -0.2238 }, green = { -0.14, -0.5305 } },
  },
  wire_shadow = {
    { red = { 0.1133, -0.3914 }, green = { 0.42, -0.3914 } },
    { red = { 0.4067, -0.4047 }, green = { 0.4067, -0.0981 } },
    { red = { 0.42, -0.1114 }, green = { 0.1133, -0.1114 } },
    { red = { 0.1267, -0.0981 }, green = { 0.1267, -0.4047 } },
  },
  lens = {
    { 0.2, -0.1684 },
    { -0.1333, -0.1017 },
    { -0.2, -0.435 },
    { 0.1333, -0.5017 },
  },
}
