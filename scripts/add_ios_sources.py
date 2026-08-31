#!/usr/bin/env python3
"""Register Swift sources with ios/PackWise.xcodeproj.

The project uses explicit file references rather than Xcode 16 synchronized
groups, so a new file is invisible to the build until it appears in four
places: PBXBuildFile, PBXFileReference, its PBXGroup's children, and the app
target's PBXSourcesBuildPhase. Adding those by hand across a multi-slice UI
pass is how files silently go missing from a target.

Usage:

    python3 scripts/add_ios_sources.py PackWise/DesignSystem/PackWiseTokens.swift ...
    python3 scripts/add_ios_sources.py --tests PackWiseTests/RenderHarness.swift

Paths are relative to `ios/`. `--tests` targets PackWiseTests instead of the
app. Groups are resolved by walking the existing
group tree and are created when a path introduces a new directory. Re-running
with a file that is already registered is a no-op, so the script is safe to
call repeatedly.
"""

from __future__ import annotations

import re
import secrets
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PBXPROJ = REPO / "ios" / "PackWise.xcodeproj" / "project.pbxproj"

# Each target's Sources phase is identified by a file only it compiles.
APP_ANCHOR = "PackWiseApp.swift in Sources"
TESTS_ANCHOR = "M1LoopTests.swift in Sources"


class ProjectError(RuntimeError):
    pass


def new_id(text: str) -> str:
    """A 24-hex-digit identifier that does not already appear in the file."""
    while True:
        candidate = secrets.token_hex(12).upper()
        if candidate not in text:
            return candidate


def section(text: str, name: str) -> tuple[int, int]:
    begin = text.index(f"/* Begin {name} section */")
    end = text.index(f"/* End {name} section */")
    return begin, end


def find_group_children(text: str, group_id: str) -> tuple[int, int]:
    """Byte range of a group's `children = (...)` list."""
    # Anchor on the newline: a bare "\t\t<id>" also matches inside the
    # four-tab child entry that lists this group in its parent, which silently
    # resolves to the wrong group's children.
    start = text.index(f"\n\t\t{group_id} /*")
    children = text.index("children = (", start)
    close = text.index("\t\t\t);", children)
    return children + len("children = (\n"), close


def group_named(text: str, parent_id: str, name: str) -> str | None:
    """The id of `name` among parent's children, if it is a group."""
    begin, end = find_group_children(text, parent_id)
    for child_id, child_name in re.findall(
        r"\t\t\t\t([A-F0-9]{24}) /\* (.+?) \*/,", text[begin:end]
    ):
        if child_name != name:
            continue
        if re.search(rf"\t\t{child_id} /\* {re.escape(name)} \*/ = \{{\n\t\t\tisa = PBXGroup;", text):
            return child_id
    return None


def root_group(text: str, name: str) -> str:
    """A top-level source group — parent of App/, Domain/, Features/, ..."""
    match = re.search(
        rf"\n\t\t([A-F0-9]{{24}}) /\* {re.escape(name)} \*/ = \{{\n\t\t\tisa = PBXGroup;", text
    )
    if not match:
        raise ProjectError(f"could not locate the {name} group")
    return match.group(1)


def insert_group(text: str, parent_id: str, name: str) -> tuple[str, str]:
    """Create an empty PBXGroup under parent and return (text, new id)."""
    group_id = new_id(text)
    block = (
        f"\t\t{group_id} /* {name} */ = {{\n"
        f"\t\t\tisa = PBXGroup;\n"
        f"\t\t\tchildren = (\n"
        f"\t\t\t);\n"
        f"\t\t\tpath = {name};\n"
        f'\t\t\tsourceTree = "<group>";\n'
        f"\t\t}};\n"
    )
    begin, _ = section(text, "PBXGroup")
    at = text.index("\n", begin) + 1
    text = text[:at] + block + text[at:]

    children_start, _ = find_group_children(text, parent_id)
    entry = f"\t\t\t\t{group_id} /* {name} */,\n"
    text = text[:children_start] + entry + text[children_start:]
    return text, group_id


def resolve_group(text: str, root: str, directories: list[str]) -> tuple[str, str]:
    """Walk (creating as needed) from a root group down to a directory."""
    current = root_group(text, root)
    for directory in directories:
        existing = group_named(text, current, directory)
        if existing is None:
            text, existing = insert_group(text, current, directory)
        current = existing
    return text, current


def already_registered(text: str, filename: str) -> bool:
    return f"/* {filename} */ = {{isa = PBXFileReference" in text


def add_source(text: str, relative_path: str, tests: bool) -> tuple[str, bool]:
    parts = Path(relative_path).parts
    root = "PackWiseTests" if tests else "PackWise"
    if parts[0] != root:
        raise ProjectError(f"expected a path under {root}/, got {relative_path}")
    filename = parts[-1]
    if not filename.endswith(".swift"):
        raise ProjectError(f"not a Swift source: {relative_path}")
    if not (REPO / "ios" / relative_path).exists():
        raise ProjectError(f"file does not exist on disk: {relative_path}")
    if already_registered(text, filename):
        return text, False

    file_id = new_id(text)
    build_id = new_id(text + file_id)

    reference = (
        f"\t\t{file_id} /* {filename} */ = {{isa = PBXFileReference; "
        f"lastKnownFileType = sourcecode.swift; path = {filename}; "
        f'sourceTree = "<group>"; }};\n'
    )
    begin, _ = section(text, "PBXFileReference")
    at = text.index("\n", begin) + 1
    text = text[:at] + reference + text[at:]

    build_file = (
        f"\t\t{build_id} /* {filename} in Sources */ = {{isa = PBXBuildFile; "
        f"fileRef = {file_id} /* {filename} */; }};\n"
    )
    begin, _ = section(text, "PBXBuildFile")
    at = text.index("\n", begin) + 1
    text = text[:at] + build_file + text[at:]

    text, group_id = resolve_group(text, root, list(parts[1:-1]))
    children_start, _ = find_group_children(text, group_id)
    text = (
        text[:children_start]
        + f"\t\t\t\t{file_id} /* {filename} */,\n"
        + text[children_start:]
    )

    # The anchor also appears in PBXBuildFile, so search within the phase
    # section rather than from the top of the file.
    phase_begin, phase_end = section(text, "PBXSourcesBuildPhase")
    anchor_text = TESTS_ANCHOR if tests else APP_ANCHOR
    anchor = text.index(anchor_text, phase_begin, phase_end)
    files_start = text.rindex("files = (\n", phase_begin, anchor) + len("files = (\n")
    text = (
        text[:files_start]
        + f"\t\t\t\t{build_id} /* {filename} in Sources */,\n"
        + text[files_start:]
    )
    return text, True


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    tests = "--tests" in argv
    argv = [argument for argument in argv if argument != "--tests"]

    text = PBXPROJ.read_text()
    added = []
    skipped = []
    for relative_path in argv:
        text, did_add = add_source(text, relative_path, tests)
        (added if did_add else skipped).append(relative_path)

    PBXPROJ.write_text(text)

    for path in added:
        print(f"added    {path}")
    for path in skipped:
        print(f"already  {path}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except ProjectError as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
