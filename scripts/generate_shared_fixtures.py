#!/usr/bin/env python3
"""Deprecated authoring entrypoint.

Catalog and rules now live as versioned JSON under shared/.
Use scripts/validate_shared.py after edits.
The previous generator remains in git history if you need to rebuild from scratch.
"""

from pathlib import Path
import sys

print(
    "shared/ JSON is the source of truth.\n"
    f"Validate with: python3 {Path(__file__).resolve().parents[1] / 'scripts' / 'validate_shared.py'}",
    file=sys.stderr,
)
sys.exit(0)
