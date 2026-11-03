"""Composite the independently registered connectors for offline sprite inspection."""
from pathlib import Path
import json
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]

def connector_layers(meta,heading):
    record=json.loads((ROOT/'connectors/validation.json').read_text())
    width=round(512*record['ortho_scale']/meta['ortho_scale']);pixels=512/meta['ortho_scale']
    result=[]
    for port in meta['ports']:
        x,y=port['position']
        for _ in range(heading):x,y=-y,x
        direction=(port['direction']//4+heading)%4
        layers={}
        for layer,shift in [('base',record['picture_shift'][1]),('shadow',0)]:
            image=Image.open(ROOT/f'connectors/frames/{layer}-{direction:02}.png').convert('RGBA')
            image=image.resize((width,width),Image.Resampling.LANCZOS)
            layers[layer]=(image,(round(256+x*pixels-width/2),round(256+(y+shift)*pixels-width/2)))
        result.append((direction,layers))
    return result

def compose_frame(meta,heading,body,shadow,background=(55,58,60,255)):
    image=Image.new('RGBA',(512,512),background);image.alpha_composite(shadow)
    connectors=connector_layers(meta,heading)
    for direction,layers in connectors:image.alpha_composite(*layers['shadow'])
    for direction,layers in connectors:
        if direction==0:image.alpha_composite(*layers['base'])
    image.alpha_composite(body)
    for direction,layers in connectors:
        if direction!=0:image.alpha_composite(*layers['base'])
    return image
