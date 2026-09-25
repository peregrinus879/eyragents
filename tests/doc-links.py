#!/usr/bin/env python3
"""Check every relative link and anchor in the repository's tracked Markdown files.

A relative link must resolve to a tracked file or directory inside this repository, and a
`#fragment` must match a heading in the target, using GitHub's anchor rules. A relative link that
leaves the repository fails, because it breaks when the repository is published; link to another
repository with its full URL instead. Image links count too. External URLs are not fetched, and only
fenced code blocks that start at the line's beginning are skipped.

Usage: tests/doc-links.py [REPOSITORY]   (default: this repository)
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent).resolve()
LINK = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
FENCE = re.compile(r"^(```|~~~)")


def tracked() -> list[str]:
    out = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-z"], capture_output=True, check=True).stdout
    return [p for p in out.decode().split("\0") if p]


def anchor(heading: str) -> str:
    """GitHub's heading anchor: lowercase, drop punctuation except hyphens, spaces to hyphens."""
    text = re.sub(r"`([^`]*)`", r"\1", heading.strip())
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"[^\w\- ]", "", text.lower())
    return text.replace(" ", "-")


def anchors(path: Path) -> set[str]:
    found, seen, fenced = set(), {}, False
    for line in path.read_text(encoding="utf-8").splitlines():
        if FENCE.match(line):
            fenced = not fenced
        if fenced:
            continue
        match = re.match(r"^#{1,6}\s+(.*?)\s*#*\s*$", line)
        if match:
            base = anchor(match.group(1))
            count = seen.get(base, 0)
            found.add(base if count == 0 else f"{base}-{count}")
            seen[base] = count + 1
    return found


def links(path: Path):
    fenced = False
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if FENCE.match(line):
            fenced = not fenced
        if fenced:
            continue
        for target in LINK.findall(re.sub(r"`[^`]*`", "", line)):
            yield number, target


files = tracked()
known = set(files) | {str(Path(f).parent) for f in files}
errors = []
for name in (f for f in files if f.endswith(".md")):
    source = ROOT / name
    for number, target in links(source):
        if re.match(r"^[a-z][a-z0-9+.-]*:", target):
            continue  # external URL or mailto
        base, _, fragment = target.partition("#")
        resolved = (source.parent / base).resolve() if base else source
        try:
            relative = str(resolved.relative_to(ROOT))
        except ValueError:
            errors.append(f"{name}:{number}: {target} leaves the repository; use a full URL")
            continue
        if base and relative not in known and relative != ".":
            errors.append(f"{name}:{number}: {target} does not resolve to a tracked path")
            continue
        if fragment and resolved.suffix == ".md" and fragment not in anchors(resolved):
            errors.append(f"{name}:{number}: {target} has no heading #{fragment}")

for error in errors:
    print(f"FAIL: {error}")
if errors:
    sys.exit(1)
print(f"ok: every relative link and anchor in {sum(f.endswith('.md') for f in files)} Markdown files resolves")
