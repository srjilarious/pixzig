#!/usr/bin/env python3
"""Builds pixzig's Linux and Windows wheels.

Each wheel bundles the platform's `libpixzig_ffi` build (from `zig build
python-ffi`) alongside the pure-Python `pixzig` package. Since the package
is ctypes-based rather than a compiled Python extension, it isn't tied to a
specific CPython version or ABI -- only to the OS/architecture the native
library was built for -- so each wheel is tagged `py3-none-<platform>`
(forced via a `--plat-name` build option) rather than the `cp3xx-cp3xx-*`
tag a real C extension would get.

The Linux build targets whatever glibc is on this machine (see the
`python-ffi` build step in build.zig), so the resulting wheel only installs
on comparably recent Linux distros. The Windows build cross-compiles
cleanly from Linux via Zig's bundled mingw toolchain.

Usage (from anywhere):
    python3 python/build_wheels.py
"""
import re
import shutil
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PYTHON_DIR = REPO_ROOT / "python"
PACKAGE_DIR = PYTHON_DIR / "pixzig"
DIST_DIR = PYTHON_DIR / "dist"

# (zig -Dtarget value, or None for a native build; the file zig produces in
# zig-out/python/; the wheel's platform tag; the name to stage it under in
# pixzig/, matching what pixzig/_native.py looks for on that OS)
TARGETS = [
    (None, "libpixzig_ffi.so", "linux_x86_64", "libpixzig_ffi.so"),
    ("x86_64-windows-gnu", "pixzig_ffi.dll", "win_amd64", "pixzig_ffi.dll"),
]


def write_version_file() -> str:
    """Writes python/VERSION from build.zig.zon's .version field -- the
    engine's own version is the single source of truth for the wheel
    version too (python/pyproject.toml reads VERSION via `dynamic =
    ["version"]`). Same extraction the CI workflow does in shell.
    """
    zon_text = (REPO_ROOT / "build.zig.zon").read_text()
    match = re.search(r'\.version\s*=\s*"([^"]+)"', zon_text)
    if not match:
        raise SystemExit("could not find .version in build.zig.zon")
    version = match.group(1)
    (PYTHON_DIR / "VERSION").write_text(version)
    return version


def run(cmd: list[str]) -> None:
    print(f"$ {' '.join(cmd)}")
    subprocess.run(cmd, check=True, cwd=REPO_ROOT)


def build_wheel_for(zig_target: str | None, built_name: str, plat_tag: str, package_name: str) -> None:
    zig_cmd = ["zig", "build", "python-ffi", "-Doptimize=ReleaseFast"]
    if zig_target:
        zig_cmd.append(f"-Dtarget={zig_target}")
    run(zig_cmd)

    built_path = REPO_ROOT / "zig-out" / "python" / built_name
    if not built_path.exists():
        raise SystemExit(f"expected build output at {built_path}, not found")

    # setuptools' build/ cache doesn't drop files removed from the source
    # tree between runs, so a stale binary from the previous platform's
    # build would otherwise get bundled into this one too.
    shutil.rmtree(PYTHON_DIR / "build", ignore_errors=True)

    staged_lib = PACKAGE_DIR / package_name
    shutil.copy2(built_path, staged_lib)
    try:
        run([
            "uv", "build", "--wheel",
            "--out-dir", str(DIST_DIR),
            "--config-setting=--build-option=--plat-name",
            f"--config-setting=--build-option={plat_tag}",
            str(PYTHON_DIR),
        ])
    finally:
        staged_lib.unlink(missing_ok=True)


def main() -> None:
    DIST_DIR.mkdir(exist_ok=True)
    version = write_version_file()
    print(f"Building pixzig {version}")
    for zig_target, built_name, plat_tag, package_name in TARGETS:
        build_wheel_for(zig_target, built_name, plat_tag, package_name)

    print("\nBuilt wheels:")
    for whl in sorted(DIST_DIR.glob("*.whl")):
        print(f"  {whl}")


if __name__ == "__main__":
    main()
