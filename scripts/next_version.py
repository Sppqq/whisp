#!/usr/bin/env python3
"""Calculate the next Whisp prerelease or stable SemVer from Git tags."""

from __future__ import annotations

import argparse
import re
import subprocess


TAG_RE = re.compile(r"^v(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$")


def tags() -> list[str]:
    result = subprocess.run(
        ["git", "tag", "--list", "v*"], check=True, text=True, capture_output=True
    )
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def parse(tag: str) -> tuple[int, int, int, str | None] | None:
    match = TAG_RE.fullmatch(tag.strip())
    if not match:
        return None
    major, minor, patch = (int(match.group(index)) for index in range(1, 4))
    return major, minor, patch, match.group(4)


def stable_tags() -> list[tuple[int, int, int, str]]:
    return [(*parsed[:3], tag) for tag in tags() if (parsed := parse(tag)) and parsed[3] is None]


def next_version(channel: str, bump: str) -> str:
    stable = stable_tags()
    if stable:
        major, minor, patch, _ = max(stable)
    else:
        major, minor, patch = 0, 1, 0

    if channel == "stable":
        if bump == "major":
            major, minor, patch = major + 1, 0, 0
        elif bump == "minor":
            minor, patch = minor + 1, 0
        else:
            patch += 1
        return f"{major}.{minor}.{patch}"

    # Prereleases are based on the next stable version. Keep the same base
    # while incrementing alpha/rc numbers on repeated workflow runs.
    if bump == "major":
        major, minor, patch = major + 1, 0, 0
    elif bump == "minor":
        minor, patch = minor + 1, 0
    else:
        patch += 1
    base = f"{major}.{minor}.{patch}"
    numbers = [
        parsed[3]
        for tag in tags()
        if (parsed := parse(tag)) and parsed[:3] == (major, minor, patch) and parsed[3]
    ]
    prefix = f"{channel}."
    indexes = [
        int(value.removeprefix(prefix))
        for value in numbers
        if value.startswith(prefix) and value.removeprefix(prefix).isdigit()
    ]
    return f"{base}-{channel}.{max(indexes, default=0) + 1}"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--channel", choices=["alpha", "rc", "stable"], required=True)
    parser.add_argument("--bump", choices=["patch", "minor", "major"], default="patch")
    args = parser.parse_args()
    print(next_version(args.channel, args.bump))


if __name__ == "__main__":
    main()
