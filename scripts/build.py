#!/usr/bin/env python3
"""Build Aicost using only source and checksum-pinned public dependencies."""
import argparse
import hashlib
import os
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
UPSTREAM_URL = "https://github.com/mstallone/runway/releases/download/v0.8.17/Runway-0.8.17.dmg"
UPSTREAM_SHA256 = "333c2bc27a8e9d3fa98f9d9b6d53a44b50f7d3ee91c788b7998d0e0978fa6cfb"
HELPER_SHA256 = "75a82e19206700084a5ff4e772fa461c2262ad854e7d47d76b1f2feb7b48d392"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(*arguments):
    subprocess.run(list(map(str, arguments)), check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=pathlib.Path, default=ROOT / "build")
    arguments = parser.parse_args()
    version = (ROOT / "VERSION").read_text().strip()
    output = arguments.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    app = output / "Aicost.app"
    if app.exists():
        raise SystemExit("Output application already exists; use a new --output directory.")
    cache = ROOT / ".cache"
    cache.mkdir(exist_ok=True)
    dmg = cache / "Runway-0.8.17.dmg"
    if not dmg.exists() or digest(dmg) != UPSTREAM_SHA256:
        download = dmg.with_suffix(".download")
        urllib.request.urlretrieve(UPSTREAM_URL, download)
        if digest(download) != UPSTREAM_SHA256:
            download.unlink()
            raise SystemExit("Upstream SHA-256 verification failed.")
        download.replace(dmg)
    with tempfile.TemporaryDirectory(prefix="aicost-upstream-") as temporary:
        mount = pathlib.Path(temporary) / "volume"
        run("hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount, dmg)
        try:
            upstream = mount / "Runway.app/Contents"
            helper = upstream / "Helpers/runway"
            if digest(helper) != HELPER_SHA256:
                raise SystemExit("Upstream helper SHA-256 verification failed.")
            contents = app / "Contents"
            for directory in ["MacOS", "Helpers", "Resources", "Frameworks"]:
                (contents / directory).mkdir(parents=True, exist_ok=True)
            shutil.copyfile(helper, contents / "Helpers/runway")
            os.chmod(contents / "Helpers/runway", 0o755)
            shutil.copytree(upstream / "Frameworks/Sparkle.framework", contents / "Frameworks/Sparkle.framework", symlinks=True)
            shutil.copytree(upstream / "Resources/Runway_Runway.bundle", contents / "Resources/Runway_Runway.bundle", symlinks=True)
            shutil.copyfile(ROOT / "Resources/aicost.svg", contents / "Resources/Runway_Runway.bundle/Contents/Resources/ProviderIcons/aicost.svg")
            shutil.copyfile(ROOT / "Resources/AppIcon.icns", contents / "Resources/AppIcon.icns")
            shutil.copytree(ROOT / "licenses", contents / "Resources/licenses")
            shutil.copyfile(ROOT / "LICENSE", contents / "Resources/licenses/Aicost-LICENSE.txt")
            for language in ["en", "zh-Hans"]:
                folder = contents / "Resources" / (language + ".lproj")
                folder.mkdir()
                (folder / "InfoPlist.strings").write_text('CFBundleName = "Aicost";\nCFBundleDisplayName = "Aicost";\n')
            info = {"CFBundleName": "Aicost", "CFBundleDisplayName": "Aicost", "CFBundleIdentifier": "io.github.saga029.aicost", "CFBundleExecutable": "Aicost", "CFBundlePackageType": "APPL", "CFBundleIconFile": "AppIcon", "CFBundleShortVersionString": version, "CFBundleVersion": "100", "LSMinimumSystemVersion": "15.0", "LSUIElement": True, "NSHighResolutionCapable": True, "NSPrincipalClass": "NSApplication", "CFBundleDevelopmentRegion": "en", "CFBundleLocalizations": ["en", "zh-Hans"]}
            (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        finally:
            run("hdiutil", "detach", mount)
    executable = app / "Contents/MacOS/Aicost"
    run("xcrun", "swiftc", "-parse-as-library", "-O", "-target", "arm64-apple-macosx15.0", "-framework", "SwiftUI", "-framework", "AppKit", "-framework", "Foundation", "-framework", "Charts", "-framework", "ServiceManagement", "-o", executable, ROOT / "Sources/Aicost.swift", ROOT / "Sources/UsageHistory.swift")
    run("strip", "-S", executable)
    run("codesign", "--force", "--sign", "-", app)
    run("codesign", "--verify", "--strict", app)
    print("Built", app)


if __name__ == "__main__":
    main()
