"""The cells of assets/hopper.png, which holds the level's tiles and every
sprite in an 8-column grid of 16x16 cells (sheet.zig, see tools/gen_art.py)."""

CELL = 16
COLUMNS = 8

# Tile cells (the level's tileset is this same image).
GRASS, DIRT = 0, 1

# Sprite cells. Sprites face right; they're flipped to face left.
FROG_IDLE, FROG_RUN1, FROG_RUN2, FROG_JUMP = 8, 9, 10, 11
BEETLE_WALK1, BEETLE_WALK2, BEETLE_SQUASHED = 12, 13, 14
COIN1, COIN_FRAMES = 15, 3

# Colours the art is drawn with: the sky behind everything, and the drop
# shadow under text.
SKY = (120, 180, 240)
SHADOW = (0, 0, 0)


def rect(index):
    """Where cell `index` is in the sheet, in pixels: (x, y, w, h)."""
    return ((index % COLUMNS) * CELL, (index // COLUMNS) * CELL, CELL, CELL)
