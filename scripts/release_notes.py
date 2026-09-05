#!/usr/bin/env python3
"""Extract one version section from Keep a Changelog Markdown."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


def extract_release(markdown: str, version: str) -> str:
    pattern = re.compile(
        rf"^## \[{re.escape(version)}\](?:\s+-\s+[^\n]+)?\s*$\n(.*?)(?=^## \[|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(markdown)
    if not match:
        raise ValueError(f"В CHANGELOG.md нет секции ## [{version}]")
    notes = match.group(1).strip()
    if not notes:
        raise ValueError(f"Секция {version} пуста")
    return notes + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("version")
    parser.add_argument("--changelog", default="CHANGELOG.md")
    parser.add_argument("--output")
    args = parser.parse_args()

    version = args.version.removeprefix("v")
    notes = extract_release(Path(args.changelog).read_text(encoding="utf-8"), version)
    if args.output:
        Path(args.output).write_text(notes, encoding="utf-8")
    else:
        print(notes, end="")


if __name__ == "__main__":
    main()
