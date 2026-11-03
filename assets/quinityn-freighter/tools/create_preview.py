"""Create a local, self-contained recoloring and direction inspection page."""
import base64
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
LAYERS=["shadow","base","mask-cab","mask-trim","mask-cargo"]
images=[]
for layer in LAYERS:
    encoded=base64.b64encode((ROOT/"previews"/f"compass-{layer}.png").read_bytes()).decode()
    images.append(f'<img id="{layer}" src="data:image/png;base64,{encoded}" hidden>')
html='''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Quinityn freighter color and direction preview</title>
<style>
body{font-family:var(--font-sans,system-ui);color:var(--foreground,#d9e1e5);margin:0}
.controls{display:flex;flex-wrap:wrap;gap:14px;align-items:center;margin:12px 0}
label{font-size:14px;display:flex;align-items:center;gap:7px}input[type=color]{width:42px;height:30px;border:0;background:none;padding:0}
button,select{color:var(--foreground,#d9e1e5);background:var(--card,#242a2d);border:1px solid var(--border,#455158);border-radius:6px;padding:7px}
.stage{border-radius:var(--radius,12px);background:#4a4e4c;overflow:hidden;text-align:center}
canvas{display:block;width:100%;max-width:640px;height:auto;margin:auto;image-rendering:auto}
.note{font-size:13px;color:var(--muted-foreground,#a4b0b6);line-height:1.5;margin:10px 0}
</style></head><body>
<div class="controls">
<label>Cab <input type="color" id="cab" value="#7a4294"></label>
<label>Clamps <input type="color" id="trim" value="#c76e24"></label>
<label>Cargo <input type="color" id="cargo" value="#5c7591"></label>
<button id="default">Default palette</button>
<button id="alternate">Alternate palette</button>
</div>
<div class="stage"><canvas id="view" width="768" height="640"></canvas></div>
<div class="controls">
<label>Direction <select id="heading"><option value="0">North</option><option value="1">North-east</option><option value="2">East</option><option value="3">South-east</option><option value="4">South</option><option value="5" selected>South-west</option><option value="6">West</option><option value="7">North-west</option></select></label>
<button id="rotate">Rotate</button>
<label><input type="checkbox" id="showShadow" checked> Shadow</label>
<label><input type="checkbox" id="masks"> Neutral masks</label>
</div>
<p class="note">Eight headings are shown here. The exported set contains all 64 directions. Colors are applied to grayscale masks over the base artwork. Steel, glazing, tires and lamps retain their original colors.</p>
IMAGES
<script>
const canvas=document.getElementById('view'),ctx=canvas.getContext('2d');
const scratch=document.createElement('canvas');scratch.width=512;scratch.height=512;
const sc=scratch.getContext('2d');
let ready=false,timer=null;
function paint(){
 if(!ready)return;
 const h=Number(document.getElementById('heading').value),x=(h%4)*512,y=Math.floor(h/4)*512;
 ctx.clearRect(0,0,768,640);
 for(const name of ['shadow','base','mask-cab','mask-trim','mask-cargo']){
  if(name==='shadow'&&!document.getElementById('showShadow').checked)continue;
  const img=document.getElementById(name);
  sc.clearRect(0,0,512,512);sc.globalCompositeOperation='source-over';
  sc.drawImage(img,x,y,512,512,0,0,512,512);
  if(name.startsWith('mask-')&&!document.getElementById('masks').checked){
   sc.globalCompositeOperation='multiply';sc.fillStyle=document.getElementById(name.slice(5)).value;sc.fillRect(0,0,512,512);
   sc.globalCompositeOperation='destination-in';sc.drawImage(img,x,y,512,512,0,0,512,512);
  }
  ctx.drawImage(scratch,64,0,640,640);
 }
}
function setPalette(values){for(const [name,value] of Object.entries(values))document.getElementById(name).value=value;paint();}
document.getElementById('default').onclick=()=>setPalette({cab:'#7a4294',trim:'#c76e24',cargo:'#5c7591'});
document.getElementById('alternate').onclick=()=>setPalette({cab:'#42ce80',trim:'#ec5252',cargo:'#dadbdb'});
document.getElementById('rotate').onclick=()=>{if(timer){clearInterval(timer);timer=null;document.getElementById('rotate').textContent='Rotate';}else{timer=setInterval(()=>{const heading=document.getElementById('heading');heading.value=(Number(heading.value)+1)%8;paint();},450);document.getElementById('rotate').textContent='Stop';}};
for(const input of document.querySelectorAll('input,select'))input.addEventListener('input',paint);
Promise.all([...document.querySelectorAll('img')].map(img=>img.decode())).then(()=>{ready=true;paint();});
</script></body></html>'''.replace('IMAGES',''.join(images))
(ROOT/'previews'/'recolor.html').write_text(html)
print(ROOT/'previews'/'recolor.html')
