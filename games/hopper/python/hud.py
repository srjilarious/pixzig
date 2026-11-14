"""The coins and lives counter in the top-left corner (hud.zig)."""

import sheet


def draw(app, coins, lives):
    """Draws the HUD in screen space, so it stays put while the camera
    moves."""
    app.render_begin()
    app.text.draw(f"Coins {coins}   Lives {lives}", 6, 4, shadow=sheet.SHADOW)
    app.render_end()
