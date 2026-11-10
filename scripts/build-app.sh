#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
swift build -c release -debug-info-format none --disable-sandbox --cache-path "$PWD/.build/swiftpm-cache"
binary_dir="$(swift build -c release --show-bin-path --disable-sandbox --cache-path "$PWD/.build/swiftpm-cache")"
app_path="$PWD/dist/SwitchKeyboard.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_dir/SwitchKeyboard" "$app_path/Contents/MacOS/SwitchKeyboard"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
codesign --force --sign - --identifier local.safronov.SwitchKeyboard "$app_path"
codesign --verify --strict "$app_path"
printf 'Готово: %s\n' "$app_path"
