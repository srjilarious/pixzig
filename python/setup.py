"""Keeps the Python bindings' version pinned to the engine version.

The single source of truth is `.version` in the repo-root `build.zig.zon`.
`pyproject.toml` declares `version` as dynamic and this script fills it in
at build time by parsing that field out of the ZON file.

This means wheels must be built from an in-tree checkout (which is how
`python/build_wheels.py` already works) so that `build.zig.zon` is present
one directory above this file.
"""
import re
from pathlib import Path

from setuptools import setup

ZON_PATH = Path(__file__).resolve().parent.parent / "build.zig.zon"

match = re.search(r'^\s*\.version\s*=\s*"([^"]+)"', ZON_PATH.read_text(), re.MULTILINE)
if match is None:
    raise SystemExit(f"could not find .version in {ZON_PATH}")

setup(version=match.group(1))
