"""Render all depot variants with the shared deterministic sprite renderer."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]
REPO=ROOT.parents[1]
RENDERER=REPO/'assets/quinityn-freighter/tools/render_directions.py'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--blender',default='blender')
    parser.add_argument('--resolution',type=int,default=2048)
    parser.add_argument('--samples',type=int,default=64)
    parser.add_argument('--workers',type=int,default=2)
    parser.add_argument('--threads',type=int,default=6)
    parser.add_argument('--role')
    args=parser.parse_args()
    # The 3x3 depots, and the 1x1 road network monitor and road tunnel built in their finish.
    variants=sorted(ROOT.glob('*/3/asset.json'))+sorted(ROOT.glob('road-monitor/1/asset.json'))+sorted(ROOT.glob('road-tunnel/1/asset.json'))
    if args.role: variants=[p for p in variants if p.parents[1].name==args.role]
    assert variants, 'No built depot masters found'

    def render(metadata_path):
        folder=metadata_path.parent
        metadata=json.loads(metadata_path.read_text())
        source=ROOT/metadata['source']
        for name in ['masters/exr','masters/shadow-silhouettes','masters/layers','frames','sheets','previews']:
            (folder/name).mkdir(parents=True,exist_ok=True)
        stamp={'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
               'renderer_sha256':hashlib.sha256(RENDERER.read_bytes()).hexdigest(),
               'resolution':args.resolution,'samples':args.samples}
        record=folder/'masters/render-inputs.json'
        if record.exists() and json.loads(record.read_text())!=stamp:
            raise RuntimeError(f'Archive previous masters and exports before rerendering changed inputs: {folder}')
        record.write_text(json.dumps(stamp,indent=2)+'\n')
        command=[args.blender,'-b',str(source),'--python-exit-code','1','--python',str(RENDERER),'--',
                 '--asset-root',str(folder),'--root-object','Depot | rotate this assembly',
                 '--direction-count','4','--projection-y-scale',str(metadata['projection_y_scale']),
                 '--start','0','--end','4','--resolution',str(args.resolution),
                 '--samples',str(args.samples),'--threads',str(args.threads)]
        logs=REPO/'.local/depot-render-logs'
        logs.mkdir(parents=True,exist_ok=True)
        with (logs/(metadata['role']+'-'+str(metadata['size'])+'.log')).open('w') as log:
            subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,check=True)
            if metadata['size']==3 and not (folder/'masters/hero-default-palette.png').exists():
                subprocess.run(command+['--hero'],stdout=log,stderr=subprocess.STDOUT,check=True)
        for direction in range(4):
            assert (folder/f'masters/exr/direction-{direction:02}.exr').exists()
            assert (folder/f'masters/shadow-silhouettes/direction-{direction:02}.png').exists()
        print('RENDERED',metadata['role'],metadata['size'],flush=True)

    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        list(executor.map(render,variants))


if __name__=='__main__': main()
