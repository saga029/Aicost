#!/usr/bin/env python3
"""Package only the built application and write its checksum."""
import argparse
import hashlib
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--app", type=pathlib.Path, default=ROOT / "build/Aicost.app")
parser.add_argument("--output", type=pathlib.Path, default=ROOT / "dist")
arguments = parser.parse_args()
version = (ROOT / "VERSION").read_text().strip()
app = arguments.app.resolve()
if not app.is_dir() or app.name != "Aicost.app":
    raise SystemExit("Expected a built Aicost.app")
subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True)
arguments.output.mkdir(parents=True, exist_ok=True)
archive = arguments.output / ("Aicost-" + version + "-macos-arm64.zip")
subprocess.run(["ditto", "-c", "-k", "--norsrc", "--noextattr", "--keepParent", str(app), str(archive)], check=True)
checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
(archive.with_suffix(archive.suffix + ".sha256")).write_text(checksum + "  " + archive.name + "\n")
print(archive)
