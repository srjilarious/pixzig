"""Key, mouse, and gamepad codes.

GENERATED FILE -- do not edit by hand. Regenerate with `zig build
py-constants`, which reads the enums in `src/pixzig/input/keys.zig`.

The values are pixzig's own dense indices into the engine's
Key/MouseButton/Gamepad enums. They are plain ints under the hood, but
code should always use these names rather than the numbers.
"""


class Key:
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


class MouseButton:
    LEFT = 0
    RIGHT = 1
    MIDDLE = 2
    X1 = 3
    X2 = 4


class GamepadButton:
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
    LEFT_X = 0
    LEFT_Y = 1
    RIGHT_X = 2
    RIGHT_Y = 3
    LEFT_TRIGGER = 4
    RIGHT_TRIGGER = 5


class MouseAxis:
    X = 0
    Y = 1
