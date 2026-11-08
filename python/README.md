# pixzig

Python bindings for [pixzig](https://github.com/srjilarious/pixzig), a 2D game engine written in Zig.

The package talks to a prebuilt shared library of the engine through `ctypes`, so there's nothing to compile: wheels are published for Windows (x64) and Linux (x86_64, manylinux 2.28), and work on any Python 3.9 or newer.

```sh
pip install pixzig
```

```python
from pixzig import App, Key


class MyGame(App):
    def __init__(self):
        super().__init__("My Game", width=800, height=480)
        self.clear_color = (18, 18, 28)

    def update(self, dt_ms: float) -> None:
        if self.keyboard.pressed(Key.ESCAPE):
            self.quit()

    def render(self, alpha: float) -> None:
        self.render_begin()
        self.text.draw("Hello from pixzig! Esc to quit", 20, 20)
        self.render_end()


if __name__ == "__main__":
    MyGame().run()
```

- [Python bindings guide](https://www.walknsqualk.com/pixzig/page/python.html)
- [Full engine documentation](https://www.walknsqualk.com/pixzig/)
- [Python examples](https://github.com/srjilarious/pixzig/tree/main/python/examples) (they load art from the repo's top-level `assets/` folder)
