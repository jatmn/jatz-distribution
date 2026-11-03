"""Package neutral tint layers using the established freighter AOV pipeline."""
import hashlib
import importlib.util
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from connector_preview import compose_frame
from depot_lua import definitions_lua

ROOT=Path(__file__).resolve().parents[1]
REPO=ROOT.parents[1]
spec=importlib.util.spec_from_file_location('shared_packager',REPO/'assets/quinityn-freighter/tools/package_sprites.py')
shared=importlib.util.module_from_spec(spec)
spec.loader.exec_module(shared)
LAYERS=['shadow','base','mask-cab','mask-trim','mask-cargo','preview']


def write_definitions():
    (ROOT/'factorio/depot-definitions.lua').write_text(definitions_lua(ROOT))


def main():
    report=[]
    resolutions=set()
    for metadata_path in sorted(ROOT.glob('*/3/asset.json')):
        folder=metadata_path.parent
        meta=json.loads(metadata_path.read_text())
        inputs=json.loads((folder/'masters/render-inputs.json').read_text())
        resolutions.add(inputs['resolution'])
        assert inputs['source_sha256']==hashlib.sha256((ROOT/meta['source']).read_bytes()).hexdigest()
        shared.ROOT=folder
        shared.PALETTE=meta['palette']
        checks=[]
        for direction in range(4):
            checks.append(shared.extract(direction,[(inputs['resolution'],folder/'masters/layers'),(512,folder/'frames')]))
        for layer in LAYERS:
            atlas=Image.new('RGBA',(2048,512))
            for direction in range(4):
                frame=Image.open(folder/f'frames/{layer}-{direction:02}.png')
                atlas.paste(frame,(direction*512,0))
            atlas.save(folder/f'sheets/{layer}.png')
        board=Image.new('RGBA',(1536,384),(51,54,55,255))
        draw=ImageDraw.Draw(board)
        for direction,name in enumerate(meta['directions']):
            tile=compose_frame(meta,direction,Image.open(folder/f'frames/preview-{direction:02}.png'),Image.open(folder/f'frames/shadow-{direction:02}.png'),(51,54,55,255))
            board.paste(tile.resize((384,384),Image.Resampling.LANCZOS),(direction*384,0))
            draw.text((direction*384+12,12),name,fill='white')
        board.save(folder/'previews/four-directions.png')
        for direction in range(4):
            for layer in LAYERS:
                with Image.open(folder/f'masters/layers/{layer}-{direction:02}.png') as master:
                    assert master.mode=='RGBA' and master.size==(inputs['resolution'],inputs['resolution'])
                    array=np.asarray(master)
                    assert array[:,:,3].max()>0
                    assert not np.any(array[[0,-1],:,3]) and not np.any(array[:,[0,-1],3]), 'Clipped master'
                    if layer.startswith('mask-'):
                        assert np.array_equal(array[:,:,0],array[:,:,1]) and np.array_equal(array[:,:,1],array[:,:,2])
            for layer in LAYERS:
                path=folder/f'frames/{layer}-{direction:02}.png'
                with Image.open(path) as image:
                    assert image.mode=='RGBA' and image.size==(512,512)
                    array=np.asarray(image)
                    alpha=array[:,:,3]
                    assert alpha.max()>0, f'Empty layer {path}'
                    assert not np.any(alpha[[0,-1],:]) and not np.any(alpha[:,[0,-1]]), f'Clipped {path}'
                    if layer.startswith('mask-'):
                        assert np.array_equal(array[:,:,0],array[:,:,1]) and np.array_equal(array[:,:,1],array[:,:,2])
                    with Image.open(folder/f'sheets/{layer}.png') as atlas:
                        assert np.array_equal(array,np.asarray(atlas.crop((direction*512,0,(direction+1)*512,512))))
            arrays=[np.asarray(Image.open(folder/f'frames/{layer}-{direction:02}.png'),dtype=np.float32)/255 for layer in ['base','mask-cab','mask-trim','mask-cargo']]
            alpha=arrays[0][:,:,3]
            for mask in arrays[1:]: alpha=mask[:,:,3]+alpha*(1-mask[:,:,3])
            reference=np.asarray(Image.open(folder/f'frames/preview-{direction:02}.png'),dtype=np.float32)[:,:,3]/255
            assert np.max(np.abs(alpha-reference))<.015
        assert len({hashlib.sha256((folder/f'frames/preview-{d:02}.png').read_bytes()).hexdigest() for d in range(4)})==4
        result={'role':meta['role'],'size':meta['size'],'source_sha256':inputs['source_sha256'],'directions':checks}
        report.append(result)
        (folder/'validation.json').write_text(json.dumps(result,indent=2)+'\n')
        print('PACKAGED AND VALIDATED',meta['role'],meta['size'],flush=True)
    write_definitions()
    summary={'status':'passed','variants':len(report),'direction_sets':len(report)*4,'frame_layers_checked':len(report)*4*6,'master_layers_checked':len(report)*4*6,'atlas_cells_checked':len(report)*4*6,'master_resolutions':sorted(resolutions),'game_resolution':512,'results':report}
    (ROOT/'validation.json').write_text(json.dumps(summary,indent=2)+'\n')


if __name__=='__main__': main()
