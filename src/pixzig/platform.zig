//! The windowing / OS backend. Everything that talks to SDL3 directly
//! lives under here (plus `input/keys.zig`, which owns the code mapping),
//! so a future backend swap is confined to these files.

const window = @import("./platform/window.zig");

pub const Window = window.Window;
pub const WindowCreateOptions = window.WindowCreateOptions;
pub const showCursor = window.showCursor;
pub const timeMs = window.timeMs;
pub const setSwapInterval = window.setSwapInterval;
pub const glProcAddress = window.glProcAddress;
pub const initVideo = window.initVideo;
pub const quit = window.quit;
pub const sdlError = window.sdlError;
