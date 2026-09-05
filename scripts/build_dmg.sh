#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p build dist
DERIVED_DATA="${WHISP_DERIVED_DATA:-$HOME/Library/Caches/Whisp/DerivedData}"
mkdir -p "$DERIVED_DATA"
xcodegen generate
xcodebuild \
  -project Whisp.xcodeproj \
  -scheme Whisp \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY=- \
  build

APP="$DERIVED_DATA/Build/Products/Release/Whisp.app"
test -d "$APP"
rm -f dist/Whisp.dmg
hdiutil create -volname Whisp -srcfolder "$APP" -ov -format UDZO dist/Whisp.dmg
echo "Готово: dist/Whisp.dmg"
