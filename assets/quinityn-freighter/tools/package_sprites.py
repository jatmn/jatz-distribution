"""Build aligned grayscale tint layers from the neutral OpenEXR master passes.

Requires Python, numpy, Pillow and OpenEXR. No generative edits occur here.
"""
import argparse
import json
from pathlib import Path

import numpy as np
import OpenEXR
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
LAYERS = ["base", "mask-cab", "mask-trim", "mask-cargo", "shadow", "preview"]
PALETTE = {"cab": [.48,.26,.58], "trim": [.78,.43,.14], "cargo": [.36,.46,.57]}

def linear_to_srgb(value):
    value = np.maximum(value, 0)
    return np.where(value <= .0031308, value*12.92, 1.055*value**(1/2.4)-.055)

def resize_float(array, size):
    if array.shape[:2] == (size,size):
        return array.copy()
    if array.ndim == 2:
        return np.array(Image.fromarray(array.astype(np.float32)).resize((size,size),Image.Resampling.LANCZOS))
    return np.stack([resize_float(array[...,i], size) for i in range(array.shape[2])],axis=-1)

def png(array):
    return Image.fromarray(np.uint8(np.clip(array,0,1)*255+.5), "RGBA")

def over(front, back):
    fa=front[...,3:4]
    ba=back[...,3:4]
    alpha=fa+ba*(1-fa)
    rgb=(front[...,:3]*fa+back[...,:3]*ba*(1-fa))/np.maximum(alpha,1e-8)
    return np.concatenate([rgb,alpha],axis=-1)

def extract(direction, sizes):
    file=OpenEXR.File(str(ROOT/"masters"/"exr"/f"direction-{direction:02d}.exr"))
    channels=file.channels()
    beauty=channels["Vehicle.Combined"].pixels.astype(np.float32)
    alpha=np.clip(beauty[...,3],0,1)
    # Combined is scene-linear and associated (premultiplied) with alpha.
    rgb=beauty[...,:3]/np.maximum(alpha[...,None],1e-8)
    rgb=np.clip(linear_to_srgb(rgb),0,1)
    premult=rgb*alpha[...,None]
    masks=[]
    for name in ["cab","trim","cargo"]:
        key=next(k for k in channels if k.startswith("Vehicle.mask_"+name+"."))
        masks.append(channels[key].pixels.astype(np.float32))
    raw_masks=np.stack(masks,axis=-1)
    shadow_alpha=np.array(Image.open(ROOT/"masters"/"shadow-silhouettes"/f"direction-{direction:02d}.png").getchannel("A"),dtype=np.float32)/255
    report={"direction":direction,"sizes":{}}
    for size,folder in sizes:
        a=np.clip(resize_float(alpha,size),0,1)
        p=np.clip(resize_float(premult,size),0,1)
        color=p/np.maximum(a[...,None],1e-8)
        weights=np.clip(resize_float(raw_masks,size),0,1)
        total=weights.sum(axis=-1)
        weights*=np.minimum(1,a/np.maximum(total,1e-8))[...,None]
        # Disjoint sample coverage is converted into source-over alpha in the
        # documented base -> cab -> trim -> cargo order. This avoids dark seams.
        remaining=np.ones_like(a)
        layer_alphas=[]
        for i in [2,1,0]:
            layer_alphas.insert(0,np.clip(weights[...,i]/np.maximum(remaining,1e-8),0,1))
            remaining-=weights[...,i]
        base_alpha=np.clip((a-weights.sum(axis=-1))/np.maximum(remaining,1e-8),0,1)
        gray=np.clip(color @ np.array([.2126,.7152,.0722]),0,1)
        grayscale=np.repeat(gray[...,None],3,axis=-1)
        result={"base":np.concatenate([color,base_alpha[...,None]],axis=-1)}
        for name,mask_alpha in zip(["cab","trim","cargo"],layer_alphas):
            result["mask-"+name]=np.concatenate([grayscale,mask_alpha[...,None]],axis=-1)
        shadow=np.zeros((size,size,4),dtype=np.float32)
        silhouette=np.clip(resize_float(shadow_alpha,size),0,1)
        blurred=Image.fromarray(np.uint8(silhouette*255)).filter(ImageFilter.GaussianBlur(size/1024*1.4))
        shadow[...,3]=np.array(blurred,dtype=np.float32)/255*.45
        result["shadow"]=shadow
        preview=result["base"].copy()
        neutral=preview.copy()
        for name in ["cab","trim","cargo"]:
            mask=result["mask-"+name]
            neutral=over(mask,neutral)
            tinted=mask.copy()
            tinted[...,:3]*=np.array(PALETTE[name])
            preview=over(tinted,preview)
        result["preview"]=preview
        folder.mkdir(parents=True,exist_ok=True)
        for name,array in result.items():
            # Clear invisible RGB to avoid hidden data in transparent margins.
            array[array[...,3]<.5/255,:3]=0
            png(array).save(folder/f"{name}-{direction:02d}.png")
        opaque=a>.01
        neutral_error=np.abs(neutral[...,:3]-color)*a[...,None]
        report["sizes"][size]={
            "alpha_max_error":float(np.abs(neutral[...,3]-a).max()),
            "neutral_rgb_mean_error":float(neutral_error[opaque].mean()),
            "body_bbox":png(result["preview"]).getbbox(),
            "shadow_bbox":png(shadow).getbbox(),
            "mask_pixels":{name:int(np.count_nonzero(result['mask-'+name][...,3]>.01)) for name in PALETTE},
        }
    return report

