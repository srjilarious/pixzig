#!/usr/bin/env python3
"""Paints assets/hopper.png: the level tiles and every sprite in one sheet.

    python3 tools/gen_art.py

The sheet is 8 columns of 16x16 cells. Tiles are drawn in code; the sprites
are the ASCII pictures below, one character per pixel (see PALETTE), so you
can redraw them in a text editor. Left-facing frames are mirrored from the
right-facing ones.

Cell indexes are what the game and level1.tmx use, so keep them where they
are (or update src/sprites.zig, python/hopper.py and the map):

     0 grass   1 dirt    2 brick   3 crate   4 bush    5 cloud   6 pole   7 flag
     8-11  frog right: idle, run 1, run 2, jump
    12-15  frog left:  idle, run 1, run 2, jump
    16-17  beetle walking   18 beetle squashed
    19-21  coin spinning
"""

import random
import sys
from pathlib import Path

from PIL import Image

CELL = 16
COLUMNS = 8
ROWS = 3

PALETTE = {
    ".": None,
    "k": (24, 22, 34),  # outline
    "g": (110, 205, 80),  # frog
    "G": (60, 150, 60),  # frog shade
    "y": (232, 226, 150),  # frog belly
    "w": (250, 250, 250),
    "b": (20, 20, 20),  # pupil
    "r": (200, 60, 60),  # mouth
    "p": (150, 85, 180),  # beetle shell
    "P": (95, 50, 125),  # beetle shade
    "o": (240, 160, 60),  # beetle legs
    "c": (250, 205, 60),  # coin
    "C": (200, 140, 30),  # coin shade
    "h": (255, 245, 180),  # coin shine
}

FROG_IDLE = """
................
................
................
.........kkk.kkk
........kwwwkwwk
........kwbwkwbk
......kkkgggggGk
....kkggggggggGk
...kggggggggrrrk
...kgggyyyyyggk.
..kggyyyyyyyGGk.
..kgGyyyyyyGGk..
..kgGGyyyyGGk...
..kkgGGGGGGkk...
.kggkkkkkkkggk..
.kkkk......kkkk.
"""

FROG_RUN1 = """
................
................
.........kkk.kkk
........kwwwkwwk
........kwbwkwbk
......kkkgggggGk
....kkggggggggGk
...kggggggggrrrk
...kgggyyyyyggk.
..kggyyyyyyyGGk.
..kgGyyyyyyGGk..
..kgGGyyyyGGk...
.kkkgGGGGGGkk...
kggkkkkkkkkggk..
kkk.......kgggk.
...........kkkk.
"""

FROG_RUN2 = """
................
................
.........kkk.kkk
........kwwwkwwk
........kwbwkwbk
......kkkgggggGk
....kkggggggggGk
...kggggggggrrrk
...kgggyyyyyggk.
..kggyyyyyyyGGk.
..kgGyyyyyyGGk..
..kgGGyyyyGGk...
...kgGGGGGGkkk..
..kggkkkkkkkggk.
.kgggk.......kkk
.kkkk...........
"""

FROG_JUMP = """
.........kkk.kkk
........kwwwkwwk
........kwbwkwbk
......kkkgggggGk
....kkggggggggGk
...kggggggggrrrk
...kgggyyyyyggk.
..kggyyyyyyyGGk.
..kgGyyyyyyGGk..
..kgGGyyyyGGk...
..kkgGGGGGGkk...
.kggkkkkkkkggk..
.kgk.......kgk..
kggk.......kggk.
kkk.........kkk.
................
"""

BEETLE1 = """
................
................
................
....k......k....
.....k....k.....
......kkkk......
....kkppppkk....
...kppppppppk...
..kpppwwppwwpk..
..kpppwbppwbpk..
..kpPppppppppk..
..kPPPPPPPPPPk..
...kkkkkkkkkk...
...ko.ko..ok....
..kok..ko.kok...
..kk....kk.kk...
"""

BEETLE2 = """
................
................
................
....k......k....
.....k....k.....
......kkkk......
....kkppppkk....
...kppppppppk...
..kpppwwppwwpk..
..kpppwbppwbpk..
..kpPppppppppk..
..kPPPPPPPPPPk..
...kkkkkkkkkk...
....ko.ok.ok....
...kok.kok.ko...
...kk..kk...kk..
"""

BEETLE_SQUASHED = """
................
................
................
................
................
................
................
................
................
................
................
....kkkkkkkk....
..kkppwwppwwpkk.
.kpppkbppkbppPk.
.kPPPPPPPPPPPPk.
..kkkkkkkkkkkk..
"""

COIN1 = """
................
................
................
.....kkkkkk.....
....kcccccck....
...kchhcccCCk...
...kchccccCCk...
...kccccccCCk...
...kccccccCCk...
...kccccccCCk...
...kccccccCCk...
...kcccccCCCk...
....kCCCCCCk....
.....kkkkkk.....
................
................
"""

COIN2 = """
................
................
................
......kkkk......
.....kcccck.....
.....khccCk.....
.....khccCk.....
.....kcccCk.....
.....kcccCk.....
.....kcccCk.....
.....kcccCk.....
.....kccCCk.....
.....kCCCCk.....
......kkkk......
................
................
"""

COIN3 = """
................
................
................
.......kk.......
......kcCk......
......khCk......
......khCk......
......kcCk......
......kcCk......
......kcCk......
......kcCk......
......kcCk......
......kCCk......
.......kk.......
................
................
"""


