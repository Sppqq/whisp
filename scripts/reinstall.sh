#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != Darwin ]]; then
  echo "Whisp — приложение macOS. Запустите этот скрипт на Mac с Xcode." >&2
  exit 1
fi
if [[ "$(id -u)" == 0 ]]; then
  echo "Не запускайте весь скрипт через sudo: пароль будет запрошен только для /Applications." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
source "$ROOT/scripts/select_xcode.sh"
whisp_select_xcode
if ! command -v xcodegen >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "Не найден XcodeGen. Установите Homebrew, затем выполните: brew install xcodegen" >&2
    exit 1
  fi
  brew install xcodegen
fi

mkdir -p build
# Atomic lock prevents two installers from replacing the app at the same time.
LOCK="$ROOT/build/reinstall.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "Другой установщик уже работает. Если он аварийно завершился, удалите пустую папку: $LOCK" >&2
  exit 1
fi
STAGE=""
OLD_MOVED=0
INSTALLED=0
NEEDS_SUDO=0
TARGET="/Applications/Whisp.app"
privileged() {
  if [[ "$NEEDS_SUDO" == 1 ]]; then sudo "$@"; else "$@"; fi
}
cleanup() {
  result=$?
  if [[ "$OLD_MOVED" == 1 && "$INSTALLED" == 0 && ! -e "$TARGET" && -d "$STAGE/Previous.app" ]]; then
    if privileged mv "$STAGE/Previous.app" "$TARGET"; then
      echo "Восстановлена предыдущая версия Whisp." >&2
    else
      echo "Не удалось откатить замену. Предыдущая версия: $STAGE/Previous.app" >&2
    fi
  fi
  rmdir "$LOCK" 2>/dev/null || true
  if [[ -n "$STAGE" ]]; then privileged rmdir "$STAGE" 2>/dev/null || true; fi
  if [[ "$result" != 0 ]]; then echo "Установка прервана. Записи и настройки не изменялись." >&2; fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$ROOT/build/reinstall-$STAMP.log"
ARCH="$(uname -m)"
DERIVED_DATA="${WHISP_DERIVED_DATA:-$HOME/Library/Caches/Whisp/DerivedData}"
mkdir -p "$DERIVED_DATA"
ARGS=(-project Whisp.xcodeproj -scheme Whisp -destination "platform=macOS,arch=$ARCH"
      -derivedDataPath "$DERIVED_DATA" "ARCHS=$ARCH" ONLY_ACTIVE_ARCH=YES
      CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)

echo "1/4 Генерация проекта и тесты. Лог: $LOG"
xcodegen generate
xcodebuild "${ARGS[@]}" -configuration Debug test 2>&1 | tee "$LOG"
echo "2/4 Release-сборка"
xcodebuild "${ARGS[@]}" -configuration Release build 2>&1 | tee -a "$LOG"
APP="$DERIVED_DATA/Build/Products/Release/Whisp.app"
[[ -x "$APP/Contents/MacOS/Whisp" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == app.whisp.lectures ]]
xattr -cr "$APP" 2>/dev/null || true
codesign --verify --deep --strict "$APP"

echo "3/4 Закрытие Whisp и установка в /Applications"
# Never force-kill a recording. A refused/timed-out quit aborts the installation.
if pgrep -x Whisp >/dev/null; then
  osascript -e 'tell application id "app.whisp.lectures" to quit'
  for ((i=0; i<30; i++)); do
    if ! pgrep -x Whisp >/dev/null; then break; fi
    sleep 1
  done
  if pgrep -x Whisp >/dev/null; then
    echo "Whisp ещё работает. Завершите запись и закройте приложение перед переустановкой." >&2
    exit 1
  fi
fi
[[ -d /Applications && ! -L /Applications ]]
if [[ ! -w /Applications || ( -e "$TARGET" && ! -w "$TARGET" ) ]]; then
  sudo -v
  NEEDS_SUDO=1
fi
if [[ -L "$TARGET" || ( -e "$TARGET" && ! -d "$TARGET" ) ]]; then
  echo "Отказ: $TARGET — ссылка или не папка приложения." >&2
  exit 1
fi
STAGE="$(privileged mktemp -d /Applications/.Whisp-install.XXXXXX)"
[[ "$STAGE" == /Applications/.Whisp-install.* && -d "$STAGE" && ! -L "$STAGE" ]]
privileged ditto "$APP" "$STAGE/New.app"
privileged xattr -cr "$STAGE/New.app" 2>/dev/null || true
privileged codesign --verify --deep --strict "$STAGE/New.app"
if [[ -d "$TARGET" ]]; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$TARGET/Contents/Info.plist")" == app.whisp.lectures ]]
  privileged mv "$TARGET" "$STAGE/Previous.app"
  OLD_MOVED=1
fi
privileged mv "$STAGE/New.app" "$TARGET"
INSTALLED=1
if [[ "$OLD_MOVED" == 1 ]]; then
  echo "Предыдущая версия сохранена: $STAGE/Previous.app"
fi
echo "4/4 Запуск установленной версии"
open "$TARGET"
echo "Готово: $TARGET. База лекций, аудио, настройки и Keychain сохранены."
echo "При ad-hoc подписи macOS может повторно запросить доступ к микрофону/экрану/Keychain."
