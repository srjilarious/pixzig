"""Key, mouse, gamepad, event, easing, blend and text codes.

GENERATED FILE -- do not edit by hand. Regenerate with `zig build
py-constants`, which reads the enums in `src/pixzig/input/keys.zig`,
the `Event` kinds in `src/pixzig/platform/event.zig`, and the
renderer and easing enums listed in
`tools/gen_py_constants/gen_py_constants.zig`.

The values are pixzig's own dense indices into the engine's enums.
They are plain ints under the hood, but code should always use these
names rather than the numbers.
"""


class Key:
    """A keyboard key, by physical position rather than the printed letter.

    `Key.W` is where W sits on a US QWERTY keyboard, whatever layout is
    active, so WASD controls stay under the same fingers on AZERTY or
    Dvorak. Read typed text with `Keyboard.text()` instead. Letters are
    `A` to `Z`, digits `ZERO` to `NINE`, and the rest follow the engine's
    `Key` names uppercased: `SPACE`, `ESCAPE`, `ENTER`, `LEFT`,
    `LEFT_SHIFT`, `F1`, `KP_ENTER` and so on. `BACK` is Android's back
    button.
    """

    UNKNOWN = 0
    SPACE = 1
    APOSTROPHE = 2
    COMMA = 3
    MINUS = 4
    PERIOD = 5
    SLASH = 6
    ZERO = 7
    ONE = 8
    TWO = 9
    THREE = 10
    FOUR = 11
    FIVE = 12
    SIX = 13
    SEVEN = 14
    EIGHT = 15
    NINE = 16
    SEMICOLON = 17
    EQUAL = 18
    A = 19
    B = 20
    C = 21
    D = 22
    E = 23
    F = 24
    G = 25
    H = 26
    I = 27
    J = 28
    K = 29
    L = 30
    M = 31
    N = 32
    O = 33
    P = 34
    Q = 35
    R = 36
    S = 37
    T = 38
    U = 39
    V = 40
    W = 41
    X = 42
    Y = 43
    Z = 44
    LEFT_BRACKET = 45
    BACKSLASH = 46
    RIGHT_BRACKET = 47
    GRAVE_ACCENT = 48
    ESCAPE = 49
    ENTER = 50
    TAB = 51
    BACKSPACE = 52
    INSERT = 53
    DELETE = 54
    RIGHT = 55
    LEFT = 56
    DOWN = 57
    UP = 58
    PAGE_UP = 59
    PAGE_DOWN = 60
    HOME = 61
    END = 62
    CAPS_LOCK = 63
    SCROLL_LOCK = 64
    NUM_LOCK = 65
    PRINT_SCREEN = 66
    PAUSE = 67
    F1 = 68
    F2 = 69
    F3 = 70
    F4 = 71
    F5 = 72
    F6 = 73
    F7 = 74
    F8 = 75
    F9 = 76
    F10 = 77
    F11 = 78
    F12 = 79
    F13 = 80
    F14 = 81
    F15 = 82
    F16 = 83
    F17 = 84
    F18 = 85
    F19 = 86
    F20 = 87
    F21 = 88
    F22 = 89
    F23 = 90
    F24 = 91
    KP_0 = 92
    KP_1 = 93
    KP_2 = 94
    KP_3 = 95
    KP_4 = 96
    KP_5 = 97
    KP_6 = 98
    KP_7 = 99
    KP_8 = 100
    KP_9 = 101
    KP_DECIMAL = 102
    KP_DIVIDE = 103
    KP_MULTIPLY = 104
    KP_SUBTRACT = 105
    KP_ADD = 106
    KP_ENTER = 107
    KP_EQUAL = 108
    LEFT_SHIFT = 109
    LEFT_CONTROL = 110
    LEFT_ALT = 111
    LEFT_SUPER = 112
    RIGHT_SHIFT = 113
    RIGHT_CONTROL = 114
    RIGHT_ALT = 115
    RIGHT_SUPER = 116
    MENU = 117
    BACK = 118


