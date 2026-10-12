#!/usr/bin/env python3
"""Regenerates the screenshots in docs/assets/screenshots/.

Each shot runs one example under the engine's screenshot hook
(`EngineOptions.screenshotHook`, see src/pixzig/screenshot.zig): the
example plays for a fixed amount of game time, optionally fed a scripted
input sequence, then writes one frame to a PNG and exits. The frame is then
cropped and scaled here and saved for the docs. A montage tiles finished
shots into one image.

Examples run under SDL's offscreen video driver by default, so no windows
appear and the window manager can't resize them. Pass --visible to watch.

Usage:
    tools/doc_screenshots.py                # build, then capture everything
    tools/doc_screenshots.py actor tiles    # only the named shots
    tools/doc_screenshots.py --no-build     # reuse the current zig-out
    tools/doc_screenshots.py --keep-raw     # also keep the uncropped frames
    tools/doc_screenshots.py --list         # print the shots and exit

Needs Pillow.
"""

import argparse
import os
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parent.parent
OUT_DIR = REPO / "docs" / "assets" / "screenshots"
RAW_DIR = REPO / "zig-out" / "screenshots-raw"

# Spacing between scripted key taps. A tap holds for one tick, so this only
# has to be comfortably more than one update step (8.3ms at 120Hz).
TAP_GAP_MS = 25


@dataclass
class Shot:
    # Output file name, without the .png.
    name: str
    # Example executable, as built into zig-out/bin/<exe>/<exe>.
    exe: str
    # Which doc page uses it, for --list.
    doc: str
    # Game time to capture at, in ms.
    ms: int = 1000
    # Window size as (w, h). None keeps the example's own. An example with
    # `integer_fit` needs an exact multiple of its logical size here: the
    # offscreen driver's surface doesn't follow the window resize that
    # policy does at startup.
    size: tuple[int, int] | None = None
    # PIXZIG_SCREENSHOT_INPUT script, see `parseInput` in screenshot.zig.
    input: str | None = None
    # Crop box in captured pixels as (x, y, w, h), applied before scaling.
    crop: tuple[int, int, int, int] | None = None
    # Integer upscale with nearest-neighbour, for small pixel-art crops.
    scale: int = 1
    # Downscale (smoothly) to at most this width. Applied after `scale`.
    max_width: int | None = None


@dataclass
class Montage:
    # Output file name, without the .png.
    name: str
    doc: str
    # Names of shots to tile, row by row. They're captured first if needed.
    shots: list[str] = field(default_factory=list)
    cols: int = 2
    # Each tile is fitted into this size, keeping its aspect ratio.
    tile: tuple[int, int] = (400, 240)
    gap: int = 8
    background: tuple[int, int, int] = (24, 24, 32)


def taps(keys, start_ms=100, gap_ms=TAP_GAP_MS):
    """An input script tapping each key in turn, `gap_ms` apart."""
    return "; ".join(f"{start_ms + i * gap_ms} tap {k}" for i, k in enumerate(keys))


def a_star_input():
    # The cursor starts at (0, 0); start is (2, 2) and end (6, 8). Build a
    # wall down column 4 from row 0 to row 10, then move the end to the
    # far side of it so the path has to go around.
    keys = ["right"] * 4
    for _ in range(11):
        keys += ["x", "down"]
    keys += ["right"] * 6 + ["e"]
    return taps(keys)


def collision_input():
    # Sweep the cursor diagonally across the sprite grid; every sprite it
    # touches is removed from the grid and the world.
    return "; ".join(f"{100 + i * 10} move {4 + i * 2} {4 + i * 2}" for i in range(40))


SHOTS = [
    Shot("render", "render_ex", "rendering.md", ms=1000),
    Shot("actor", "actor_ex", "animation.md", ms=600, input=taps(["right"]),
         crop=(200, 120, 400, 240)),
    Shot("text", "text_rendering_ex", "text.md", ms=500, crop=(0, 0, 560, 400)),
    Shot("bitmap_text", "bitmap_text_rendering_ex", "text.md", ms=500,
         crop=(0, 150, 800, 110)),
    Shot("tiles", "tile_load_ex", "tile-rendering.md", ms=1500,
         input="100 down right; 900 up right"),
    Shot("collision", "collision_ex", "collision.md", ms=600, input=collision_input(),
         crop=(0, 0, 100, 100), scale=4),
    Shot("a_star", "a_star_path_ex", "collision.md", ms=1500, input=a_star_input()),
    Shot("flecs", "flecs_ex", "ecs.md", ms=2000),
    # Moves the actor in from the corner, then starts the Lua circle script.
    Shot("sequencer", "sequencer_ex", "sequences.md", ms=3300, size=(640, 480),
         input="100 tap right; 900 tap down; 1700 tap right; 2500 tap c",
         crop=(0, 0, 480, 360)),
    Shot("imgui", "imgui_ex", "ui.md", ms=500, size=(1200, 720), crop=(0, 0, 780, 500)),
    Shot("console", "console_ex", "scripting.md", ms=1500,
         input="100 text x = 6 * 7; 400 tap enter; 500 text con:log(\"x is \" .. x); 900 tap enter"),
    Shot("quad3d", "quad3d_ex", "low-level-rendering.md", ms=300),
    Shot("create_texture", "create_texture_ex", "assets.md", ms=200,
         crop=(32, 32, 256, 192), scale=2),
]

