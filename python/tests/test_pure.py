"""Tests for the parts of the Python bindings that don't need a window:
sequences, the state stack, colors, easing, collision and saves.

Run from the repo root after `zig build python-ffi`:

    just py_test
"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from pixzig import Ease, collision, color, easing, save  # noqa: E402
from pixzig.sequence import SequencePlayer, Step, parallel, tween, tween_attr, wait  # noqa: E402
from pixzig.states import State, StateStack  # noqa: E402


class Box:
    value = 0.0


class SequenceTests(unittest.TestCase):
    def test_code_between_yields_runs_in_the_same_tick(self):
        log = []

        def seq():
            log.append("a")
            log.append("b")
            yield wait(100)
            log.append("c")

        p = SequencePlayer()
        p.play(seq())
        p.update(16)
        self.assertEqual(log, ["a", "b"])
        p.update(84)
        self.assertEqual(log, ["a", "b", "c"])
        self.assertEqual(p.count, 0)

    def test_leftover_time_carries_into_the_next_step(self):
        log = []

        def seq():
            yield wait(30)
            yield wait(30)
            log.append("done")

        p = SequencePlayer()
        p.play(seq())
        p.update(50)
        self.assertEqual(log, [])
        p.update(10)
        self.assertEqual(log, ["done"])

    def test_tween_attr_starts_from_the_current_value(self):
        box = Box()
        box.value = 10.0

        def seq():
            yield tween_attr(box, "value", 20.0, 100)
            box.value = 3.0

        p = SequencePlayer()
        p.play(seq())
        p.update(50)
        self.assertAlmostEqual(box.value, 15.0)
        p.update(50)
        self.assertEqual(box.value, 3.0)

    def test_tween_follows_the_curve(self):
        seen = []

        def seq():
            yield tween(seen.append, 0.0, 1.0, 100, Ease.QUAD_OUT)

        p = SequencePlayer()
        p.play(seq())
        p.update(50)
        self.assertAlmostEqual(seen[-1], 0.75, places=5)

    def test_parallel_finishes_with_the_slowest_track(self):
        log = []

        def short():
            yield wait(10)
            log.append("short")

        def long():
            yield wait(40)
            log.append("long")

        def seq():
            yield parallel(short(), long())
            log.append("after")

        p = SequencePlayer()
        p.play(seq())
        p.update(30)
        self.assertEqual(log, ["short"])
        p.update(10)
        self.assertEqual(log, ["short", "long", "after"])

    def test_bare_yield_waits_one_tick(self):
        log = []

        def seq():
            log.append(1)
            yield
            log.append(2)

        p = SequencePlayer()
        p.play(seq())
        p.update(16)
        self.assertEqual(log, [1])
        p.update(16)
        self.assertEqual(log, [1, 2])

    def test_yielding_a_generator_runs_it_as_a_sub_sequence(self):
        log = []

        def inner():
            yield wait(10)
            log.append("inner")

        def outer():
            yield inner()
            log.append("outer")

        p = SequencePlayer()
        p.play(outer())
        p.update(10)
        self.assertEqual(log, ["inner", "outer"])

    def test_cancel_by_tag_and_is_running(self):
        log = []

        def seq():
            try:
                yield wait(100)
                log.append("finished")
            finally:
                log.append("closed")

        p = SequencePlayer()
        p.play(seq(), tag="door")
        self.assertTrue(p.is_running("door"))
        p.update(16)
        self.assertEqual(p.cancel("door"), 1)
        self.assertFalse(p.is_running("door"))
        p.update(200)
        self.assertEqual(log, ["closed"])

    def test_a_sequence_can_cancel_itself_and_play_another(self):
        log = []
        p = SequencePlayer()

        def second():
            log.append("second")
            yield wait(1)

        def first():
            p.cancel("first")
            p.play(second(), tag="second")
            log.append("still running")
            yield wait(1)
            log.append("never")

        p.play(first(), tag="first")
        p.update(16)
        self.assertFalse(p.is_running("first"))
        self.assertTrue(p.is_running("second"))
        # The code up to the next yield ran; nothing after it does.
        self.assertEqual(log, ["still running"])
        p.update(16)
        self.assertEqual(log, ["still running", "second"])

    def test_custom_step(self):
        class Count(Step):
            def __init__(self):
                self.calls = 0

            def update(self, dt_ms):
                self.calls += 1
                return dt_ms if self.calls == 2 else None

        step = Count()

        def seq():
            yield step

        p = SequencePlayer()
        p.play(seq())
        p.update(16)
        p.update(16)
        self.assertEqual(step.calls, 2)
        self.assertEqual(p.count, 0)

    def test_play_needs_a_generator(self):
        def seq():
            yield wait(1)

        with self.assertRaises(TypeError):
            SequencePlayer().play(seq)


class Recorder(State):
    def __init__(self, name, log):
        self.name = name
        self.log = log

    def update(self, dt_ms):
        self.log.append(f"{self.name}.update")

    def render(self, alpha):
        self.log.append(f"{self.name}.render")

    def activate(self):
        self.log.append(f"{self.name}.activate")

    def deactivate(self):
        self.log.append(f"{self.name}.deactivate")

    def pause(self):
        self.log.append(f"{self.name}.pause")

    def resume(self):
        self.log.append(f"{self.name}.resume")


class StateStackTests(unittest.TestCase):
    def test_push_pop_hooks_and_below(self):
        log = []
        game, menu = Recorder("game", log), Recorder("menu", log)
        stack = StateStack(game)
        stack.push(menu)
        self.assertIs(stack.current, menu)
        self.assertEqual(stack.depth, 2)
        self.assertEqual(log, ["game.pause", "menu.activate"])

        log.clear()
        stack.update(16)
        stack.render(0.5)
        # Frozen below, drawn below.
        self.assertEqual(log, ["menu.update", "game.render", "menu.render"])

        log.clear()
        stack.pop()
        self.assertEqual(log, ["menu.deactivate", "game.resume"])
        with self.assertRaises(ValueError):
            stack.pop()

    def test_update_below_and_cover(self):
        log = []
        game, hud = Recorder("game", log), Recorder("hud", log)
        stack = StateStack(game)
        stack.push(hud, render_below=False, update_below=True)
        log.clear()
        stack.update(16)
        stack.render(1.0)
        self.assertEqual(log, ["game.update", "hud.update", "hud.render"])
        with self.assertRaises(ValueError):
            stack.push(hud)

    def test_set_state_replaces_the_stack(self):
        log = []
        a, b, c = Recorder("a", log), Recorder("b", log), Recorder("c", log)
        stack = StateStack(a)
        stack.push(b)
        log.clear()
        stack.set_state(c)
        self.assertEqual(log, ["b.deactivate", "a.deactivate", "c.activate"])
        self.assertEqual(stack.depth, 1)
        self.assertTrue(stack.is_on_stack(c))


class ColorTests(unittest.TestCase):
    def test_hex_forms(self):
        self.assertEqual(color.hex("#ff8800"), (255, 136, 0, 255))
        self.assertEqual(color.hex("ff880080"), (255, 136, 0, 128))
        self.assertEqual(color.hex("#f80"), (255, 136, 0, 255))
        self.assertEqual(color.hex(0x112233), (17, 34, 51, 255))
        with self.assertRaises(ValueError):
            color.hex("#12345")

    def test_lerp_and_alpha(self):
        self.assertEqual(color.lerp(color.BLACK, color.WHITE, 0.5), (128, 128, 128, 255))
        self.assertEqual(color.lerp((0, 0, 0), (10, 10, 10), 2), (10, 10, 10, 255))
        self.assertEqual(color.with_alpha((1, 2, 3), 9), (1, 2, 3, 9))


class EasingTests(unittest.TestCase):
    def test_curves_match_the_engine(self):
        self.assertAlmostEqual(easing.ease(Ease.LINEAR, 0.25), 0.25)
        self.assertAlmostEqual(easing.ease(Ease.QUAD_IN, 0.5), 0.25)
        self.assertAlmostEqual(easing.ease(Ease.QUAD_OUT, 2.0), 1.0)
        self.assertAlmostEqual(easing.tween(Ease.LINEAR, 10, 20, 0.5), 15.0)


class CollisionTests(unittest.TestCase):
    def test_overlaps(self):
        hit = collision.circle_circle((0, 0, 5), (8, 0, 5))
        self.assertEqual(hit.normal, (-1.0, 0.0))
        self.assertAlmostEqual(hit.depth, 2.0)
        self.assertEqual(hit.mtv, (-2.0, 0.0))
        self.assertIsNone(collision.circle_circle((0, 0, 1), (10, 0, 1)))
        self.assertIsNotNone(collision.rect_rect((0, 0, 10, 10), (8, 2, 10, 10)))
        self.assertIsNotNone(collision.circle_rect((5, 5, 2), (0, 0, 10, 10)))

    def test_segments_and_points(self):
        hit = collision.segment_rect(((-5, 5), (5, 5)), (0, 0, 10, 10))
        self.assertAlmostEqual(hit.t, 0.5)
        self.assertEqual(hit.point, (0.0, 5.0))
        self.assertIsNone(collision.segment_circle(((0, 0), (1, 0)), (10, 10, 1)))
        square = [(0, 0), (4, 0), (4, 4), (0, 4)]
        self.assertTrue(collision.point_in_polygon((1, 1), square))
        self.assertFalse(collision.point_in_polygon((5, 5), square))
        self.assertTrue(collision.point_in_circle((3, 4), (0, 0, 5)))


class SaveTests(unittest.TestCase):
    def test_json_round_trip_is_atomic(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "nested", "settings.json")
            self.assertEqual(save.load_json(path, default={"volume": 0.8}), {"volume": 0.8})
            save.save_json(path, {"volume": 0.25, "name": "nate"})
            self.assertEqual(save.load_json(path), {"volume": 0.25, "name": "nate"})
            self.assertFalse(os.path.exists(path + ".tmp"))


if __name__ == "__main__":
    unittest.main()
