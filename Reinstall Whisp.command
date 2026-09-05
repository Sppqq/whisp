#!/bin/bash
cd "$(dirname "$0")" || exit 1
/bin/bash scripts/reinstall.sh
result=$?
echo
if [[ "$result" != 0 ]]; then echo "Не удалось переустановить Whisp. Ошибка описана выше."; fi
read -r -p "Нажмите Enter, чтобы закрыть окно… " _
exit "$result"
