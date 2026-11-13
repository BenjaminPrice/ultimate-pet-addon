#!/usr/bin/env python3
"""Builds a shareable addon zip: .release/UltimatePet-<version>.zip

The zip holds one UltimatePet/ folder with only what the game loads (the TOC, the files it lists,
the embedded libraries) plus LICENSE and README.md. Tests, tools and CI files are left out.
Files come from the working tree, but only ones tracked by git.

Usage (from the repository root): python3 -I tools/package.py
"""
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDON = "UltimatePet"
TOC = ROOT / f"{ADDON}.toc"
EXTRA = {"LICENSE", "README.md", f"{ADDON}.toc"}


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True,
                          text=True).stdout


def toc_files(text):
    """Files the TOC loads, as repo-relative paths with forward slashes."""
    files = []
    for line in text.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return files


def main():
    text = TOC.read_text(encoding="utf-8")
    match = re.search(r"^## Version:\s*(\S+)", text, re.M)
    version = match.group(1) if match else "dev"
    tracked = set(git("ls-files").split("\n")) - {""}

    wanted = set(EXTRA)
    for path in toc_files(text):
        if path not in tracked:
            sys.exit(f"TOC lists {path}, which isn't tracked by git.")
        wanted.add(path)
    # Libraries are loaded through embeds.xml, so take the whole folder.
    wanted |= {p for p in tracked if p.startswith("Libs/")}

    dirty = git("status", "--porcelain", "--", *sorted(wanted)).strip()
    if dirty:
        print("Warning: uncommitted changes are included:\n" + dirty, file=sys.stderr)

    out = ROOT / ".release" / f"{ADDON}-{version}.zip"
    out.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(wanted):
            zf.write(ROOT / path, f"{ADDON}/{path}")
    print(f"{out.relative_to(ROOT)}: {len(wanted)} files, commit {git('rev-parse', '--short', 'HEAD').strip()}")


if __name__ == "__main__":
    main()
