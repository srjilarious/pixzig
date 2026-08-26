"""Key, mouse, and gamepad codes. Values match GLFW's own codes exactly, so
they're plain ints under the hood -- but code should always use these names
rather than the raw numbers.
"""


class Key:
    SPACE = 32
    APOSTROPHE = 39
    COMMA = 44
    MINUS = 45
    PERIOD = 46
    SLASH = 47
    ZERO = 48
    ONE = 49
    TWO = 50
    THREE = 51
    FOUR = 52
    FIVE = 53
    SIX = 54
    SEVEN = 55
    EIGHT = 56
    NINE = 57
    SEMICOLON = 59
    EQUAL = 61
    A = 65
    B = 66
    C = 67
    D = 68
    E = 69
    F = 70
    G = 71
    H = 72
    I = 73
    J = 74
    K = 75
    L = 76
    M = 77
    N = 78
    O = 79
    P = 80
    Q = 81
    R = 82
    S = 83
    T = 84
    U = 85
    V = 86
    W = 87
    X = 88
    Y = 89
    Z = 90
    LEFT_BRACKET = 91
    BACKSLASH = 92
    RIGHT_BRACKET = 93
    GRAVE_ACCENT = 96

    ESCAPE = 256
    ENTER = 257
    TAB = 258
    BACKSPACE = 259
    INSERT = 260
    DELETE = 261
    RIGHT = 262
    LEFT = 263
    DOWN = 264
    UP = 265
    PAGE_UP = 266
    PAGE_DOWN = 267
    HOME = 268
    END = 269
    CAPS_LOCK = 280
    SCROLL_LOCK = 281
    NUM_LOCK = 282
    PRINT_SCREEN = 283
    PAUSE = 284
    F1 = 290
    F2 = 291
    F3 = 292
    F4 = 293
    F5 = 294
    F6 = 295
    F7 = 296
    F8 = 297
    F9 = 298
    F10 = 299
    F11 = 300
    F12 = 301
    LEFT_SHIFT = 340
    LEFT_CONTROL = 341
    LEFT_ALT = 342
    LEFT_SUPER = 343
    RIGHT_SHIFT = 344
    RIGHT_CONTROL = 345
    RIGHT_ALT = 346
    RIGHT_SUPER = 347


class MouseButton:
    LEFT = 0
    RIGHT = 1
    MIDDLE = 2


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
