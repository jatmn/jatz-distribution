"""Run the artwork fixture with a local Factorio 2.1 binary."""
import argparse
import json
import subprocess
from pathlib import Path

from prepare_test_mod import ROOT, WORKSPACE, prepare


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--factorio", type=Path, required=True, help="Path to the Factorio executable")
    parser.add_argument("--data-dir", type=Path, help="Factorio data directory, if it cannot be inferred from bin/x64")
    args = parser.parse_args()
    binary = args.factorio.expanduser().resolve()
    if not binary.is_file():
        parser.error(f"Factorio binary does not exist: {binary}")
    data = args.data_dir.expanduser().resolve() if args.data_dir else binary.parents[2] / "data"
    if not (data / "base" / "info.json").is_file():
        parser.error("Cannot locate Factorio data. Supply --data-dir with a directory containing base/info.json.")
    version = subprocess.check_output([str(binary), "--version"], text=True).strip()
    prepare(replace=True)
    write_data = WORKSPACE / "write"
    write_data.mkdir(exist_ok=True)
    config = WORKSPACE / "config.ini"
    config.write_text(f"[path]\nread-data={data.as_posix()}\nwrite-data={write_data.as_posix()}\n")
    save = WORKSPACE / "freighter-test.zip"
    save.unlink(missing_ok=True)
    log_path = WORKSPACE / "headless.log"
    command = [str(binary), "--config", str(config), "--mod-directory", str(WORKSPACE / "mods"), "--create", str(save)]
    with log_path.open("w") as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    log_text = log_path.read_text()
    marker = "FREIGHTER_ART_CHECK passed 64 orientations and alternate palette prototype"
    passed = result.returncode == 0 and marker in log_text and save.is_file()
    report = {"status": "passed" if passed else "failed", "engine_version": version,
              "headings": 64, "alternate_palette": True, "graphical_client_tested": False,
              "exit_code": result.returncode, "save": str(save.relative_to(ROOT)),
              "log": str(log_path.relative_to(ROOT))}
    (WORKSPACE / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    if not passed:
        print(log_text[-6000:])
        raise SystemExit(1)


if __name__ == "__main__":
    main()
