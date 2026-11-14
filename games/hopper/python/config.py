"""Gameplay numbers, read from assets/tuning.json at startup (config.zig). The
Zig version reads the same file, so tweaking it changes both."""

import json
from dataclasses import dataclass, fields


@dataclass
class Tuning:
    """Distances in pixels (a tile is 16), speeds in pixels per second, times
    in milliseconds. See src/config.zig for what each one does."""

    run_speed: float = 95
    ground_accel: float = 900
    air_accel: float = 600
    ground_friction: float = 1100
    gravity: float = 1000
    max_fall_speed: float = 320
    jump_speed: float = 380
    jump_release_cut: float = 0.45
    coyote_ms: float = 90
    jump_buffer_ms: float = 110
    walker_speed: float = 28
    walkers_turn_at_ledges: bool = True
    stomp_bounce: float = 260
    squash_ms: float = 450
    lives: int = 3
    death_pause_ms: float = 900
    camera_deadzone_x: float = 12
    camera_smoothing: float = 9

    @classmethod
    def load(cls, manifest, asset_id):
        """A Tuning from the manifest's JSON asset `asset_id`; fields it leaves
        out keep their default, and unknown ones (like "_comment") are
        ignored."""
        data = json.loads(manifest.read_raw(asset_id))
        known = {f.name for f in fields(cls)}
        return cls(**{k: v for k, v in data.items() if k in known})
