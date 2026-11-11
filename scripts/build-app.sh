#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

dist_dir="$PWD/dist"
signing_identity="${SWITCHKEYBOARD_SIGNING_IDENTITY:-}"
case "${1:-}" in
    "")
        if [[ -z "$signing_identity" ]]; then
            identities="$(/usr/bin/security find-identity -v -p codesigning)"
            signing_identity="$(/usr/bin/awk '/"Apple Development: / {print $2}' <<< "$identities")"
        fi
        if [[ -z "$signing_identity" || "$signing_identity" == "-" || "$signing_identity" == *$'\n'* ]]; then
            printf '%s\n' 'Нужен один сертификат Apple Development в связке ключей. Если их несколько, задайте SWITCHKEYBOARD_SIGNING_IDENTITY.' >&2
            exit 1
        fi
        ;;
    --adhoc)
        signing_identity=-
        dist_dir="$dist_dir/adhoc"
        ;;
    *)
        printf '%s\n' 'Использование: bash scripts/build-app.sh [--adhoc]' >&2
        exit 2
        ;;
esac

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
swift build -c release -debug-info-format none --disable-sandbox --cache-path "$PWD/.build/swiftpm-cache"
binary_dir="$(swift build -c release --show-bin-path --disable-sandbox --cache-path "$PWD/.build/swiftpm-cache")"
mkdir -p "$dist_dir"
staging_dir="$(mktemp -d "$dist_dir/.build.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
candidate="$staging_dir/SwitchKeyboard.app"
mkdir -p "$candidate/Contents/MacOS"
cp "$binary_dir/SwitchKeyboard" "$candidate/Contents/MacOS/SwitchKeyboard"
cp Resources/Info.plist "$candidate/Contents/Info.plist"
/usr/bin/codesign --force --sign "$signing_identity" "$candidate"
/usr/bin/codesign --verify --strict "$candidate"

installed="/Applications/SwitchKeyboard.app"
if [[ "$signing_identity" != "-" && -d "$installed" ]]; then
    installed_requirement="$(/usr/bin/codesign --display -r- "$installed" 2>&1 | sed -En 's/^(# )?designated => //p')"
    # Для перехода с ad hoc старая подпись привязана к хешу и не может сохраниться.
    if [[ "$installed_requirement" != cdhash\ * ]] &&
       { [[ -z "$installed_requirement" ]] ||
         ! /usr/bin/codesign --verify --strict -R="$installed_requirement" "$candidate"; }; then
        printf '%s\n' 'Подпись новой сборки несовместима с установленной. Выберите прежнего подписанта и тип сертификата.' >&2
        exit 1
    fi
fi

app_path="$dist_dir/SwitchKeyboard.app"
/usr/bin/ditto "$candidate" "$app_path"
/usr/bin/codesign --verify --strict "$app_path"
printf 'Готово: %s\n' "$app_path"