MONTAGES = [
    Montage("examples", "getting-started.md", ["render", "actor", "tiles", "imgui"]),
]


def capture(shot, raw_path, visible):
    env = dict(os.environ)
    env["PIXZIG_SCREENSHOT"] = str(raw_path)
    env["PIXZIG_SCREENSHOT_MS"] = str(shot.ms)
    if shot.size:
        env["PIXZIG_SCREENSHOT_SIZE"] = f"{shot.size[0]}x{shot.size[1]}"
    if shot.input:
        env["PIXZIG_SCREENSHOT_INPUT"] = shot.input
    if not visible:
        env["SDL_VIDEO_DRIVER"] = "offscreen"

    raw_path.unlink(missing_ok=True)
    exe = REPO / "zig-out" / "bin" / shot.exe / shot.exe
    # Examples find assets/ relative to the working directory.
    result = subprocess.run([exe], cwd=REPO, env=env, capture_output=True, text=True, timeout=120)
    if result.returncode != 0 or not raw_path.exists():
        sys.stderr.write(result.stderr[-4000:])
        raise RuntimeError(f"{shot.exe} exited {result.returncode} without a screenshot")


def process(shot, raw_path, out_path):
    img = Image.open(raw_path).convert("RGB")
    if shot.crop:
        x, y, w, h = shot.crop
        img = img.crop((x, y, x + w, y + h))
    if shot.scale != 1:
        img = img.resize((img.width * shot.scale, img.height * shot.scale), Image.NEAREST)
    if shot.max_width and img.width > shot.max_width:
        h = round(img.height * shot.max_width / img.width)
        img = img.resize((shot.max_width, h), Image.LANCZOS)
    img.save(out_path, optimize=True)
    return img.size


def compose(montage, out_path):
    tw, th = montage.tile
    rows = (len(montage.shots) + montage.cols - 1) // montage.cols
    gap = montage.gap
    sheet = Image.new(
        "RGB",
        (montage.cols * tw + (montage.cols + 1) * gap, rows * th + (rows + 1) * gap),
        montage.background,
    )
    for i, name in enumerate(montage.shots):
        img = Image.open(OUT_DIR / f"{name}.png").convert("RGB")
        img.thumbnail((tw, th), Image.LANCZOS)
        col, row = i % montage.cols, i // montage.cols
        # Centre each tile in its cell.
        x = gap + col * (tw + gap) + (tw - img.width) // 2
        y = gap + row * (th + gap) + (th - img.height) // 2
        sheet.paste(img, (x, y))
    sheet.save(out_path, optimize=True)
    return sheet.size


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("names", nargs="*", help="only capture these shots or montages")
    parser.add_argument("--no-build", action="store_true", help="skip `zig build`")
    parser.add_argument("--visible", action="store_true", help="show the windows instead of rendering offscreen")
    parser.add_argument("--keep-raw", action="store_true", help=f"keep uncropped captures in {RAW_DIR.relative_to(REPO)}")
    parser.add_argument("--list", action="store_true", help="list the shots and exit")
    args = parser.parse_args()

    if args.list:
        for s in SHOTS:
            print(f"{s.name:16} {s.exe:26} {s.doc}")
        for m in MONTAGES:
            print(f"{m.name:16} {'montage: ' + ' '.join(m.shots):26} {m.doc}")
        return 0

    shots_by_name = {s.name: s for s in SHOTS}
    montages_by_name = {m.name: m for m in MONTAGES}
    unknown = [n for n in args.names if n not in shots_by_name and n not in montages_by_name]
    if unknown:
        parser.error(f"unknown shot(s): {', '.join(unknown)}")

    if args.names:
        montages = [montages_by_name[n] for n in args.names if n in montages_by_name]
        wanted = [n for n in args.names if n in shots_by_name]
        # A montage only re-captures the shots it needs that are missing.
        for m in montages:
            wanted += [n for n in m.shots if n not in wanted and not (OUT_DIR / f"{n}.png").exists()]
        shots = [shots_by_name[n] for n in wanted]
    else:
        shots, montages = SHOTS, MONTAGES

    if not args.no_build:
        subprocess.run(["zig", "build"], cwd=REPO, check=True)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    failed = []
    for shot in shots:
        raw = RAW_DIR / f"{shot.name}.png"
        out = OUT_DIR / f"{shot.name}.png"
        try:
            capture(shot, raw, args.visible)
            w, h = process(shot, raw, out)
            print(f"{shot.name:16} {w}x{h}  {out.relative_to(REPO)}")
        except Exception as err:
            print(f"{shot.name:16} FAILED: {err}", file=sys.stderr)
            failed.append(shot.name)
        finally:
            if not args.keep_raw:
                raw.unlink(missing_ok=True)

    for m in montages:
        out = OUT_DIR / f"{m.name}.png"
        try:
            w, h = compose(m, out)
            print(f"{m.name:16} {w}x{h}  {out.relative_to(REPO)}")
        except Exception as err:
            print(f"{m.name:16} FAILED: {err}", file=sys.stderr)
            failed.append(m.name)

    if failed:
        print(f"{len(failed)} item(s) failed: {', '.join(failed)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