class MouseButton:
    """A mouse button.

    Attributes:
        LEFT: The left button.
        RIGHT: The right button.
        MIDDLE: The middle button or wheel click.
        X1: The first side button, usually "back".
        X2: The second side button, usually "forward".
    """

    LEFT = 0
    RIGHT = 1
    MIDDLE = 2
    X1 = 3
    X2 = 4


class GamepadButton:
    """A gamepad button, by position on an Xbox-style pad.

    Attributes:
        A: The bottom face button.
        B: The right face button.
        X: The left face button.
        Y: The top face button.
        LEFT_BUMPER: The left shoulder button.
        RIGHT_BUMPER: The right shoulder button.
        BACK: The back or select button.
        START: The start button.
        GUIDE: The guide or home button.
        LEFT_THUMB: Pressing the left stick in.
        RIGHT_THUMB: Pressing the right stick in.
        DPAD_UP: D-pad up.
        DPAD_RIGHT: D-pad right.
        DPAD_DOWN: D-pad down.
        DPAD_LEFT: D-pad left.
    """

    A = 0
    B = 1
    X = 2
    Y = 3
    LEFT_BUMPER = 4
    RIGHT_BUMPER = 5
    BACK = 6
    START = 7
    GUIDE = 8
    LEFT_THUMB = 9
    RIGHT_THUMB = 10
    DPAD_UP = 11
    DPAD_RIGHT = 12
    DPAD_DOWN = 13
    DPAD_LEFT = 14


class GamepadAxis:
    """A gamepad stick or trigger axis.

    Attributes:
        LEFT_X: The left stick, -1 left to 1 right.
        LEFT_Y: The left stick, -1 up to 1 down.
        RIGHT_X: The right stick, -1 left to 1 right.
        RIGHT_Y: The right stick, -1 up to 1 down.
        LEFT_TRIGGER: The left trigger, 0 to 1.
        RIGHT_TRIGGER: The right trigger, 0 to 1.
    """

    LEFT_X = 0
    LEFT_Y = 1
    RIGHT_X = 2
    RIGHT_Y = 3
    LEFT_TRIGGER = 4
    RIGHT_TRIGGER = 5


class MouseAxis:
    """A direction of mouse movement, for `ActionMap.bind_axis_mouse`.

    Attributes:
        X: Horizontal movement, positive to the right.
        Y: Vertical movement, positive downward.
    """

    X = 0
    Y = 1


class EventKind:
    """What an `Event` reports.

    Attributes:
        CLOSE_REQUESTED: The close button, Alt+F4, Cmd+Q, or SIGINT/SIGTERM.
            The window closes afterwards unless `App.cancel_close()` is called.
        WINDOW_RESIZED: The window changed size; see `Event.size`.
        FOCUS_GAINED: The window got keyboard focus.
        FOCUS_LOST: The window lost keyboard focus. Input state is already
            cleared, so no key stays stuck down.
        MINIMIZED: The window was minimized.
        MAXIMIZED: The window was maximized.
        RESTORED: The window was restored from minimized or maximized.
        DROP_BEGIN: A drag-and-drop onto the window started.
        DROP_FILE: A file was dropped; see `Event.path` and `Event.pos`.
        DROP_TEXT: Text was dropped; see `Event.text` and `Event.pos`.
        DROP_COMPLETE: The drag-and-drop finished.
        GAMEPAD_ADDED: A pad was plugged in; see `Event.gamepad_id`.
        GAMEPAD_REMOVED: A pad was unplugged; see `Event.gamepad_id`.
        WILL_ENTER_BACKGROUND: The app is about to be suspended, mostly on
            mobile. Audio is already paused; save here.
        DID_ENTER_BACKGROUND: The app was suspended.
        WILL_ENTER_FOREGROUND: The app is about to resume.
        DID_ENTER_FOREGROUND: The app resumed. Audio is already resumed.
        LOW_MEMORY: The OS is low on memory.
        TERMINATING: The OS is closing the app.
        SCRIPT_RELOADED: A Lua script was reloaded. Zig games only; Python
            games never see it.
    """

    CLOSE_REQUESTED = 0
    WINDOW_RESIZED = 1
    FOCUS_GAINED = 2
    FOCUS_LOST = 3
    MINIMIZED = 4
    MAXIMIZED = 5
    RESTORED = 6
    DROP_BEGIN = 7
    DROP_FILE = 8
    DROP_TEXT = 9
    DROP_COMPLETE = 10
    GAMEPAD_ADDED = 11
    GAMEPAD_REMOVED = 12
    WILL_ENTER_BACKGROUND = 13
    DID_ENTER_BACKGROUND = 14
    WILL_ENTER_FOREGROUND = 15
    DID_ENTER_FOREGROUND = 16
    LOW_MEMORY = 17
    TERMINATING = 18
    SCRIPT_RELOADED = 19


