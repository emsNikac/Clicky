#!/usr/bin/env python3
"""Fetch only the recordings used by Clicky, pinned to an upstream revision."""
import hashlib
import io
import json
from pathlib import Path
import subprocess
import zipfile

REVISION = "ba103f3b0afa9dab80447aa2e7e2ed80b6bd80e4"
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Clicky" / "Resources" / "Sounds"
PACKS = {"alpaca", "blackink", "bluealps", "boxnavy", "buckling", "cream",
         "holypanda", "mxblack", "mxblue", "mxbrown", "redink", "topre", "turquoise"}
PRESS = {"GENERIC_R0", "GENERIC_R1", "GENERIC_R2", "GENERIC_R3", "GENERIC_R4",
         "SPACE", "ENTER", "BACKSPACE"}
RELEASE = {"GENERIC", "SPACE", "ENTER", "BACKSPACE"}


def main():
    # macOS curl uses the system certificate store, including managed certificates.
    data = subprocess.run(["/usr/bin/curl", "--fail", "--silent", "--show-error",
                           "--location", "--max-time", "60",
                           f"https://codeload.github.com/tplai/kbsim/zip/{REVISION}"],
                          check=True, capture_output=True).stdout
    archive = zipfile.ZipFile(io.BytesIO(data))
    prefix = f"kbsim-{REVISION}/"
    license_text = archive.read(prefix + "LICENSE.md")
    assert b"Copyright (c) Thomas Lai" in license_text
    assert b"Permission is hereby granted" in license_text
    recordings = {}
    for name in archive.namelist():
        relative = name.removeprefix(prefix + "src/assets/audio/")
        parts = relative.split("/")
        if len(parts) != 3:
            continue
        pack, action, filename = parts
        if pack not in PACKS or not filename.endswith(".mp3"):
            continue
        stem = Path(filename).stem
        if stem not in (PRESS if action == "press" else RELEASE if action == "release" else set()):
            continue
        recordings[f"{pack}_{action}_{filename}"] = (name, archive.read(name))
    for pack in PACKS:
        required = [f"{pack}_press_GENERIC_R{row}.mp3" for row in range(5)]
        required.append(f"{pack}_release_GENERIC.mp3")
        if pack != "mxblue":
            required += [f"{pack}_{action}_{key}.mp3"
                         for action in ("press", "release") for key in ("SPACE", "ENTER", "BACKSPACE")]
        assert all(filename in recordings for filename in required), f"Incomplete pack: {pack}"
    OUTPUT.mkdir(parents=True, exist_ok=True)
    manifest = {}
    for filename, (source, data) in sorted(recordings.items()):
        (OUTPUT / filename).write_bytes(data)
        manifest[filename] = {"source": source.removeprefix(prefix),
                              "sha256": hashlib.sha256(data).hexdigest()}
    (OUTPUT / "KBSIM-LICENSE.txt").write_bytes(license_text)
    (OUTPUT / "recordings.json").write_text(json.dumps(
        {"repository": "https://github.com/tplai/kbsim", "revision": REVISION,
         "files": manifest}, indent=2) + "\n")
    print(f"Imported {len(recordings)} original recordings across {len(PACKS)} packs.")


if __name__ == "__main__":
    main()
