"""Package and validate the shared untinted full-size pipe-picture layers."""
from pathlib import Path
import hashlib,json
import numpy as np
from PIL import Image,ImageFilter
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
# StyLua-formatted (.stylua.toml) so the regenerated file passes the CI format check.
lua="""-- Engine pipe pictures are positioned at the neighboring pipe center.
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
""".replace('SHIFT',str(shift))
(ROOT/'factorio/depot-pipe-pictures.lua').write_text(lua)
report={'pipe_picture_engine_origin':'neighboring_pipe_center','status':'passed','directions':4,'master_layers':8,'game_layers':8,'atlas_cells':8,**record}
(out/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('PACKAGED4 full-size registered pipe pictures',flush=True)
