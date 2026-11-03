"""Create a self-contained four-direction depot recoloring viewer."""
import base64
from io import BytesIO
import json
from pathlib import Path

from PIL import Image, ImageDraw
from connector_preview import compose_frame

ROOT=Path(__file__).resolve().parents[1]
LAYERS=['shadow','base','mask-cab','mask-trim','mask-cargo']
roles=['provider','request','buffer','fuel','liquid-provider','liquid-request','liquid-buffer']
images=[]
file_images=[]
local_preview=ROOT.parents[1]/'.local/depot-preview'
local_preview.mkdir(parents=True,exist_ok=True)
palettes={}
metadata={}
connector_record=json.loads((ROOT/'connectors/validation.json').read_text())
for role in roles:
    for size in [3]:
        variant=ROOT/role/str(size)
        meta=json.loads((variant/'asset.json').read_text());metadata[role+'-'+str(size)]=meta
        palettes[role]=meta['palette']
        for layer in LAYERS:
            with Image.open(variant/'sheets'/f'{layer}.png') as image:
                buffer=BytesIO()
                image.resize((1024,256),Image.Resampling.LANCZOS).save(buffer,format='PNG')
            encoded=base64.b64encode(buffer.getvalue()).decode()
            image_id=f'{role}-{size}-{layer}'
            thumbnail=local_preview/f'{image_id}.png'
            thumbnail.write_bytes(buffer.getvalue())
            images.append(f'<img id="{image_id}" src="data:image/png;base64,{encoded}" hidden>')
            file_images.append(f'<img id="{image_id}" src="{thumbnail}" hidden>')
for layer in ['base','shadow']:
    with Image.open(ROOT/'connectors/sheets'/f'{layer}.png') as im:
        buffer=BytesIO();im.resize((1024,256),Image.Resampling.LANCZOS).save(buffer,format='PNG')
    encoded=base64.b64encode(buffer.getvalue()).decode();image_id='connector-'+layer
    thumbnail=local_preview/f'{image_id}.png';thumbnail.write_bytes(buffer.getvalue())
    images.append(f'<img id="{image_id}" src="data:image/png;base64,{encoded}" hidden>')
    file_images.append(f'<img id="{image_id}" src="{thumbnail}" hidden>')
output=ROOT/'previews'
output.mkdir(exist_ok=True)
for size in [3]:
    board=Image.new('RGBA',(1024,7*256),(55,58,60,255))
    draw=ImageDraw.Draw(board)
    for row,role in enumerate(roles):
        for direction in range(4):
            variant=ROOT/role/str(size)
            tile=compose_frame(metadata[role+'-'+str(size)],direction,Image.open(variant/f'frames/preview-{direction:02}.png'),Image.open(variant/f'frames/shadow-{direction:02}.png'))
            board.paste(tile.resize((256,256),Image.Resampling.LANCZOS),(direction*256,row*256))
        draw.text((10,row*256+8),role+' '+str(size)+'x'+str(size),fill='white')
    board.save(output/f'all-depots-{size}.png')
