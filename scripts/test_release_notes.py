#!/usr/bin/env python3

import unittest
import sys
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent))
import next_version
import release_notes


CHANGELOG = """# История

## [Unreleased]

### Добавлено

- Новая функция.

## [0.1.2-alpha.1] - 2026-01-02

### Изменено

- Первая альфа.

## [0.1.2-rc.1] - 2026-01-03

### Исправлено

- Кандидат.

## [0.1.1] - 2026-01-01

### Добавлено

- Стабильный релиз.
"""


class ReleaseNotesTests(unittest.TestCase):
    def test_extract_release(self):
        self.assertIn("Первая альфа", release_notes.extract_release(CHANGELOG, "0.1.2-alpha.1"))

    def test_aggregate_since_includes_unreleased_and_prereleases(self):
        result = release_notes.aggregate_since(CHANGELOG, "0.1.1")
        self.assertIn("Новая функция", result)
        self.assertIn("Первая альфа", result)
        self.assertIn("Кандидат", result)
        self.assertNotIn("Стабильный релиз", result)

    @patch("next_version.tags", return_value=["v0.1.1", "v0.1.2-alpha.1"])
    def test_next_alpha_increments_existing_alpha(self, _tags):
        self.assertEqual(next_version.next_version("alpha", "patch"), "0.1.2-alpha.2")


if __name__ == "__main__":
    unittest.main()
