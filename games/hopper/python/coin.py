"""Coins: they spin in place until the player touches them (coin.zig)."""

import sheet

# Hitbox size. Smaller than the 16x16 sprite, so grabbing one means actually
# touching it.
SIZE = 10


class Coin:
    def __init__(self, x, y):
        self.x, self.y = x, y
        self.taken = False

    def center(self):
        return (self.x + SIZE / 2, self.y + SIZE / 2)


def cell(elapsed_ms):
    """The sheet cell every coin shows `elapsed_ms` into the level: they all
    spin together."""
    return sheet.COIN1 + int(elapsed_ms / 120) % sheet.COIN_FRAMES
