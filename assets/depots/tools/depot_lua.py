# SPDX-License-Identifier: LGPL-3.0-only
"""Render the generated depot Lua files from committed data, using only the standard library.

package_depots.py and package_connector.py write these files during packaging.
tools/test_depot_lua.py regenerates them in CI and requires the committed files
to match, so the generators and their StyLua-formatted output cannot drift apart.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFINITIONS = ROOT / 'factorio/depot-definitions.lua'
PIPE_PICTURES = ROOT / 'factorio/depot-pipe-pictures.lua'
CONNECTOR_RECORD = ROOT / 'connectors/validation.json'


def definitions_lua(root=ROOT):
    """depot-definitions.lua from every active <role>/3/asset.json, in StyLua format."""
    lines = ['-- Generated from asset.json files by package_depots.py.', 'return {']
    for role in sorted({path.parents[1].name for path in root.glob('*/3/asset.json')}):
        lines.append(f'  ["{role}"] = {{')
        for size in [3]:
            meta = json.loads((root / role / str(size) / 'asset.json').read_text())
            lines += [f'    [{size}] = {{', f'      size = {size},', f'      scale = {meta["game_scale"]},', '      palette = {']
            for semantic, channel in [('role', 'cab'), ('clamps', 'trim'), ('housing', 'cargo')]:
                values = ', '.join(str(value) for value in meta['palette'][channel])
                lines.append(f'        {semantic} = {{ {values} }},')
            lines.append('      },')
            if meta['ports']:
                lines.append('      ports = {')
                for port in meta['ports']:
                    x, y = port['position']
                    lines.append(f'        {{ direction = {port["direction"]}, position = {{ {x}, {y} }}, '
                                 'hide_connection_info = false },')
                lines.append('      },')
            else:
                lines.append('      ports = {},')
            lines.append('    },')
        lines.append('  },')
    lines.append('}')
    return '\n'.join(lines) + '\n'


PIPE_PICTURES_TEMPLATE = """-- Engine pipe pictures are positioned at the neighboring pipe center.
-- Move back one tile to register this master's internal-anchor origin.
-- Keep this scale independent of the depot's 3x3/1x1 body scale.
return function(mod_name)
  local pictures = {}
  local origins = { { 0, 1 }, { -1, 0 }, { 0, -1 }, { 1, 0 } }
  for index, direction in ipairs({ "north", "east", "south", "west" }) do
    local function layer(name, shadow)
      return {
        filename = "__" .. mod_name .. "__/graphics/depots/connectors/" .. name .. ".png",
        width = 512,
        height = 512,
        x = (index - 1) * 512,
        y = 0,
        scale = 0.15625,
        shift = { origins[index][1], origins[index][2] + (shadow and 0 or SHIFT) },
        draw_as_shadow = shadow,
      }
    end
    pictures[direction] = { layers = { layer("shadow", true), layer("base", false) } }
  end
  return pictures
end
"""


def pipe_pictures_lua(shift):
    """depot-pipe-pictures.lua for the connector's registered vertical picture shift, in StyLua format."""
    return PIPE_PICTURES_TEMPLATE.replace('SHIFT', str(shift))


def recorded_pipe_shift(record_path=CONNECTOR_RECORD):
    """The vertical picture shift that package_connector.py recorded with the committed connector sprites."""
    return json.loads(Path(record_path).read_text())['picture_shift'][1]
