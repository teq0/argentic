#!/usr/bin/env python3
"""Generate macOS and iOS app-icon assets from icons/argentic.icon.png.

Run from the repository root with: python3 app/Tools/generate_app_icon.py
Requires macOS's sips tool and the Xcode Swift toolchain. Generated PNGs and the
AppIcon manifest are checked in. macOS gets a rounded tile; iOS keeps the original.
"""
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "icons/argentic.icon.png"
OUTPUT = ROOT / "app/Argentic/Assets.xcassets/AppIcon.appiconset"
MAC_RENDERER = ROOT / "app/Tools/render_macos_icon.swift"


def main():
    properties = subprocess.check_output(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", "-g", "hasAlpha", str(SOURCE)], text=True
    )
    values = dict(re.findall(r"^\s*(pixelWidth|pixelHeight|hasAlpha):\s*(\S+)", properties, re.MULTILINE))
    if values.get("pixelWidth") != "1024" or values.get("pixelHeight") != "1024":
        raise SystemExit("The source app icon must be a 1024 × 1024 PNG.")
    if values.get("hasAlpha") != "no":
        raise SystemExit("The source app icon must be opaque (no alpha channel) for iOS.")

    OUTPUT.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(SOURCE, OUTPUT / "icon-ios-1024.png")
    mac_master = OUTPUT / "icon-1024.png"
    subprocess.run(["xcrun", "swift", str(MAC_RENDERER), str(SOURCE), str(mac_master)], check=True)
    for size in [16, 32, 64, 128, 256, 512]:
        destination = OUTPUT / f"icon-{size}.png"
        subprocess.run(
            ["sips", "--resampleHeightWidth", str(size), str(size), str(mac_master), "--out", str(destination)],
            check=True, stdout=subprocess.DEVNULL,
        )

    images = [
        {"filename": f"icon-{size * scale}.png", "idiom": "mac", "scale": f"{scale}x", "size": f"{size}x{size}"}
        for size in [16, 32, 128, 256, 512] for scale in [1, 2]
    ]
    images.append({"filename": "icon-ios-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"})
    manifest = {"images": images, "info": {"author": "xcode", "version": 1}}
    (OUTPUT / "Contents.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Generated app icons in {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
