#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/ModuleCache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$PWD/.build/ModuleCache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

swift build -c release -debug-info-format none --disable-sandbox --cache-path "$PWD/.build/PackageCache"

APP="build/UmamiBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$(swift build -c release -debug-info-format none --disable-sandbox --cache-path "$PWD/.build/PackageCache" --show-bin-path)/UmamiBar" "$APP/Contents/MacOS/UmamiBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/en.lproj Resources/zh-Hans.lproj "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Signing preference: real Developer ID (release) > local dev cert (stable
# cdhash so keychain grants survive rebuilds) > ad-hoc (re-prompts every build).
DEV_KEYCHAIN="$PWD/.dev-cert/dev.keychain-db"
DEV_ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
if [[ -n "$DEV_ID" ]]; then
    codesign --force --deep --sign "$DEV_ID" --options runtime --timestamp "$APP"
elif security find-certificate -c "UmamiBar Dev" "$DEV_KEYCHAIN" >/dev/null 2>&1; then
    codesign --force --deep --sign "UmamiBar Dev" --keychain "$DEV_KEYCHAIN" "$APP"
else
    codesign --force --deep --sign - "$APP"
fi

codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
echo "Built $APP"
