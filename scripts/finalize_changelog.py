#!/usr/bin/env python3
"""Move the current Unreleased changelog section into a versioned section."""
from __future__ import annotations

import argparse
import re
from datetime import date
from pathlib import Path

SECTION_RE = re.compile(r"^## \[([^\]]+)\](?:\s+-\s+[^\n]+)?\s*$\n(.*?)(?=^## \[|\Z)", re.MULTILINE | re.DOTALL)


def finalize_changelog(markdown: str, version: str, release_date: str | None = None) -> str:
    version = version.removeprefix("v")
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", version):
        raise ValueError(f"Некорректная версия: {version}")
    matches = list(SECTION_RE.finditer(markdown))
    unreleased = next((m for m in matches if m.group(1) == "Unreleased"), None)
    if unreleased is None:
        raise ValueError("В CHANGELOG.md нет секции [Unreleased]")
    body = unreleased.group(2).strip()
    if not body:
        return markdown
    if any(m.group(1) == version for m in matches):
        raise ValueError(f"Секция [{version}] уже существует")
    stamp = release_date or date.today().isoformat()
    section = f"## [{version}] - {stamp}\n\n{body}\n\n"
    replacement = "## [Unreleased]\n\n" + section
    return markdown[:unreleased.start()] + replacement + markdown[unreleased.end():]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("version")
    parser.add_argument("--date", dest="release_date")
    parser.add_argument("--changelog", default="CHANGELOG.md")
    args = parser.parse_args()
    path = Path(args.changelog)
    current = path.read_text(encoding="utf-8")
    updated = finalize_changelog(current, args.version, args.release_date)
    if updated != current:
        path.write_text(updated, encoding="utf-8")


if __name__ == "__main__":
    main()
