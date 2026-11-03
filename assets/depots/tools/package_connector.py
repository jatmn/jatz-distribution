"""Package and validate the shared untinted full-size pipe-picture layers."""
from pathlib import Path
import hashlib,json
import numpy as np
from PIL import Image,ImageFilter
from depot_lua import pipe_pictures_lua
ROOT=Path(__file__).resolve().parents[1];out=ROOT/'connectors';masters=out/'masters'
record=json.loads((masters/'render-inputs.json').read_text())
assert record['source_sha256']==hashlib.sha256((ROOT/'source/pipe-connector.blend').read_bytes()).hexdigest()
assert record['renderer_sha256']==hashlib.sha256((ROOT/'tools/render_connector.py').read_bytes()).hexdigest()
for folder in ['frames','sheets','layers']:(out/folder).mkdir(exist_ok=True)
for layer in ['base','shadow']:
    atlas=Image.new('RGBA',(2048,512))
    for i,direction in enumerate(['north','east','south','west']):
        source=masters/(direction+('-shadow' if layer=='shadow' else '')+'.png')
        im=Image.open(source).convert('RGBA');assert im.size==(2048,2048)
        if layer=='shadow':
            alpha=im.getchannel('A').filter(ImageFilter.GaussianBlur(2.8)).point(lambda x:round(x*.45))
            im=Image.new('RGBA',im.size);im.putalpha(alpha)
        im.save(out/'layers'/f'{layer}-{i:02}.png')
        for resolution in [2048,512]:
            frame=im if resolution==2048 else im.resize((512,512),Image.Resampling.LANCZOS)
            a=np.asarray(frame)[:,:,3]
            assert a.max()>0 and not a[[0,-1],:].any() and not a[:,[0,-1]].any()
            if resolution==512:
                frame.save(out/'frames'/f'{layer}-{i:02}.png');atlas.paste(frame,(i*512,0))
    atlas.save(out/'sheets'/f'{layer}.png')
    for i in range(4):
        assert np.array_equal(np.asarray(Image.open(out/'frames'/f'{layer}-{i:02}.png')),np.asarray(atlas.crop((512*i,0,512*(i+1),512))))
shift=record['picture_shift'][1]
lua=pipe_pictures_lua(shift)
(ROOT/'factorio/depot-pipe-pictures.lua').write_text(lua)
report={'pipe_picture_engine_origin':'neighboring_pipe_center','status':'passed','directions':4,'master_layers':8,'game_layers':8,'atlas_cells':8,**record}
(out/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('PACKAGED4 full-size registered pipe pictures',flush=True)
