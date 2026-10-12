#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
project_root="$PWD"
scratch="$project_root/.clicky-verification"
if [[ -e "$scratch" ]]; then
    echo "Verification directory already exists: $scratch" >&2
    exit 1
fi
mkdir "$scratch"
app="$scratch/DerivedData/Build/Products/Debug/Clicky.app"
cleanup() {
    # Xcode registers macOS build products even when code signing is disabled.
    # Remove this disposable verification app before deleting its files.
    if [[ -d "$app" ]]; then
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
            -u "$app" >/dev/null 2>&1 || true
    fi
    rm -rf "$scratch"
}
trap cleanup EXIT

if ! xcodebuild -project Clicky.xcodeproj -scheme Clicky -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$scratch/DerivedData" \
    -clonedSourcePackagesDirPath "$scratch/SourcePackages" \
    CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO \
    PRODUCT_BUNDLE_IDENTIFIER=com.projects.Clicky.verification \
    CLANG_MODULE_CACHE_PATH="$scratch/ModuleCache" \
    SWIFT_MODULE_CACHE_PATH="$scratch/ModuleCache" \
    build > "$scratch/build.log" 2>&1; then
    tail -100 "$scratch/build.log"
    exit 1
fi
echo "PASS: macOS application build."
python3 - "$app" <<'PY'
import hashlib, json, plistlib, sys
from pathlib import Path
app = Path(sys.argv[1])
resources = app / "Contents" / "Resources"
manifest = json.loads((resources / "recordings.json").read_text())
assert len(manifest["files"]) == 150
for name, entry in manifest["files"].items():
    assert hashlib.sha256((resources / name).read_bytes()).hexdigest() == entry["sha256"], name
assert "Copyright (c) Thomas Lai" in (resources / "KBSIM-LICENSE.txt").read_text()
info = plistlib.loads((app / "Contents" / "Info.plist").read_bytes())
assert info["LSUIElement"] is True, "App must stay in the menu bar."
assert info["CFBundleIconFile"] == "Clicky.icns", "System app icon is not configured."
assert not info.get("CFBundleIconName"), "System icon must use the standalone ICNS resource."
icon = resources / info["CFBundleIconFile"]
if not icon.suffix:
    icon = icon.with_suffix(".icns")
assert icon.is_file() and icon.stat().st_size > 0, "Compiled macOS icon is missing."
assert (resources / "Assets.car").is_file(), "Menu bar image assets are missing."
print("PASS: bundled recording integrity, license, and menu bar configuration.")
print("PASS: compiled macOS icon and image asset catalog.")
PY
xcrun swiftc -parse-as-library -module-cache-path "$scratch/ModuleCache" \
    Clicky/SwitchProfile.swift Clicky/PhysicalKeyboard.swift Clicky/RecordingDecoder.swift \
    Clicky/VolumeMode.swift Clicky/SystemOutputMonitor.swift Clicky/PlaybackSettings.swift \
    Tests/VolumeModeChecks.swift Tests/IconChecks.swift Tests/AudioChecks.swift -o "$scratch/AudioChecks"
"$scratch/AudioChecks" "$app/Contents/Resources"
echo "Verification complete. Removing project-local build artifacts."
