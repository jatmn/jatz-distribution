"""Prepare and run the depot artwork fixture in an isolated Factorio workspace."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--factorio',required=True,type=Path)
    parser.add_argument('--data-dir',type=Path)
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    binary=args.factorio.expanduser().resolve()
    data=args.data_dir.resolve() if args.data_dir else binary.parents[2]/'data'
    if not binary.is_file() or not (data/'base/info.json').exists(): parser.error('Factorio executable or data directory missing')
    parent=root/'.local/depot-art-check'
    parent.mkdir(parents=True,exist_ok=True)
    workspace=Path(tempfile.mkdtemp(prefix='run-',dir=parent))
    mods=workspace/'mods';mods.mkdir()
    destination=mods/'depot-art-check_0.1.0'
    shutil.copytree(root/'tests/factorio/depot-art-check_0.1.0',destination)
    prototypes=destination/'prototypes';prototypes.mkdir()
    for name in ['depot-pictures.lua','depot-definitions.lua','depot-pipe-pictures.lua']:
        shutil.copy2(root/'assets/depots/factorio'/name,prototypes/name)
    for metadata in sorted((root/'assets/depots').glob('*/3/asset.json')):
        variant=metadata.parent
        graphics=destination/'graphics/depots'/variant.parent.name/variant.name
        shutil.copytree(variant/'sheets',graphics)
    shutil.copytree(root/'assets/depots/connectors/sheets',destination/'graphics/depots/connectors')
    (mods/'mod-list.json').write_text(json.dumps({'mods':[{'name':'base','enabled':True},{'name':'depot-art-check','enabled':True}]}))
    write=workspace/'write';write.mkdir()
    config=workspace/'config.ini'
    config.write_text(f'[path]\nread-data={data.as_posix()}\nwrite-data={write.as_posix()}\n')
    save=workspace/'depot-art-test.zip'
    command=[str(binary),'--config',str(config),'--mod-directory',str(mods)]
    with (workspace/'headless.log').open('w') as log:
        result=subprocess.run(command+['--create',str(save)],stdout=log,stderr=subprocess.STDOUT,timeout=180)
    report_path=write/'script-output/depot-art-check.json'
    if result.returncode or not save.exists() or not report_path.exists():
        print((workspace/'headless.log').read_text()[-6000:])
        raise SystemExit('Fixture failed. Evidence retained at '+str(workspace))
    report=json.loads(report_path.read_text())
    assert report['default_entities']==28 and report['alternate_entities']==7
    assert report['ghosts']==28 and report['rotations']==112 and report['pipe_connections']==20
    with (workspace/'reload.log').open('w') as log:
        result=subprocess.run(command+['--benchmark',str(save),'--benchmark-ticks','120','--benchmark-runs','1'],stdout=log,stderr=subprocess.STDOUT,timeout=180)
    assert result.returncode==0, (workspace/'reload.log').read_text()[-6000:]
    report['reload_120_ticks']='passed'
    (workspace/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
    print('Graphical test workspace '+str(workspace))


if __name__=='__main__': main()