class InputDevice:
    """A kind of input device, from `App.last_device`.

    Attributes:
        KEYBOARD: A key was pressed.
        MOUSE: A real mouse moved or clicked.
        GAMEPAD: A gamepad was used.
        TOUCH: The screen was touched.
    """

    KEYBOARD = 0
    MOUSE = 1
    GAMEPAD = 2
    TOUCH = 3


class Ease:
    """An easing curve, for `pixzig.easing` and `pixzig.sequence`.

    `_IN` curves start slow, `_OUT` curves end slow and `_IN_OUT` curves do
    both. `BACK_*` and `ELASTIC_OUT` overshoot before settling.

    Attributes:
        LINEAR: Constant speed.
        QUAD_IN: Quadratic, starting slow.
        QUAD_OUT: Quadratic, ending slow.
        QUAD_IN_OUT: Quadratic, slow at both ends.
        CUBIC_IN: Cubic, starting slow.
        CUBIC_OUT: Cubic, ending slow.
        CUBIC_IN_OUT: Cubic, slow at both ends.
        SINE_IN: Sine, starting slow.
        SINE_OUT: Sine, ending slow.
        SINE_IN_OUT: Sine, slow at both ends.
        BACK_IN: Pulls back below 0 before going.
        BACK_OUT: Overshoots past 1 and settles.
        ELASTIC_OUT: Overshoots and wobbles into place.
        BOUNCE_OUT: Bounces off 1 like a dropped ball.
    """

    LINEAR = 0
    QUAD_IN = 1
    QUAD_OUT = 2
    QUAD_IN_OUT = 3
    CUBIC_IN = 4
    CUBIC_OUT = 5
    CUBIC_IN_OUT = 6
    SINE_IN = 7
    SINE_OUT = 8
    SINE_IN_OUT = 9
    BACK_IN = 10
    BACK_OUT = 11
    ELASTIC_OUT = 12
    BOUNCE_OUT = 13


class BlendMode:
    """How draws combine with what's behind them, for `App.set_blend`.

    Attributes:
        ALPHA: Normal transparency, the default.
        ADDITIVE: Adds the color, brightening: glows, fire, lasers.
        MULTIPLY: Multiplies what's behind by the color, darkening:
            shadows, tinting.
        PREMULTIPLIED: For colors already multiplied by their alpha, such
            as a render target cleared transparent.
    """

    ALPHA = 0
    ADDITIVE = 1
    MULTIPLY = 2
    PREMULTIPLIED = 3


class TextAlign:
    """Which point of the text a draw's x names, for `Text.draw`.

    Attributes:
        LEFT: x is the left edge.
        CENTER: x is the middle.
        RIGHT: x is the right edge.
    """

    LEFT = 0
    CENTER = 1
    RIGHT = 2


class TargetFilter:
    """How a render target is sampled when drawn scaled, for
    `App.create_render_target`.

    Attributes:
        NEAREST: Hard pixel edges, for low-resolution pixel art.
        LINEAR: Smooth.
    """

    NEAREST = 0
    LINEAR = 1
