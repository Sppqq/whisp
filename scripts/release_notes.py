#!/usr/bin/env python3
"""Extract one release section or aggregate changes since a stable version."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


SECTION_RE = re.compile(
    r"^## \[([^\]]+)\](?:\s+-\s+[^\n]+)?\s*$\n(.*?)(?=^## \[|\Z)",
    re.MULTILINE | re.DOTALL,
)


def extract_release(markdown: str, version: str) -> str:
    match = next((item for item in SECTION_RE.finditer(markdown) if item.group(1) == version), None)
    if not match:
        raise ValueError(f"В CHANGELOG.md нет секции ## [{version}]")
    notes = match.group(2).strip()
    if not notes:
        raise ValueError(f"Секция {version} пуста")
    return notes + "\n"


def _version_key(value: str) -> tuple[int, int, int, tuple]:
    """Return a SemVer-ish key suitable for ordering changelog headings."""
    clean = value.removeprefix("v")
    numeric, _, prerelease = clean.partition("-")
    numbers = numeric.split(".")
    if len(numbers) != 3 or not all(part.isdigit() for part in numbers):
        raise ValueError(f"Некорректная версия в CHANGELOG.md: {value}")
    # Stable releases sort after prereleases of the same numeric version.
    pre_key = (1,) if not prerelease else (
        0,
        *(
            (0, int(identifier)) if identifier.isdigit() else (1, identifier)
            for identifier in prerelease.split(".")
        ),
    )
    return (int(numbers[0]), int(numbers[1]), int(numbers[2]), pre_key)


def aggregate_since(markdown: str, previous_stable: str) -> str:
    """Concatenate Unreleased and all version sections newer than a stable tag."""
    previous_key = _version_key(previous_stable)
    chunks: list[str] = []
    for match in SECTION_RE.finditer(markdown):
        version = match.group(1)
        body = match.group(2).strip()
        if not body:
            continue
        if version == "Unreleased" or _version_key(version) > previous_key:
            chunks.append(f"## [{version}]\n\n{body}")
    if not chunks:
        raise ValueError(f"После версии {previous_stable} нет изменений в CHANGELOG.md")
    return "\n\n".join(chunks) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("version", nargs="?")
    parser.add_argument("--aggregate-since", help="Собрать Unreleased и версии новее указанной")
    parser.add_argument("--changelog", default="CHANGELOG.md")
    parser.add_argument("--output")
    args = parser.parse_args()

    markdown = Path(args.changelog).read_text(encoding="utf-8")
    if args.aggregate_since:
        notes = aggregate_since(markdown, args.aggregate_since.removeprefix("v"))
    else:
        if not args.version:
            parser.error("укажите версию или --aggregate-since")
        version = args.version.removeprefix("v")
        notes = extract_release(markdown, version)
    if args.output:
        Path(args.output).write_text(notes, encoding="utf-8")
    else:
        print(notes, end="")


if __name__ == "__main__":
    main()
