#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p build dist
DERIVED_DATA="${WHISP_DERIVED_DATA:-$HOME/Library/Caches/Whisp/DerivedData}"
VERSION="${WHISP_VERSION:-1.0.0}"
BUILD_NUMBER="${WHISP_BUILD_NUMBER:-1}"
SIGNING_IDENTITY="${WHISP_SIGNING_IDENTITY:--}"
DEVELOPMENT_TEAM="${WHISP_DEVELOPMENT_TEAM:-}"
DMG="dist/Whisp-${VERSION}.dmg"
mkdir -p "$DERIVED_DATA"
xcodegen generate
xcodebuild \
  -project Whisp.xcodeproj \
  -scheme Whisp \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  build

APP="$DERIVED_DATA/Build/Products/Release/Whisp.app"
test -x "$APP/Contents/MacOS/Whisp"
codesign --verify --deep --strict "$APP"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/whisp-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Whisp.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG" "$DMG.sha256"
hdiutil create -volname "Whisp ${VERSION}" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG"
  codesign --verify --verbose "$DMG"
fi
shasum -a 256 "$DMG" > "$DMG.sha256"
echo "Готово: $DMG"
