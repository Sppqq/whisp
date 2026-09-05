#!/bin/bash
# Sourced by reinstall.sh. Select Xcode for this process only, never system-wide.
whisp_use_xcode() {
  local candidate="$1"
  if [[ "$candidate" == *.app ]]; then candidate="$candidate/Contents/Developer"; fi
  [[ -x "$candidate/usr/bin/xcodebuild" ]] || return 1
  if ! DEVELOPER_DIR="$candidate" xcrun --find xcodebuild >/dev/null 2>&1 \
     || ! DEVELOPER_DIR="$candidate" xcrun --find swiftc >/dev/null 2>&1 \
     || ! DEVELOPER_DIR="$candidate" xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1; then
    return 1
  fi
  export DEVELOPER_DIR="$candidate"
  echo "Xcode для сборки: $DEVELOPER_DIR"
}

whisp_select_xcode() {
  local selected candidate
  # An explicit override (including beta/custom installs) takes precedence.
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    if whisp_use_xcode "$DEVELOPER_DIR"; then return 0; fi
    echo "Указанный DEVELOPER_DIR не содержит готовый Xcode: $DEVELOPER_DIR" >&2
    echo "Проверьте путь, завершите установку компонентов Xcode или выполните unset DEVELOPER_DIR." >&2
    DEVELOPER_DIR="$DEVELOPER_DIR" xcrun --find swiftc >&2 || true
    DEVELOPER_DIR="$DEVELOPER_DIR" xcrun --sdk macosx --show-sdk-path >&2 || true
    return 1
  fi

  selected="$(xcode-select --print-path 2>/dev/null || true)"
  if [[ -n "$selected" ]] && whisp_use_xcode "$selected"; then return 0; fi

  # An open Xcode does not change xcode-select: it may still point at CLT.
  for candidate in /Applications/Xcode.app /Applications/Xcode-beta.app \
                   /Applications/Xcode*.app "${HOME}/Applications/"Xcode*.app \
                   "${HOME}/Downloads/"Xcode*.app; do
    if whisp_use_xcode "$candidate"; then return 0; fi
  done
  # Also handle renamed apps and nonstandard locations indexed by Spotlight.
  if command -v mdfind >/dev/null 2>&1; then
    while IFS= read -r candidate; do
      if whisp_use_xcode "$candidate"; then return 0; fi
    done < <(mdfind 'kMDItemCFBundleIdentifier == "com.apple.dt.Xcode"' 2>/dev/null || true)
  fi

  echo "Не удалось найти Xcode с инструментами Swift и macOS SDK." >&2
  echo "Активный путь xcode-select: ${selected:-не задан}" >&2
  echo 'Если Xcode уже установлен, укажите его путь (переустанавливать его не нужно):' >&2
  echo 'DEVELOPER_DIR="/путь/к/Xcode.app/Contents/Developer" bash scripts/reinstall.sh' >&2
  echo "Также проверьте Xcode → Settings → Locations → Command Line Tools и завершите установку компонентов." >&2
  return 1
}