def make_sheets(count):
    for layer in LAYERS:
        sheet=Image.new("RGBA",(4096,4096))
        for direction in range(count):
            frame=Image.open(ROOT/"frames"/f"{layer}-{direction:02d}.png")
            sheet.paste(frame,((direction%8)*512,(direction//8)*512))
        sheet.save(ROOT/"sheets"/f"freighter-{layer}.png")

def make_previews(count):
    if count!=64:
        return
    directions=list(range(0,64,8))
    for layer in LAYERS:
        atlas=Image.new("RGBA",(2048,1024))
        for i,direction in enumerate(directions):
            frame=Image.open(ROOT/"frames"/f"{layer}-{direction:02d}.png")
            atlas.paste(frame,((i%4)*512,(i//4)*512))
        atlas.save(ROOT/"previews"/f"compass-{layer}.png")
    turntable=[]
    for direction in range(64):
        background=Image.new("RGBA",(512,512),(73,77,76,255))
        background.alpha_composite(Image.open(ROOT/"frames"/f"shadow-{direction:02d}.png"))
        background.alpha_composite(Image.open(ROOT/"frames"/f"preview-{direction:02d}.png"))
        turntable.append(background.convert("RGB"))
    turntable[0].save(ROOT/"previews"/"turntable.webp",save_all=True,append_images=turntable[1:],duration=85,loop=0,quality=90)
    sheet=Image.new("RGB",(1024,1024),(73,77,76))
    draw=ImageDraw.Draw(sheet)
    for direction in range(64):
        frame=turntable[direction].resize((128,128),Image.Resampling.LANCZOS)
        x,y=(direction%8)*128,(direction//8)*128
        sheet.paste(frame,(x,y))
        draw.text((x+4,y+4),f"{direction:02d}",fill="white")
    sheet.save(ROOT/"previews"/"all-64-directions.png")

if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--count",type=int,default=64)
    args=parser.parse_args()
    report=[]
    for direction in range(args.count):
        report.append(extract(direction,[(1024,ROOT/"masters"/"layers"),(512,ROOT/"frames")]))
        print("PACKAGED",direction,flush=True)
    if args.count==64:
        make_sheets(args.count)
        make_previews(args.count)
    (ROOT/"validation.json").write_text(json.dumps(report,indent=2)+"\n")