# Active 3x3 designs keep native 32 pixels per tile and a common ground row.
world=Image.new('RGBA',(1440,7*264),(55,58,60,255));draw=ImageDraw.Draw(world)
for row,role in enumerate(roles):
    for direction,name in enumerate(['N','E','S','W']):
        for size,xoffset in [(3,0)]:
            variant=ROOT/role/str(size);meta=metadata[role+'-'+str(size)]
            tile=compose_frame(meta,direction,Image.open(variant/f'frames/preview-{direction:02}.png'),Image.open(variant/f'frames/shadow-{direction:02}.png'))
            pixels=round(512*meta['game_scale'])
            world.paste(tile.resize((pixels,pixels),Image.Resampling.LANCZOS),(direction*360+xoffset,row*264+132-pixels//2))
        draw.text((direction*360+8,row*264+8),role+' '+name+' / 3x3',fill='white')
world.save(output/'all-depots-world-scale.png')
html='''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Depot model and tint preview</title>
<style>
body{margin:0;font:14px/1.5 var(--font-sans,system-ui);color:var(--foreground,#ddd)}
.controls{display:flex;flex-wrap:wrap;gap:12px;margin:12px 0;align-items:center}label{display:flex;align-items:center;gap:6px}
select,button{padding:7px;background:var(--card,#24292d);color:var(--foreground,#ddd);border:1px solid var(--border,#555);border-radius:var(--radius,8px)}
input[type=color]{width:36px;height:30px;padding:0;border:0;background:none}.stage{padding:16px;border-radius:var(--radius,12px);background:var(--secondary,#404447)}
canvas{display:block;width:100%;max-width:560px;margin:auto}.note{font-size:12px;color:var(--muted-foreground,#aaa)}
</style></head><body>
<div class="controls"><label>Depot <select id="role">OPTIONS</select></label><label>Variant <select id="size"><option value="3">3×3</option></select></label><label>Facing <select id="heading"><option value="0">North</option><option value="1">East</option><option value="2" selected>South</option><option value="3">West</option></select></label></div>
<div class="controls"><label>Role <input type="color" id="cab"></label><label>Clamps <input type="color" id="trim"></label><label>Housing <input type="color" id="cargo"></label><button id="reset">Default colors</button><button id="alternate">Alternate colors</button></div>
<div class="stage"><canvas id="view" width="512" height="512"></canvas></div>
<div class="controls"><label><input id="shadow" type="checkbox" checked>Shadow</label><label><input id="neutral" type="checkbox">Neutral masks</label></div>
<p class="note">Four rendered directions for each of seven active 3×3 depots. The 1×1 source assets are preserved in archive/1x1.</p>
<p class="note">Built from editable Blender masters. This viewer composites exported layers and registered connector pictures. Graphical-client checks for pipe covers, overlays and sprite alignment remain pending.</p>
IMAGES
<script>
const palettes=PALETTES,metadata=METADATA,connectorShift=CONNECTORSHIFT;
const layers=['shadow','base','mask-cab','mask-trim','mask-cargo'];
const canvas=document.querySelector('#view'),ctx=canvas.getContext('2d');
const scratch=document.createElement('canvas');scratch.width=scratch.height=256;const sc=scratch.getContext('2d');let ready=false;
function paint(){
 if(!ready)return;
 const role=document.querySelector('#role').value,size=document.querySelector('#size').value,heading=Number(document.querySelector('#heading').value);
 ctx.clearRect(0,0,512,512);
 const meta=metadata[role+'-'+size],pixels=512/meta.ortho_scale,csize=512*2.5/meta.ortho_scale;
 function connectors(layer,north){
  for(const port of meta.ports){
   let [x,y]=port.position;for(let n=0;n<heading;n++)[x,y]=[-y,x];
   const d=(port.direction/4+heading)%4;
   if(layer==='base'&&(d===0)!==north)continue;
   const image=document.getElementById('connector-'+layer),shift=layer==='base'?connectorShift:0;
   ctx.drawImage(image,d*256,0,256,256,256+x*pixels-csize/2,256+(y+shift)*pixels-csize/2,csize,csize);
  }
 }
 if(document.querySelector('#shadow').checked){
  const image=document.getElementById(role+'-'+size+'-shadow');ctx.drawImage(image,heading*256,0,256,256,0,0,512,512);connectors('shadow',false);
 }
 connectors('base',true);
 for(const layer of layers){
  if(layer==='shadow')continue;
  const image=document.getElementById(role+'-'+size+'-'+layer);
  sc.clearRect(0,0,256,256);sc.globalCompositeOperation='source-over';sc.drawImage(image,heading*256,0,256,256,0,0,256,256);
  if(layer.startsWith('mask-')&&!document.querySelector('#neutral').checked){
   sc.globalCompositeOperation='multiply';sc.fillStyle=document.getElementById(layer.slice(5)).value;sc.fillRect(0,0,256,256);
   sc.globalCompositeOperation='destination-in';sc.drawImage(image,heading*256,0,256,256,0,0,256,256);
  }
  ctx.drawImage(scratch,0,0,512,512);
 }
 connectors('base',false);
}
function reset(){for(const [name,color] of Object.entries(palettes[document.querySelector('#role').value]))document.getElementById(name).value='#'+color.map(v=>Math.round(v*255).toString(16).padStart(2,'0')).join('');paint();}
document.querySelector('#role').addEventListener('change',reset);
document.querySelectorAll('input,select').forEach(input=>input.addEventListener('input',paint));
document.querySelector('#reset').onclick=reset;
document.querySelector('#alternate').onclick=()=>{for(const [name,color] of Object.entries({cab:'#d91fb3',trim:'#1ae6d9',cargo:'#c7c7c7'}))document.getElementById(name).value=color;paint();};
Promise.all([...document.querySelectorAll('img')].map(image=>image.decode())).then(()=>{ready=true;reset();});
</script></body></html>'''
html=html.replace('OPTIONS',''.join(f'<option value="{role}">{role.replace("-"," ").title()} Depot</option>' for role in roles)).replace('PALETTES',json.dumps(palettes)).replace('METADATA',json.dumps(metadata)).replace('CONNECTORSHIFT',str(connector_record['picture_shift'][1]))
(output/'recolor.html').write_text(html.replace('IMAGES',''.join(images)))
(local_preview/'inline.html').write_text(html.replace('IMAGES',''.join(file_images)))
print(output/'recolor.html')
