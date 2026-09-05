#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "Установите Homebrew: https://brew.sh"
    exit 1
  fi
  brew install xcodegen
fi

xcodegen generate
open Whisp.xcodeproj