def from_ascii(art):
    rows = [r for r in art.strip("\n").split("\n")]
    if len(rows) != CELL or any(len(r) != CELL for r in rows):
        sys.exit(f"sprite art must be {CELL}x{CELL}:\n{art}")
    img = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            color = PALETTE[ch]
            if color is not None:
                img.putpixel((x, y), color + (255,))
    return img


def mirrored(img):
    return img.transpose(Image.Transpose.FLIP_LEFT_RIGHT)


# ---------------------------------------------------------------------------
# Tiles


def tile(seed):
    return Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0)), random.Random(seed)


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + (255,)


DIRT = (150, 95, 55)
GRASS = (90, 190, 70)


def dirt_pixels(img, rng, top=0):
    for y in range(top, CELL):
        for x in range(CELL):
            img.putpixel((x, y), shade(DIRT, 1 + rng.uniform(-0.08, 0.08)))
    for _ in range(6):  # pebbles
        x, y = rng.randrange(1, CELL - 1), rng.randrange(top + 1, CELL - 1)
        img.putpixel((x, y), shade(DIRT, 0.7))
        img.putpixel((x + 1, y), shade(DIRT, 1.25))


def grass_tile():
    img, rng = tile(1)
    dirt_pixels(img, rng, top=0)
    for x in range(CELL):
        depth = 4 + (1 if rng.random() < 0.4 else 0)
        for y in range(depth):
            f = 1.2 if y == 0 else 0.8 if y == depth - 1 else 1 + rng.uniform(-0.06, 0.06)
            img.putpixel((x, y), shade(GRASS, f))
    return img


def dirt_tile():
    img, rng = tile(2)
    dirt_pixels(img, rng)
    return img


def brick_tile():
    img, rng = tile(3)
    base = (190, 90, 60)
    mortar = (90, 50, 40)
    for y in range(CELL):
        row = y // 4
        offset = 0 if row % 2 == 0 else 4
        for x in range(CELL):
            if y % 4 == 3 or (x + offset) % 8 == 7:
                img.putpixel((x, y), mortar + (255,))
            else:
                f = 1.15 if y % 4 == 0 else 1 + rng.uniform(-0.05, 0.05)
                img.putpixel((x, y), shade(base, f))
    return img


def crate_tile():
    img, rng = tile(4)
    wood = (205, 150, 70)
    dark = (110, 70, 30)
    for y in range(CELL):
        for x in range(CELL):
            edge = x in (0, CELL - 1) or y in (0, CELL - 1)
            frame = x in (1, CELL - 2) or y in (1, CELL - 2)
            diag = abs(x - y) <= 1 or abs(x - (CELL - 1 - y)) <= 1
            if edge:
                c = dark + (255,)
            elif frame or diag:
                c = shade(wood, 0.8)
            else:
                c = shade(wood, 1 + rng.uniform(-0.06, 0.06))
            img.putpixel((x, y), c)
    return img


def bush_tile():
    img, _ = tile(5)
    for y in range(CELL):
        for x in range(CELL):
            # Three overlapping bumps, sitting on the tile's bottom edge.
            inside = any(((x - cx) ** 2 + (y - cy) ** 2) <= r * r for cx, cy, r in ((4, 11, 4.5), (8.5, 9, 5.5), (12, 11, 4)))
            if inside and y < CELL:
                lit = ((x - 6) ** 2 + (y - 6) ** 2) < 20
                img.putpixel((x, y), shade(GRASS, 1.2 if lit else 0.85))
    return img


def cloud_tile():
    img, _ = tile(6)
    for y in range(CELL):
        for x in range(CELL):
            inside = any(((x - cx) ** 2 + ((y - cy) * 1.3) ** 2) <= r * r for cx, cy, r in ((4, 10, 4), (8, 7, 5), (12, 10, 4)))
            if inside:
                shadow = y > 11
                img.putpixel((x, y), (215, 230, 245, 255) if shadow else (255, 255, 255, 255))
    return img


def pole_tile(top=False):
    img, _ = tile(7)
    for y in range(CELL):
        for x in (7, 8):
            img.putpixel((x, y), (200, 200, 210, 255) if x == 7 else (130, 130, 145, 255))
    if top:
        # Ball on top and a pennant flying right.
        for y in range(0, 4):
            for x in range(6, 10):
                if (x - 7.5) ** 2 + (y - 1.5) ** 2 <= 4:
                    img.putpixel((x, y), (250, 205, 60, 255))
        for y in range(4, 11):
            for x in range(9, 9 + (11 - y) if y >= 7 else 9 + (y - 3)):
                if x < CELL:
                    img.putpixel((x, y), (90, 200, 90, 255))
    return img


def main():
    root = Path(__file__).resolve().parent.parent
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "assets" / "hopper.png"

    cells = [
        grass_tile(), dirt_tile(), brick_tile(), crate_tile(),
        bush_tile(), cloud_tile(), pole_tile(), pole_tile(top=True),
    ]
    frog = [from_ascii(a) for a in (FROG_IDLE, FROG_RUN1, FROG_RUN2, FROG_JUMP)]
    cells += frog + [mirrored(f) for f in frog]
    cells += [from_ascii(a) for a in (BEETLE1, BEETLE2, BEETLE_SQUASHED, COIN1, COIN2, COIN3)]

    sheet = Image.new("RGBA", (CELL * COLUMNS, CELL * ROWS), (0, 0, 0, 0))
    for i, img in enumerate(cells):
        sheet.paste(img, ((i % COLUMNS) * CELL, (i // COLUMNS) * CELL))
    sheet.save(out)
    print(f"Wrote {out} ({sheet.width}x{sheet.height}, {len(cells)} cells)")


if __name__ == "__main__":
    main()
