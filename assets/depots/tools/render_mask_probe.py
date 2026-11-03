"""Low-resolution source render to inspect all paint coverage AOVs before export."""
import bpy,math,json,hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[3];out=root/'.local/depot-mask-probe';out.mkdir(parents=True,exist_ok=True)
stamp=out/'inputs.json'
stamp.unlink(missing_ok=True)
inputs={}
for metadata in sorted((root/'assets/depots').glob('*/3/asset.json')):
 source=root/'assets/depots'/json.loads(metadata.read_text())['source']
 inputs[source.name]=hashlib.sha256(source.read_bytes()).hexdigest()
 bpy.ops.wm.open_mainfile(filepath=str(source))
 scene=bpy.data.scenes['Scene'];bpy.context.window.scene=scene
 scene.render.threads_mode='FIXED';scene.render.threads=2
 scene.render.resolution_x=scene.render.resolution_y=256;scene.cycles.samples=4
 scene.render.image_settings.file_format='OPEN_EXR_MULTILAYER';scene.render.image_settings.color_depth='16'
 for d in range(4):
  bpy.data.objects['Depot | rotate this assembly'].rotation_euler.z=-d*math.pi/2
  scene.render.filepath=str(out/(source.stem+f'-{d}.exr'))
  bpy.ops.render.render(write_still=True)
stamp.write_text(json.dumps(inputs,indent=2)+'\n')
