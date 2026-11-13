"""Runs the bug board CLI's pure-logic tests (scripts/tests/bugs_logic.test.ts) under
`node --test` so they ride along with the existing guard suite. Skipped when Node is
missing or too old to run TypeScript directly (type stripping needs Node 23.6+ or 22.18+).

    python3 -m unittest discover -s scripts/tests -v
    node --test scripts/tests/bugs_logic.test.ts
"""
from __future__ import annotations

import re
import shutil
import subprocess
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def node_can_strip_types() -> bool:
    node = shutil.which("node")
    if not node:
        return False
    out = subprocess.run([node, "--version"], capture_output=True, text=True).stdout.strip()
    m = re.match(r"v(\d+)\.(\d+)", out)
    if not m:
        return False
    major, minor = int(m.group(1)), int(m.group(2))
    return major >= 24 or (major == 23 and minor >= 6) or (major == 22 and minor >= 18)


class BugsLogic(unittest.TestCase):
    @unittest.skipUnless(node_can_strip_types(), "needs Node 22.18+ / 23.6+ to run TypeScript directly")
    def test_logic_suite(self):
        result = subprocess.run(
            ["node", "--test", "scripts/tests/bugs_logic.test.ts"],
            cwd=REPO,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_cli_is_wired_to_the_admin_rpc_only(self):
        # The CLI must write through admin_set_bug_status (which enforces the reason,
        # original and version rules), never by updating bug_reports directly.
        src = (REPO / "scripts" / "bugs.ts").read_text()
        self.assertIn("admin_set_bug_status", src)
        self.assertNotRegex(src, r"\.from\(\"bug_reports\"\)\s*\.(update|insert|delete|upsert)")


if __name__ == "__main__":
    unittest.main()
