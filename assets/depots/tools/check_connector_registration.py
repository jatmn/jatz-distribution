"""Audit all depot ports against the independently rendered connector registration.

This is a projection/asset audit, not a replacement for full-client seam checks.
"""
from pathlib import Path
import hashlib
import json
import math

ROOT = Path(__file__).resolve().parents[1]
record = json.loads((ROOT/'connectors/validation.json').read_text())
assert record['source_sha256'] == hashlib.sha256((ROOT/'source/pipe-connector.blend').read_bytes()).hexdigest()
assert record['renderer_sha256'] == hashlib.sha256((ROOT/'tools/render_connector.py').read_bytes()).hexdigest()
assert record['pipe_picture_engine_origin'] == 'neighboring_pipe_center'
vectors = [(0,-1),(1,0),(0,1),(-1,0)]
checks = []
for path in sorted(ROOT.glob('*/3/asset.json')):
    meta = json.loads(path.read_text())
    for heading in range(4):
        for port in meta['ports']:
            x,y = port['position']
            for _ in range(heading):
                x,y = -y,x
            direction = (port['direction']//4+heading)%4
            dx,dy = vectors[direction]
            measured = record['registration'][direction]
            assert .60 <= measured['barrel_width_tiles'] <= .64
            # Source origin is the interior edge tile, engine origin is its neighbor.
            neighbor = (x+dx,y+dy)
            seam = (neighbor[0]-dx+measured['registered_seam'][0],
                    neighbor[1]-dy+measured['registered_seam'][1])
            expected = (x+.5*dx,y+.5*dy-.025)
            assert max(abs(a-b) for a,b in zip(seam,expected)) < 1e-5
            assert math.isclose(abs(x+.5*dx) if dx else abs(y+.5*dy),meta['size']/2)
            checks.append({'role':meta['role'],'size':meta['size'],'heading':heading*4,
                           'port_direction':direction*4,'neighbor':neighbor,'visible_seam_tiles':seam,
                           'barrel_width_at_1x_pixels':32*measured['barrel_width_tiles']})
assert len(checks) == 20
output = {'status':'passed','rotated_ports':20,'reference_commit':record['reference_commit'],
          'native_measurement':'49–51 px at 80 px/tile; approximate center offset −0.025 tile',
          'graphical_acceptance':'pending','checks':checks}
(ROOT/'connectors/registration-validation.json').write_text(json.dumps(output,indent=2)+'\n')
print('PASS: 20 rotated ports, fixed native pipe scale and visible centerline')
