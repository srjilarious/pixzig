//! Immediate mode GUI for pixzig.
//!
//! Call ui.update() once per engine update step (in app.update()).
//! Call ui.begin() / widgets / ui.end() once per render frame (in app.render()).
//!
//! Usage:
//!   // In App: ui: imgui.UiContext(AppRunner.Engine),
//!   //         .ui = imgui.UiContext(AppRunner.Engine).init(eng),
//!
//!   // In app.update():
//!   self.ui.update();
//!
//!   // In app.render(), inside renderer.begin()/end():
//!   self.ui.begin();
//!   self.ui.beginWindow("win", "My Window", &rect);
//!   self.ui.label("Hello!");
//!   self.ui.image(texture, .{ .x = 64, .y = 64 });
//!   if (self.ui.button("btn1", "Click Me")) { ... }
//!   // Side-by-side buttons using sameLine():
//!   _ = self.ui.buttonSized("ok", "OK", self.ui.contentWidth() / 2.0 - 2);
//!   self.ui.sameLine();
//!   if (self.ui.buttonSized("cancel", "Cancel", self.ui.contentWidth() / 2.0 - 2)) { ... }
//!   _ = self.ui.inputText("input1", &buf, &buf_len);
//!   _ = self.ui.inputInt("frame_ms", &frameMs);
//!   _ = self.ui.checkbox("loop", "Loop", &loop);
//!   _ = self.ui.selectableList("sprites", names, &selection, &scroll, 120);
//!   self.ui.textArea("log", log_lines.items, &scroll, 120);
//!   self.ui.endWindow();
//!   self.ui.end();

const std = @import("std");
const platform = @import("./platform.zig");
const TextureHandle = @import("./resources.zig").TextureHandle;
const Viewport = @import("./window.zig").Viewport;
const common = @import("./common.zig");
const input = @import("./input.zig");

const Vec2I = common.Vec2I;
const Vec2F = common.Vec2F;
const RectF = common.RectF;
const Color = common.Color;
const Keyboard = input.Keyboard;
const Mouse = input.Mouse;

// ============================================================
// Style
// ============================================================

pub const Style = struct {
    windowBg: Color = Color.from(30, 30, 35, 230),
    windowBorder: Color = Color.from(80, 80, 90, 255),
    windowTitleBg: Color = Color.from(50, 50, 70, 255),
    windowResizeHandle: Color = Color.from(100, 100, 120, 255),
    windowResizeHandleHover: Color = Color.from(135, 155, 205, 255),
    windowScrollbarTrack: Color = Color.from(20, 20, 28, 255),
    windowScrollbarThumb: Color = Color.from(80, 80, 100, 255),
    windowScrollbarThumbHover: Color = Color.from(110, 110, 140, 255),
    windowScrollbarThumbActive: Color = Color.from(60, 60, 80, 255),
    titleText: Color = Color.from(230, 230, 255, 255),
    buttonNormal: Color = Color.from(60, 60, 80, 255),
    buttonHover: Color = Color.from(90, 90, 120, 255),
    buttonPressed: Color = Color.from(40, 40, 60, 255),
    buttonDisabled: Color = Color.from(45, 45, 50, 200),
    buttonText: Color = Color.from(220, 220, 220, 255),
    buttonDisabledText: Color = Color.from(100, 100, 100, 255),
    selectableNormal: Color = Color.from(35, 35, 42, 255),
    selectableHover: Color = Color.from(65, 65, 85, 255),
    selectablePressed: Color = Color.from(45, 55, 78, 255),
    selectableSelected: Color = Color.from(60, 95, 145, 255),
    selectableText: Color = Color.from(220, 220, 220, 255),
    checkboxBg: Color = Color.from(20, 20, 25, 255),
    checkboxBorder: Color = Color.from(100, 100, 120, 255),
    checkboxHover: Color = Color.from(130, 150, 190, 255),
    checkboxCheck: Color = Color.from(95, 155, 230, 255),
    inputBg: Color = Color.from(20, 20, 25, 255),
    inputBorder: Color = Color.from(70, 70, 80, 255),
    inputBorderHover: Color = Color.from(100, 100, 120, 255),
    inputBorderFocused: Color = Color.from(100, 130, 200, 255),
    inputText: Color = Color.from(220, 220, 220, 255),
    inputCursor: Color = Color.from(180, 220, 255, 200),
    labelText: Color = Color.from(220, 220, 220, 255),
    textAreaBg: Color = Color.from(15, 15, 20, 255),
    textAreaBorder: Color = Color.from(60, 60, 70, 255),
    sliderTrack: Color = Color.from(30, 30, 40, 255),
    sliderFill: Color = Color.from(60, 100, 160, 255),
    sliderThumb: Color = Color.from(100, 150, 220, 255),
    sliderThumbHover: Color = Color.from(130, 180, 255, 255),
    sliderThumbActive: Color = Color.from(80, 120, 200, 255),
    sliderText: Color = Color.from(220, 220, 220, 255),
    padding: Vec2I = .{ .x = 8, .y = 6 },
    itemSpacing: i32 = 4,
    titleHeight: i32 = 22,
    resizeHandleSize: i32 = 14,
    minWindowSize: Vec2I = .{ .x = 120, .y = 70 },
    buttonHeight: i32 = 24,
    selectableHeight: i32 = 24,
    checkboxSize: i32 = 18,
    inputHeight: i32 = 24,
    sliderHeight: i32 = 24,
    sliderThumbW: i32 = 10,
    scrollbarW: f32 = 8,
    scrollbarTrack: Color = Color.from(20, 20, 28, 255),
    scrollbarThumb: Color = Color.from(80, 80, 100, 255),
    scrollbarThumbHover: Color = Color.from(110, 110, 140, 255),
    scrollbarThumbActive: Color = Color.from(60, 60, 80, 255),
};

// ============================================================
// ButtonState / ButtonResult
// ============================================================

pub const ButtonState = enum { normal, hover, pressed, disabled };

pub const ButtonResult = struct {
    clicked: bool,
    state: ButtonState,
};

pub const WindowSide = enum { left, right, up, down };

pub const InputTextOptions = struct {
    submitOnEnter: bool = false,
    clipboard: bool = true,
    clearOnCtrlL: bool = true,
    historyKeys: bool = false,
};

pub const InputTextResult = struct {
    changed: bool = false,
    submitted: bool = false,
    focused: bool = false,
    historyPrev: bool = false,
    historyNext: bool = false,
    copied: bool = false,
    pasted: bool = false,
    cleared: bool = false,
};

// ============================================================
// Internal per-window layout state
// ============================================================

const WindowCtx = struct {
    id: u64,
    rect: RectF,
    contentRect: RectF,
    scrollY: f32,
    contentY: f32, // next widget baseline Y
    lastX: f32, // top-left of last placed widget
    lastY: f32,
    lastW: f32, // size of last placed widget
    lastH: f32,
    sameLine: bool, // if true, next widget placed to the right
};

const WindowState = struct {
    used: bool = false,
    id: u64 = 0,
    contentHeight: f32 = 0,
    scrollY: f32 = 0,
};

// ============================================================
// UiContext
// ============================================================

/// An immediate-mode UI drawing through `Engine`'s renderer, e.g.
/// `imgui.UiContext(AppRunner.Engine).init(eng)`. The engine needs shape and
/// text rendering enabled.
pub fn UiContext(comptime Engine: type) type {
    return struct {
        const Self = @This();

        hotId: u64, // widget the mouse is currently over
        activeId: u64, // widget being clicked/dragged
        focusId: u64, // widget with keyboard focus
        frame: u64, // frame counter (used for cursor blink)

        mouse: *Mouse,
        keyboard: *Keyboard,
        viewport: *const Viewport,
        /// Widgets draw in submission order through the renderer, so the UI
        /// lands above whatever the scene drew earlier in the same pass.
        renderer: *Engine.Renderer,
        clipboardWindow: ?*platform.Window,
        style: Style,

        winStack: [8]WindowCtx,
        winDepth: usize,
        windowStates: [32]WindowState,

        // ----------------------------------------------------------
        // Input accumulated by update() — consumed each render frame
        // ----------------------------------------------------------

        /// Typed characters accumulated across all update() calls this frame.
        textInput: [64]u8,
        textInputLen: usize,
        /// Number of backspace presses accumulated this frame.
        backspaceCount: usize,
        /// Number of delete presses accumulated this frame.
        deleteCount: usize,
        /// Whether page-up was pressed in any update step this frame.
        pageUpPressed: bool,
        /// Whether page-down was pressed in any update step this frame.
        pageDownPressed: bool,
        /// Vertical scroll wheel delta accumulated this frame (positive = up).
        scrollDelta: f32,
        /// Set to true by the first widget that consumes scrollDelta this frame,
        /// preventing parent containers from double-scrolling.
        scrollConsumed: bool,

        /// Scratch text used by the currently focused integer input.
        intEditBuf: [32]u8,
        intEditLen: usize,
        intEditId: u64,
        intEditReplace: bool,

        /// Cursor position within the focused text/int input buffer.
        /// Shared between inputText and inputInt; reset when focus changes.
        editCursorId: u64,
        editCursorPos: usize,

        /// Number of left/right arrow key presses accumulated this frame.
        leftArrowCount: usize,
        rightArrowCount: usize,
        /// Number of up/down arrow key presses accumulated this frame.
        upArrowCount: usize,
        downArrowCount: usize,
        /// Home/end movement for focused text editors.
        homePressed: bool,
        endPressed: bool,
        /// Common text editing shortcuts accumulated this frame.
        ctrlCPressed: bool,
        ctrlVPressed: bool,
        ctrlLPressed: bool,
        /// Whether Tab was pressed this frame (forward) or shift+Tab (backward).
        tabPressed: bool,
        tabBackward: bool,
        /// Whether Enter (or keypad enter) was pressed this frame.
        enterPressed: bool,

        /// Ordered list of focusable widget IDs registered this frame (for Tab cycling).
        tabFocusOrder: [64]u64,
        tabFocusCount: usize,

        // ----------------------------------------------------------
        // Mouse state snapshotted by update()
        // ----------------------------------------------------------

        /// Mouse position in render coordinates (already scaled).
        mousePos: Vec2F,
        /// True if the left button was pressed in any update step this frame.
        leftPressed: bool,
        /// True if the left button was released in any update step this frame.
        leftReleased: bool,
        /// True if the left button is currently held.
        leftDown: bool,
        windowDragOffset: Vec2F,
        windowResizeStartMouse: Vec2F,
        windowResizeStartSize: Vec2F,

        pub fn init(eng: *Engine) Self {
            return .{
                .hotId = 0,
                .activeId = 0,
                .focusId = 0,
                .frame = 0,
                .mouse = &eng.inputs.mouse,
                .keyboard = &eng.inputs.keyboard,
                .viewport = &eng.viewport,
                .renderer = &eng.renderer,
                .clipboardWindow = null,
                .style = Style{},
                .winStack = undefined,
                .winDepth = 0,
                .windowStates = @splat(.{}),
                .textInput = undefined,
                .textInputLen = 0,
                .backspaceCount = 0,
                .deleteCount = 0,
                .pageUpPressed = false,
                .pageDownPressed = false,
                .scrollDelta = 0,
                .scrollConsumed = false,
                .intEditBuf = undefined,
                .intEditLen = 0,
                .intEditId = 0,
                .intEditReplace = false,
                .editCursorId = 0,
                .editCursorPos = 0,
                .leftArrowCount = 0,
                .rightArrowCount = 0,
                .upArrowCount = 0,
                .downArrowCount = 0,
                .homePressed = false,
                .endPressed = false,
                .ctrlCPressed = false,
                .ctrlVPressed = false,
                .ctrlLPressed = false,
                .tabPressed = false,
                .tabBackward = false,
                .enterPressed = false,
                .tabFocusOrder = undefined,
                .tabFocusCount = 0,
                .mousePos = .{ .x = 0, .y = 0 },
                .leftPressed = false,
                .leftReleased = false,
                .leftDown = false,
                .windowDragOffset = .{ .x = 0, .y = 0 },
                .windowResizeStartMouse = .{ .x = 0, .y = 0 },
                .windowResizeStartSize = .{ .x = 0, .y = 0 },
            };
        }

        /// Enables clipboard shortcuts for text inputs. Without this, Ctrl+C and
        /// Ctrl+V are reported but cannot touch the OS clipboard.
        pub fn setClipboardWindow(self: *Self, window: *platform.Window) void {
            self.clipboardWindow = window;
        }

        // ----------------------------------------------------------
        // update() — call once per engine update step in app.update()
        // ----------------------------------------------------------

        /// Latch keyboard and mouse input for this update step.
        /// Must be called from app.update(), after mouse.update().
        pub fn update(self: *Self) void {
            // Advance the frame counter here (fixed update rate) so cursor-blink
            // logic based on frame/N runs at a stable speed regardless of FPS.
            self.frame +%= 1;

            // Re-derive mouse position from the framebuffer-space cursor position
            // through this UI's own viewport, so the coordinates match whichever
            // projection is used when draw() is called.
            self.mousePos = self.viewport.framebufferToLogical(self.mouse.fbPos()) orelse
                Vec2F{ .x = -1, .y = -1 };
            self.leftDown = self.mouse.down(.left);
            if (self.mouse.pressed(.left)) self.leftPressed = true;
            if (self.mouse.released(.left)) self.leftReleased = true;

            const ctrl_down = self.keyboard.ctrl();
            const alt_down = self.keyboard.alt();
            const super_down = self.keyboard.super();

            // Accumulate typed characters. Modified key chords are handled below
            // as commands, so they should not also type their letter.
            if (!ctrl_down and !alt_down and !super_down) {
                var buf: [8]u8 = undefined;
                const n = self.keyboard.text(&buf);
                for (buf[0..n]) |c| {
                    if (self.textInputLen < self.textInput.len) {
                        self.textInput[self.textInputLen] = c;
                        self.textInputLen += 1;
                    }
                }
            }

            // Accumulate special key presses
            if (self.keyboard.pressed(.backspace)) self.backspaceCount += 1;
            if (self.keyboard.pressed(.delete)) self.deleteCount += 1;
            if (self.keyboard.pressed(.page_up)) self.pageUpPressed = true;
            if (self.keyboard.pressed(.page_down)) self.pageDownPressed = true;
            if (self.keyboard.pressed(.left)) self.leftArrowCount += 1;
            if (self.keyboard.pressed(.right)) self.rightArrowCount += 1;
            if (self.keyboard.pressed(.up)) self.upArrowCount += 1;
            if (self.keyboard.pressed(.down)) self.downArrowCount += 1;
            if (self.keyboard.pressed(.home)) self.homePressed = true;
            if (self.keyboard.pressed(.end)) self.endPressed = true;
            if (ctrl_down and self.keyboard.pressed(.c)) self.ctrlCPressed = true;
            if (ctrl_down and self.keyboard.pressed(.v)) self.ctrlVPressed = true;
            if (ctrl_down and self.keyboard.pressed(.l)) self.ctrlLPressed = true;
            if (self.keyboard.pressed(.tab)) {
                if (self.keyboard.shift()) {
                    self.tabBackward = true;
                } else {
                    self.tabPressed = true;
                }
            }
            if (self.keyboard.pressed(.enter) or self.keyboard.pressed(.kp_enter)) self.enterPressed = true;

            self.scrollDelta += self.mouse.scroll().y;
        }

        // ----------------------------------------------------------
        // Frame lifecycle — begin/end wrap all widget calls in render()
        // ----------------------------------------------------------

        /// Call at the start of each render frame before any widgets.
        pub fn begin(self: *Self) void {
            self.hotId = 0;
            self.tabFocusCount = 0;
        }

        /// Call at the end of each render frame after all widgets.
        /// Clears accumulated input state for the next frame.
        pub fn end(self: *Self) void {
            // Handle focus: click on empty space clears it
            if (self.leftPressed and self.hotId == 0) {
                self.focusId = 0;
            }
            // Release active widget when mouse released
            if (self.leftReleased) {
                self.activeId = 0;
            }

            // Tab focus cycling
            if ((self.tabPressed or self.tabBackward) and self.tabFocusCount > 0) {
                var found: ?usize = null;
                for (self.tabFocusOrder[0..self.tabFocusCount], 0..) |id, i| {
                    if (id == self.focusId) {
                        found = i;
                        break;
                    }
                }
                const n = self.tabFocusCount;
                const next_idx = if (self.tabBackward)
                    if (found) |i| (i + n - 1) % n else n - 1
                else if (found) |i| (i + 1) % n else 0;
                self.focusId = self.tabFocusOrder[next_idx];
            }

            // Clear accumulated input for next frame
            self.textInputLen = 0;
            self.backspaceCount = 0;
            self.deleteCount = 0;
            self.pageUpPressed = false;
            self.pageDownPressed = false;
            self.leftArrowCount = 0;
            self.rightArrowCount = 0;
            self.upArrowCount = 0;
            self.downArrowCount = 0;
            self.homePressed = false;
            self.endPressed = false;
            self.ctrlCPressed = false;
            self.ctrlVPressed = false;
            self.ctrlLPressed = false;
            self.tabPressed = false;
            self.tabBackward = false;
            self.enterPressed = false;
            self.scrollDelta = 0;
            self.scrollConsumed = false;
            self.leftPressed = false;
            self.leftReleased = false;
        }

        // ----------------------------------------------------------
        // Window
        // ----------------------------------------------------------

        /// Resize and place a window against one edge of the logical screen.
        /// `percent` controls width for left/right and height for up/down.
        pub fn resizeWindowToSide(self: *Self, rect: *RectF, side: WindowSide, percent: f32, screen_size: Vec2I) void {
            _ = self;
            const p = std.math.clamp(percent, 0.0, 1.0);
            const width: f32 = @floatFromInt(screen_size.x);
            const height: f32 = @floatFromInt(screen_size.y);
            switch (side) {
                .left => rect.* = .{ .l = 0, .t = 0, .r = width * p, .b = height },
                .right => rect.* = .{ .l = width * (1.0 - p), .t = 0, .r = width, .b = height },
                .up => rect.* = .{ .l = 0, .t = 0, .r = width, .b = height * p },
                .down => rect.* = .{ .l = 0, .t = height * (1.0 - p), .r = width, .b = height },
            }
        }

        fn windowState(self: *Self, id: u64) *WindowState {
            for (&self.windowStates) |*state| {
                if (state.used and state.id == id) return state;
            }
            for (&self.windowStates) |*state| {
                if (!state.used) {
                    state.* = .{ .used = true, .id = id };
                    return state;
                }
            }
            return &self.windowStates[@intCast(id % self.windowStates.len)];
        }

        /// Clips to the enclosing window's content, or back to the viewport
        /// when leaving the outermost window.
        fn restoreContentClip(self: *Self) void {
            if (self.winDepth > 1) {
                self.renderer.setClip(self.winStack[self.winDepth - 2].contentRect);
            } else {
                self.renderer.setClip(null);
            }
        }

        /// Begin a draggable and bottom-right resizable window.
        /// `rect` stores the persistent bounds and must be matched with endWindow().
        pub fn beginWindow(
            self: *Self,
            id: []const u8,
            title: []const u8,
            rect: *RectF,
        ) void {
            const s = &self.style;
            const title_h: f32 = @floatFromInt(s.titleHeight);
            const pad_x: f32 = @floatFromInt(s.padding.x);
            const pad_y: f32 = @floatFromInt(s.padding.y);
            const resize_size: f32 = @floatFromInt(s.resizeHandleSize);
            const uid = hashId(id);
            const move_uid = uid ^ 0x5749_4e44_4f57_0001;
            const resize_uid = uid ^ 0x5749_4e44_4f57_0002;
            const scroll_uid = uid ^ 0x5749_4e44_4f57_0003;
            const state = self.windowState(uid);

            var resize_rect = RectF{
                .l = rect.r - resize_size,
                .t = rect.b - resize_size,
                .r = rect.r,
                .b = rect.b,
            };
            const over_resize = self.testHot(resize_uid, resize_rect);
            if (over_resize and self.leftPressed) {
                self.activeId = resize_uid;
                self.focusId = resize_uid;
                self.windowResizeStartMouse = self.mousePos;
                self.windowResizeStartSize = .{ .x = rect.width(), .y = rect.height() };
            }
            if (self.activeId == resize_uid and self.leftDown) {
                const min_w: f32 = @floatFromInt(s.minWindowSize.x);
                const min_h: f32 = @floatFromInt(s.minWindowSize.y);
                const width = @max(min_w, self.windowResizeStartSize.x + self.mousePos.x - self.windowResizeStartMouse.x);
                const height = @max(min_h, self.windowResizeStartSize.y + self.mousePos.y - self.windowResizeStartMouse.y);
                rect.r = rect.l + width;
                rect.b = rect.t + height;
            }

            var title_rect = RectF{
                .l = rect.l,
                .t = rect.t,
                .r = rect.r,
                .b = rect.t + title_h,
            };
            const over_title = self.testHot(move_uid, title_rect);
            if (over_title and self.leftPressed and self.activeId != resize_uid) {
                self.activeId = move_uid;
                self.focusId = move_uid;
                self.windowDragOffset = .{
                    .x = self.mousePos.x - rect.l,
                    .y = self.mousePos.y - rect.t,
                };
            }
            if (self.activeId == move_uid and self.leftDown) {
                const width = rect.width();
                const height = rect.height();
                rect.l = self.mousePos.x - self.windowDragOffset.x;
                rect.t = self.mousePos.y - self.windowDragOffset.y;
                rect.r = rect.l + width;
                rect.b = rect.t + height;
            }

            const content_t = rect.t + title_h + pad_y;
            const content_b = rect.b - pad_y;
            const visible_h = @max(0.0, content_b - content_t);
            const scrollable = state.contentHeight > visible_h;
            const max_scroll = @max(0.0, state.contentHeight - visible_h);
            state.scrollY = std.math.clamp(state.scrollY, 0.0, max_scroll);
            const scroll_space = if (scrollable) s.scrollbarW + @as(f32, @floatFromInt(s.itemSpacing)) else 0.0;
            const contentRect = RectF{
                .l = rect.l + pad_x,
                .t = content_t,
                .r = rect.r - pad_x - scroll_space,
                .b = content_b,
            };

            if (scrollable) {
                const sb_rect = RectF{
                    .l = rect.r - pad_x - s.scrollbarW,
                    .t = content_t,
                    .r = rect.r - pad_x,
                    .b = content_b,
                };
                const over_scrollbar = self.testHot(scroll_uid, sb_rect);
                if (over_scrollbar and self.leftPressed) self.activeId = scroll_uid;
                if (self.activeId == scroll_uid and self.leftDown) {
                    const thumb_h = @max(visible_h * visible_h / state.contentHeight, 12.0);
                    const travel = @max(1.0, visible_h - thumb_h);
                    const t = std.math.clamp((self.mousePos.y - sb_rect.t - thumb_h / 2.0) / travel, 0.0, 1.0);
                    state.scrollY = t * max_scroll;
                }
            }

            // Background
            self.renderer.drawFilledRect(rect.*, s.windowBg);
            self.renderer.drawEnclosingRect(rect.*, s.windowBorder, 1);

            // Title bar
            title_rect = RectF{
                .l = rect.l,
                .t = rect.t,
                .r = rect.r,
                .b = rect.t + title_h,
            };
            self.renderer.drawFilledRect(title_rect, s.windowTitleBg);
            resize_rect = .{
                .l = rect.r - resize_size,
                .t = rect.b - resize_size,
                .r = rect.r,
                .b = rect.b,
            };
            self.renderer.drawFilledRect(
                resize_rect.shrinkFrom(3.0),
                if (over_resize or self.activeId == resize_uid) s.windowResizeHandleHover else s.windowResizeHandle,
            );

            // Title text — vertically centered in title bar
            const line_h: f32 = @floatFromInt(self.renderer.lineHeight() orelse 16);
            _ = self.renderer.drawString(title, .{
                .x = @intFromFloat(rect.l + pad_x),
                .y = @intFromFloat(rect.t + (title_h - line_h) / 2.0),
            });

            // Push window context
            std.debug.assert(self.winDepth < self.winStack.len);
            self.winStack[self.winDepth] = .{
                .id = uid,
                .rect = rect.*,
                .contentRect = contentRect,
                .scrollY = state.scrollY,
                .contentY = content_t - state.scrollY,
                .lastX = rect.l + pad_x,
                .lastY = content_t - state.scrollY,
                .lastW = 0,
                .lastH = 0,
                .sameLine = false,
            };
            self.winDepth += 1;

            self.renderer.setClip(contentRect);
        }

        /// End the current window.
        pub fn endWindow(self: *Self) void {
            std.debug.assert(self.winDepth > 0);
            const win = self.curWin().*;
            const state = self.windowState(win.id);
            const content_top = win.contentRect.t;
            state.contentHeight = @max(0.0, win.contentY + win.scrollY - content_top);
            const visible_h = win.contentRect.height();
            const max_scroll = @max(0.0, state.contentHeight - visible_h);
            state.scrollY = std.math.clamp(state.scrollY, 0.0, max_scroll);

            if (max_scroll > 0.0 and !self.scrollConsumed and self.scrollDelta != 0.0) {
                const rect = win.rect;
                const mp = self.mousePos;
                if (mp.x >= rect.l and mp.x < rect.r and mp.y >= rect.t and mp.y < rect.b) {
                    const line_h: f32 = @floatFromInt(self.renderer.lineHeight() orelse 16);
                    state.scrollY = std.math.clamp(
                        state.scrollY - self.scrollDelta * line_h * 3.0,
                        0.0,
                        max_scroll,
                    );
                    self.scrollConsumed = true;
                }
            }

            self.restoreContentClip();

            if (max_scroll > 0.0) {
                const s = &self.style;
                const pad_x: f32 = @floatFromInt(s.padding.x);
                const sb_rect = RectF{
                    .l = win.rect.r - pad_x - s.scrollbarW,
                    .t = win.contentRect.t,
                    .r = win.rect.r - pad_x,
                    .b = win.contentRect.b,
                };
                const visible = sb_rect.height();
                const thumb_h = @max(visible * visible / state.contentHeight, 12.0);
                const travel = visible - thumb_h;
                const scroll_t = if (max_scroll > 0.0) state.scrollY / max_scroll else 0.0;
                const thumb = RectF{
                    .l = sb_rect.l + 1.0,
                    .t = sb_rect.t + scroll_t * travel,
                    .r = sb_rect.r - 1.0,
                    .b = sb_rect.t + scroll_t * travel + thumb_h,
                };
                const scroll_uid = win.id ^ 0x5749_4e44_4f57_0003;
                self.renderer.drawFilledRect(sb_rect, s.windowScrollbarTrack);
                self.renderer.drawFilledRect(
                    thumb,
                    if (self.activeId == scroll_uid)
                        s.windowScrollbarThumbActive
                    else if (self.hotId == scroll_uid)
                        s.windowScrollbarThumbHover
                    else
                        s.windowScrollbarThumb,
                );
            }
            self.winDepth -= 1;
        }

        // ----------------------------------------------------------
        // Layout helpers
        // ----------------------------------------------------------

        fn curWin(self: *Self) *WindowCtx {
            return &self.winStack[self.winDepth - 1];
        }

        /// Allocate a rect for the next widget, advancing the layout cursor.
        fn allocWidget(self: *Self, w: f32, h: f32) RectF {
            const win = self.curWin();
            const pad_x: f32 = @floatFromInt(self.style.padding.x);
            const item_sp: f32 = @floatFromInt(self.style.itemSpacing);

            var x: f32 = undefined;
            var y: f32 = undefined;

            if (win.sameLine) {
                x = win.lastX + win.lastW + item_sp;
                y = win.lastY;
                win.sameLine = false;
            } else {
                x = win.rect.l + pad_x;
                y = win.contentY;
            }

            const rect = RectF{ .l = x, .t = y, .r = x + w, .b = y + h };

            win.lastX = x;
            win.lastY = y;
            win.lastW = w;
            win.lastH = h;

            const new_bottom = y + h + item_sp;
            if (new_bottom > win.contentY) {
                win.contentY = new_bottom;
            }

            return rect;
        }

        /// Place the next widget on the same line as the previous widget.
        pub fn sameLine(self: *Self) void {
            self.curWin().sameLine = true;
        }

        /// Add extra vertical space.
        pub fn spacing(self: *Self) void {
            const win = self.curWin();
            win.contentY += @as(f32, @floatFromInt(self.style.itemSpacing)) * 2.0;
        }

        pub fn contentWidth(self: *Self) f32 {
            const win = self.curWin();
            return win.contentRect.width();
        }

        /// Returns the remaining vertical space inside the current window,
        /// accounting for bottom padding. Useful for filling the rest of the
        /// window with a text area or other expanding widget.
        pub fn remainingHeight(self: *Self) f32 {
            const win = self.curWin();
            const remaining = win.contentRect.b - (win.contentY + win.scrollY);
            return @max(0, remaining);
        }

        // ----------------------------------------------------------
        // ID hashing (FNV-1a)
        // ----------------------------------------------------------

        fn hashId(s: []const u8) u64 {
            var h: u64 = 14695981039346656037;
            for (s) |c| {
                h ^= c;
                h *%= 1099511628211;
            }
            return h;
        }

        fn indexId(parent: u64, index: usize) u64 {
            var h = parent;
            var n: usize = index + 1;
            while (n > 0) : (n >>= 8) {
                h ^= @as(u64, @intCast(n & 0xff));
                h *%= 1099511628211;
            }
            return h;
        }

        fn registerFocusable(self: *Self, uid: u64) void {
            if (self.tabFocusCount < self.tabFocusOrder.len) {
                self.tabFocusOrder[self.tabFocusCount] = uid;
                self.tabFocusCount += 1;
            }
        }

        // ----------------------------------------------------------
        // Mouse hit test — uses the position snapshotted in update()
        // ----------------------------------------------------------

        fn testHot(self: *Self, id: u64, rect: RectF) bool {
            // mousePos is already in logical coordinates (converted in update()).
            // Widget rects live in the same logical space, so compare directly.
            const mp = self.mousePos;
            var over = mp.x >= rect.l and mp.x < rect.r and
                mp.y >= rect.t and mp.y < rect.b;
            if (over and self.winDepth > 0) {
                const clip = self.curWin().contentRect;
                over = mp.x >= clip.l and mp.x < clip.r and
                    mp.y >= clip.t and mp.y < clip.b;
            }
            if (over) self.hotId = id;
            return over;
        }

        // ----------------------------------------------------------
        // label
        // ----------------------------------------------------------

        pub fn label(self: *Self, str: []const u8) void {
            const s = &self.style;
            const line_h: i32 = self.renderer.lineHeight() orelse 16;
            const h: f32 = @floatFromInt(line_h + s.itemSpacing);
            const w: f32 = self.contentWidth();
            const rect = self.allocWidget(w, h);
            _ = self.renderer.drawString(str, .{
                .x = @intFromFloat(rect.l),
                .y = @intFromFloat(rect.t),
            });
        }

        // ----------------------------------------------------------
        // image
        // ----------------------------------------------------------

        /// Draw a texture or atlas subtexture at the requested logical size.
        pub fn image(self: *Self, texture: *TextureHandle, size: Vec2I) void {
            const rect = self.allocWidget(
                @floatFromInt(size.x),
                @floatFromInt(size.y),
            );
            self.renderer.drawTexture(texture, rect, texture.val.src);
        }

        // ----------------------------------------------------------
        // button / buttonEx
        // ----------------------------------------------------------

        /// Draw a button. Returns true if clicked this frame.
        pub fn button(self: *Self, id: []const u8, lbl: []const u8) bool {
            return self.buttonEx(id, lbl, false).clicked;
        }

        /// Draw a button with an explicit pixel width. Useful with sameLine() to
        /// place multiple buttons on one row.
        pub fn buttonSized(self: *Self, id: []const u8, lbl: []const u8, width: f32) bool {
            return self.buttonSizedEx(id, lbl, width, false).clicked;
        }

        /// Draw a button with explicit width and disabled state.
        pub fn buttonSizedEx(
            self: *Self,
            id: []const u8,
            lbl: []const u8,
            width: f32,
            disabled: bool,
        ) ButtonResult {
            const s = &self.style;
            const uid = hashId(id);
            const h: f32 = @floatFromInt(s.buttonHeight);
            const rect = self.allocWidget(width, h);

            self.registerFocusable(uid);

            var state = ButtonState.normal;
            var clicked = false;

            if (disabled) {
                state = .disabled;
            } else {
                const over = self.testHot(uid, rect);
                if (over and self.leftPressed) {
                    self.activeId = uid;
                    self.focusId = uid;
                }
                if (self.activeId == uid) {
                    state = .pressed;
                    if (over and self.leftReleased) {
                        clicked = true;
                    }
                } else if (over) {
                    state = .hover;
                }
                if (self.focusId == uid and self.enterPressed) {
                    clicked = true;
                }
            }

            const bg = switch (state) {
                .normal => s.buttonNormal,
                .hover => s.buttonHover,
                .pressed => s.buttonPressed,
                .disabled => s.buttonDisabled,
            };
            self.renderer.drawFilledRect(rect, bg);
            self.renderer.drawEnclosingRect(rect, s.windowBorder, 1);

            const ts = self.renderer.measureString(lbl);
            const line_h: f32 = @floatFromInt(self.renderer.lineHeight() orelse 16);
            const tx: i32 = @intFromFloat(rect.l + (width - @as(f32, @floatFromInt(ts.x))) / 2.0);
            const ty: i32 = @intFromFloat(rect.t + (h - line_h) / 2.0);
            _ = self.renderer.drawString(lbl, .{ .x = tx, .y = ty });

            return .{ .clicked = clicked, .state = state };
        }

        /// Draw a button with explicit disabled state.
        pub fn buttonEx(
            self: *Self,
            id: []const u8,
            lbl: []const u8,
            disabled: bool,
        ) ButtonResult {
            const s = &self.style;
            const uid = hashId(id);
            const h: f32 = @floatFromInt(s.buttonHeight);
            const w: f32 = self.contentWidth();
            const rect = self.allocWidget(w, h);

            self.registerFocusable(uid);

            var state = ButtonState.normal;
            var clicked = false;

            if (disabled) {
                state = .disabled;
            } else {
                const over = self.testHot(uid, rect);
                if (over and self.leftPressed) {
                    self.activeId = uid;
                    self.focusId = uid;
                }
                if (self.activeId == uid) {
                    state = .pressed;
                    if (over and self.leftReleased) {
                        clicked = true;
                    }
                } else if (over) {
                    state = .hover;
                }
                // Enter key fires the focused button
                if (self.focusId == uid and self.enterPressed) {
                    clicked = true;
                }
            }

            const bg = switch (state) {
                .normal => s.buttonNormal,
                .hover => s.buttonHover,
                .pressed => s.buttonPressed,
                .disabled => s.buttonDisabled,
            };
            self.renderer.drawFilledRect(rect, bg);
            self.renderer.drawEnclosingRect(rect, s.windowBorder, 1);

            // Centered label
            const ts = self.renderer.measureString(lbl);
            const line_h: f32 = @floatFromInt(self.renderer.lineHeight() orelse 16);
            const tx: i32 = @intFromFloat(rect.l + (w - @as(f32, @floatFromInt(ts.x))) / 2.0);
            const ty: i32 = @intFromFloat(rect.t + (h - line_h) / 2.0);
            _ = self.renderer.drawString(lbl, .{ .x = tx, .y = ty });

            return .{ .clicked = clicked, .state = state };
        }

        // ----------------------------------------------------------
        // selectable / selectableList
        // ----------------------------------------------------------

        fn drawSelectable(
            self: *Self,
            uid: u64,
            lbl: []const u8,
            selected: bool,
            rect: RectF,
        ) bool {
            const s = &self.style;
            const over = self.testHot(uid, rect);
            var clicked = false;

            if (over and self.leftPressed) {
                self.activeId = uid;
                self.focusId = uid;
            }
            if (self.activeId == uid and over and self.leftReleased) {
                clicked = true;
            }

            const bg = if (self.activeId == uid)
                s.selectablePressed
            else if (selected)
                s.selectableSelected
            else if (over)
                s.selectableHover
            else
                s.selectableNormal;
            self.renderer.drawFilledRect(rect, bg);

            const pad_x: f32 = @floatFromInt(s.padding.x);
            const line_h: f32 = @floatFromInt(self.renderer.lineHeight() orelse 16);
            const text_clip = RectF{ .l = rect.l + pad_x, .t = rect.t, .r = rect.r - pad_x, .b = rect.b };
            _ = self.renderer.drawClippedString(lbl, .{
                .x = @intFromFloat(rect.l + pad_x),
                .y = @intFromFloat(rect.t + (rect.height() - line_h) / 2.0),
            }, text_clip);

            return clicked;
        }

        /// A single selectable row. Returns true when it is clicked.
        pub fn selectable(self: *Self, id: []const u8, lbl: []const u8, selected: bool) bool {
            const h: f32 = @floatFromInt(self.style.selectableHeight);
            const rect = self.allocWidget(self.contentWidth(), h);
            return self.drawSelectable(hashId(id), lbl, selected, rect);
        }

        /// Scrollable list of text rows with one optional selection.
        /// Returns true when `selected` changes.
        pub fn selectableList(
            self: *Self,
            id: []const u8,
            items: []const []const u8,
            selected: *?usize,
            scroll: *usize,
            areaHeight: f32,
        ) bool {
            const s = &self.style;
            const uid = hashId(id);
            const sb_uid = uid ^ 0x5343_0000_0000_0002;
            const rect = self.allocWidget(self.contentWidth(), areaHeight);
            const row_h: f32 = @floatFromInt(s.selectableHeight);
            const visible: usize = @max(1, @as(usize, @intFromFloat(@floor(areaHeight / row_h))));
            const scrollable = items.len > visible;
            const max_scroll = if (scrollable) items.len - visible else 0;
            const sb_w = s.scrollbarW;
            const row_r = if (scrollable) rect.r - sb_w - 2.0 else rect.r;

            if (scroll.* > max_scroll) scroll.* = max_scroll;
            if (selected.*) |idx| {
                if (idx >= items.len) selected.* = null;
            }

            const body_rect = RectF{ .l = rect.l, .t = rect.t, .r = row_r, .b = rect.b };
            const over_body = self.testHot(uid, body_rect);
            if (over_body) {
                if (self.pageUpPressed and scroll.* > 0) {
                    scroll.* -= 1;
                } else if (self.pageDownPressed and scroll.* < max_scroll) {
                    scroll.* += 1;
                }
                if (scrollable and self.scrollDelta != 0) {
                    if (self.scrollDelta > 0 and scroll.* > 0) {
                        const steps = @max(1, @as(usize, @intFromFloat(self.scrollDelta)));
                        scroll.* -= @min(scroll.*, steps);
                    } else if (self.scrollDelta < 0 and scroll.* < max_scroll) {
                        const steps = @max(1, @as(usize, @intFromFloat(-self.scrollDelta)));
                        scroll.* = @min(max_scroll, scroll.* + steps);
                    }
                    self.scrollConsumed = true;
                }
            }

            const sb_rect = RectF{ .l = rect.r - sb_w, .t = rect.t, .r = rect.r, .b = rect.b };
            if (scrollable) {
                const over_sb = self.testHot(sb_uid, sb_rect);
                if (over_sb and self.leftPressed) self.activeId = sb_uid;
                if (self.activeId == sb_uid and self.leftDown) {
                    const thumb_h = @max((areaHeight * @as(f32, @floatFromInt(visible))) /
                        @as(f32, @floatFromInt(items.len)), 12.0);
                    const travel = areaHeight - thumb_h;
                    const t = std.math.clamp((self.mousePos.y - sb_rect.t - thumb_h / 2.0) / travel, 0.0, 1.0);
                    scroll.* = @intFromFloat(t * @as(f32, @floatFromInt(max_scroll)));
                }
            }

            self.renderer.drawFilledRect(rect, s.textAreaBg);
            self.renderer.drawEnclosingRect(rect, s.textAreaBorder, 1);

            var changed = false;
            const end_idx = @min(scroll.* + visible, items.len);
            var y = rect.t;
            for (scroll.*..end_idx) |idx| {
                const row = RectF{ .l = rect.l + 1.0, .t = y + 1.0, .r = row_r - 1.0, .b = @min(y + row_h, rect.b - 1.0) };
                const is_selected = if (selected.*) |selected_idx| selected_idx == idx else false;
                if (self.drawSelectable(indexId(uid, idx), items[idx], is_selected, row)) {
                    if (!is_selected) {
                        selected.* = idx;
                        changed = true;
                    }
                }
                y += row_h;
            }

            if (scrollable) {
                const thumb_h = @max((areaHeight * @as(f32, @floatFromInt(visible))) /
                    @as(f32, @floatFromInt(items.len)), 12.0);
                const travel = areaHeight - thumb_h;
                const scroll_t = @as(f32, @floatFromInt(scroll.*)) / @as(f32, @floatFromInt(max_scroll));
                const thumb_t = sb_rect.t + scroll_t * travel;
                const thumb_rect = RectF{
                    .l = sb_rect.l + 1.0,
                    .t = thumb_t,
                    .r = sb_rect.r - 1.0,
                    .b = thumb_t + thumb_h,
                };
                self.renderer.drawFilledRect(sb_rect, s.scrollbarTrack);
                const thumb_col = if (self.activeId == sb_uid)
                    s.scrollbarThumbActive
                else if (self.hotId == sb_uid)
                    s.scrollbarThumbHover
                else
                    s.scrollbarThumb;
                self.renderer.drawFilledRect(thumb_rect, thumb_col);
            }

            return changed;
        }

        // ----------------------------------------------------------
        // checkbox / toggle
        // ----------------------------------------------------------

        /// Boolean toggle rendered as a checkbox and label.
        pub fn checkbox(self: *Self, id: []const u8, lbl: []const u8, checked: *bool) bool {
            const s = &self.style;
            const uid = hashId(id);
            const h: f32 = @floatFromInt(s.inputHeight);
            const rect = self.allocWidget(self.contentWidth(), h);
            const over = self.testHot(uid, rect);
            self.registerFocusable(uid);
            var changed = false;

            if (over and self.leftPressed) {
                self.activeId = uid;
                self.focusId = uid;
            }
            if (self.activeId == uid and over and self.leftReleased) {
                checked.* = !checked.*;
                changed = true;
            }

            const box_size: f32 = @floatFromInt(s.checkboxSize);
            const box = RectF{
                .l = rect.l,
                .t = rect.t + (h - box_size) / 2.0,
                .r = rect.l + box_size,
                .b = rect.t + (h + box_size) / 2.0,
            };
            self.renderer.drawFilledRect(box, s.checkboxBg);
            self.renderer.drawEnclosingRect(box, if (over) s.checkboxHover else s.checkboxBorder, 1);
            if (checked.*) {
                self.renderer.drawFilledRect(box.shrinkFrom(4.0), s.checkboxCheck);
            }

            const item_sp: f32 = @floatFromInt(s.itemSpacing);
            const line_h: f32 = @floatFromInt(self.renderer.lineHeight() orelse 16);
            _ = self.renderer.drawString(lbl, .{
                .x = @intFromFloat(box.r + item_sp * 2.0),
                .y = @intFromFloat(rect.t + (h - line_h) / 2.0),
            });

            return changed;
        }

        /// Alias for checkbox when a boolean is conceptually an option toggle.
        pub fn toggle(self: *Self, id: []const u8, lbl: []const u8, value: *bool) bool {
            return self.checkbox(id, lbl, value);
        }

        /// Give keyboard focus to a widget by ID.
        pub fn focusWidget(self: *Self, id: []const u8) void {
            self.focusId = hashId(id);
        }

        /// Returns true when a widget has keyboard focus.
        pub fn widgetFocused(self: *const Self, id: []const u8) bool {
            return self.focusId == hashId(id);
        }

        /// Sets the cursor for a focused text input. Useful after replacing an
        /// input buffer from caller-owned command history.
        pub fn setInputCursor(self: *Self, id: []const u8, pos: usize) void {
            const uid = hashId(id);
            self.editCursorId = uid;
            self.editCursorPos = pos;
        }

        fn insertTextAtCursor(self: *Self, uid: u64, buf: []u8, len: *usize, text_to_insert: []const u8) bool {
            if (buf.len == 0) return false;
            if (self.editCursorId != uid) {
                self.editCursorId = uid;
                self.editCursorPos = len.*;
            }

            const capacity = buf.len - 1;
            if (len.* >= capacity) return false;

            const insert_len = @min(text_to_insert.len, capacity - len.*);
            if (insert_len == 0) return false;

            var i = len.*;
            while (i > self.editCursorPos) : (i -= 1) {
                buf[i + insert_len - 1] = buf[i - 1];
            }
            @memcpy(buf[self.editCursorPos .. self.editCursorPos + insert_len], text_to_insert[0..insert_len]);
            len.* += insert_len;
            self.editCursorPos += insert_len;
            buf[len.*] = 0;
            return true;
        }

        // ----------------------------------------------------------
        // inputText
        // ----------------------------------------------------------

        /// Single-line text input. Returns true if the buffer changed this frame.
        /// `buf` is the text buffer; `len` is the current text length (in/out).
        pub fn inputText(
            self: *Self,
            id: []const u8,
            buf: []u8,
            len: *usize,
        ) bool {
            return self.inputTextEx(id, buf, len, .{}).changed;
        }

        /// Single-line text input with submit, clipboard, and history-key reporting.
        pub fn inputTextEx(
            self: *Self,
            id: []const u8,
            buf: []u8,
            len: *usize,
            opts: InputTextOptions,
        ) InputTextResult {
            const s = &self.style;
            const uid = hashId(id);
            const h: f32 = @floatFromInt(s.inputHeight);
            const w: f32 = self.contentWidth();
            const rect = self.allocWidget(w, h);

            self.registerFocusable(uid);

            var result = InputTextResult{};

            // Click to focus
            const over = self.testHot(uid, rect);
            if (over and self.leftPressed) {
                self.focusId = uid;
            }

            const focused = self.focusId == uid;
            result.focused = focused;

            if (focused) {
                // Initialize cursor when this widget first gains focus
                if (self.editCursorId != uid) {
                    self.editCursorId = uid;
                    self.editCursorPos = len.*;
                }

                if (len.* >= buf.len) len.* = if (buf.len > 0) buf.len - 1 else 0;
                if (self.editCursorPos > len.*) self.editCursorPos = len.*;

                if (opts.submitOnEnter and self.enterPressed) {
                    result.submitted = true;
                }

                if (opts.historyKeys) {
                    result.historyPrev = self.upArrowCount > 0;
                    result.historyNext = self.downArrowCount > 0;
                }

                if (self.homePressed) self.editCursorPos = 0;
                if (self.endPressed) self.editCursorPos = len.*;

                if (opts.clipboard and self.ctrlCPressed) {
                    if (self.clipboardWindow) |win| {
                        if (buf.len > 0) {
                            buf[len.*] = 0;
                            win.setClipboardString(buf[0..len.* :0]);
                        }
                    }
                    result.copied = true;
                }

                if (opts.clearOnCtrlL and self.ctrlLPressed) {
                    if (buf.len > 0) buf[0] = 0;
                    result.changed = result.changed or len.* > 0;
                    result.cleared = true;
                    len.* = 0;
                    self.editCursorPos = 0;
                }

                if (opts.clipboard and self.ctrlVPressed) {
                    if (self.clipboardWindow) |win| {
                        if (win.getClipboardString()) |clip| {
                            if (self.insertTextAtCursor(uid, buf, len, clip)) {
                                result.changed = true;
                                result.pasted = true;
                            }
                        }
                    }
                }

                // Move cursor with arrow keys
                var la = self.leftArrowCount;
                while (la > 0) : (la -= 1) {
                    if (self.editCursorPos > 0) self.editCursorPos -= 1;
                }
                var ra = self.rightArrowCount;
                while (ra > 0) : (ra -= 1) {
                    if (self.editCursorPos < len.*) self.editCursorPos += 1;
                }

                // Insert typed characters at cursor position
                for (self.textInput[0..self.textInputLen]) |c| {
                    if (self.insertTextAtCursor(uid, buf, len, (&[_]u8{c})[0..])) result.changed = true;
                }

                // Backspace: delete character before cursor
                var bs = self.backspaceCount;
                while (bs > 0 and self.editCursorPos > 0) : (bs -= 1) {
                    var i = self.editCursorPos - 1;
                    while (i < len.* - 1) : (i += 1) buf[i] = buf[i + 1];
                    len.* -= 1;
                    buf[len.*] = 0;
                    self.editCursorPos -= 1;
                    result.changed = true;
                }

                // Delete: delete character at cursor
                var del = self.deleteCount;
                while (del > 0 and self.editCursorPos < len.*) : (del -= 1) {
                    var i = self.editCursorPos;
                    while (i < len.* - 1) : (i += 1) buf[i] = buf[i + 1];
                    len.* -= 1;
                    buf[len.*] = 0;
                    result.changed = true;
                }

                // Clamp cursor in case buffer shrank externally
                if (self.editCursorPos > len.*) self.editCursorPos = len.*;
            }

            // Draw background + border
            self.renderer.drawFilledRect(rect, s.inputBg);
            const border_col = if (focused) s.inputBorderFocused else if (over) s.inputBorderHover else s.inputBorder;
            self.renderer.drawEnclosingRect(rect, border_col, 1);

            const pad_x: f32 = @floatFromInt(s.padding.x);
            const line_h: f32 = @floatFromInt(self.renderer.lineHeight() orelse 16);
            const ty: i32 = @intFromFloat(rect.t + (h - line_h) / 2.0);
            const text_clip = RectF{ .l = rect.l + pad_x, .t = rect.t, .r = rect.r - pad_x, .b = rect.b };
            _ = self.renderer.drawClippedString(buf[0..len.*], .{
                .x = @intFromFloat(rect.l + pad_x),
                .y = ty,
            }, text_clip);

            // Blinking cursor at editCursorPos
            if (focused) {
                const blink_on = (self.frame / 30) % 2 == 0;
                if (blink_on) {
                    const cursor_pos = if (self.editCursorId == uid) self.editCursorPos else len.*;
                    const pre_sz = self.renderer.measureString(buf[0..cursor_pos]);
                    const cx: f32 = rect.l + pad_x + @as(f32, @floatFromInt(pre_sz.x));
                    const cy: f32 = rect.t + (h - line_h) / 2.0;
                    self.renderer.drawFilledRect(RectF{
                        .l = cx,
                        .t = cy + line_h - 3.0,
                        .r = cx + 8.0,
                        .b = cy + line_h,
                    }, s.inputCursor);
                }
            }

            return result;
        }

        // ----------------------------------------------------------
        // inputInt
        // ----------------------------------------------------------

        fn beginIntEdit(self: *Self, uid: u64, value: i32) void {
            const str = std.fmt.bufPrint(&self.intEditBuf, "{}", .{value}) catch "0";
            self.intEditLen = str.len;
            self.intEditId = uid;
            self.intEditReplace = true;
            self.editCursorId = uid;
            self.editCursorPos = str.len;
        }

        /// Signed integer input. Typing after focus replaces the current value;
        /// backspace/delete and arrow keys edit with cursor support.
        pub fn inputInt(self: *Self, id: []const u8, value: *i32) bool {
            const s = &self.style;
            const uid = hashId(id);
            const h: f32 = @floatFromInt(s.inputHeight);
            const rect = self.allocWidget(self.contentWidth(), h);
            const over = self.testHot(uid, rect);

            self.registerFocusable(uid);

            if (over and self.leftPressed) {
                if (self.focusId != uid or self.intEditId != uid) {
                    self.beginIntEdit(uid, value.*);
                }
                self.focusId = uid;
            }

            const focused = self.focusId == uid;
            if (focused and self.intEditId != uid) {
                self.beginIntEdit(uid, value.*);
            }

            // Sync cursor if focus just arrived (from tab or external set)
            if (focused and self.editCursorId != uid) {
                self.editCursorId = uid;
                self.editCursorPos = self.intEditLen;
            }

            var changed = false;
            if (focused) {
                for (self.textInput[0..self.textInputLen]) |c| {
                    const valid = (c >= '0' and c <= '9') or
                        (c == '-' and (self.intEditReplace or self.intEditLen == 0));
                    if (!valid) continue;
                    if (self.intEditReplace) {
                        self.intEditLen = 0;
                        self.intEditReplace = false;
                        self.editCursorPos = 0;
                    }
                    // '-' only allowed at position 0
                    if (c == '-' and self.intEditLen != 0) continue;
                    if (self.intEditLen < self.intEditBuf.len) {
                        var i = self.intEditLen;
                        while (i > self.editCursorPos) : (i -= 1) {
                            self.intEditBuf[i] = self.intEditBuf[i - 1];
                        }
                        self.intEditBuf[self.editCursorPos] = c;
                        self.intEditLen += 1;
                        self.editCursorPos += 1;
                    }
                }

                if (self.backspaceCount + self.deleteCount > 0) self.intEditReplace = false;

                // Arrow keys (only meaningful once out of replace mode)
                var la = self.leftArrowCount;
                while (la > 0) : (la -= 1) {
                    if (self.editCursorPos > 0) self.editCursorPos -= 1;
                }
                var ra = self.rightArrowCount;
                while (ra > 0) : (ra -= 1) {
                    if (self.editCursorPos < self.intEditLen) self.editCursorPos += 1;
                }

                // Backspace: delete character before cursor
                var bs = self.backspaceCount;
                while (bs > 0 and self.editCursorPos > 0) : (bs -= 1) {
                    var i = self.editCursorPos - 1;
                    while (i < self.intEditLen - 1) : (i += 1) {
                        self.intEditBuf[i] = self.intEditBuf[i + 1];
                    }
                    self.intEditLen -= 1;
                    self.editCursorPos -= 1;
                }

                // Delete: delete character at cursor
                var del = self.deleteCount;
                while (del > 0 and self.editCursorPos < self.intEditLen) : (del -= 1) {
                    var i = self.editCursorPos;
                    while (i < self.intEditLen - 1) : (i += 1) {
                        self.intEditBuf[i] = self.intEditBuf[i + 1];
                    }
                    self.intEditLen -= 1;
                }

                if (self.intEditLen > 0 and
                    !(self.intEditLen == 1 and self.intEditBuf[0] == '-'))
                {
                    if (std.fmt.parseInt(i32, self.intEditBuf[0..self.intEditLen], 10)) |new_value| {
                        if (new_value != value.*) {
                            value.* = new_value;
                            changed = true;
                        }
                    } else |_| {}
                }
            }

            self.renderer.drawFilledRect(rect, s.inputBg);
            const border_col = if (focused) s.inputBorderFocused else if (over) s.inputBorderHover else s.inputBorder;
            self.renderer.drawEnclosingRect(rect, border_col, 1);

            var display_buf: [32]u8 = undefined;
            const value_str = if (focused)
                self.intEditBuf[0..self.intEditLen]
            else
                std.fmt.bufPrint(&display_buf, "{}", .{value.*}) catch "?";
            const pad_x: f32 = @floatFromInt(s.padding.x);
            const line_h: f32 = @floatFromInt(self.renderer.lineHeight() orelse 16);
            const ty: i32 = @intFromFloat(rect.t + (h - line_h) / 2.0);
            const text_clip = RectF{ .l = rect.l + pad_x, .t = rect.t, .r = rect.r - pad_x, .b = rect.b };
            _ = self.renderer.drawClippedString(value_str, .{
                .x = @intFromFloat(rect.l + pad_x),
                .y = ty,
            }, text_clip);

            // Blinking cursor at editCursorPos
            if (focused and (self.frame / 30) % 2 == 0) {
                const cursor_pos = if (self.editCursorId == uid) self.editCursorPos else self.intEditLen;
                const pre_sz = self.renderer.measureString(value_str[0..cursor_pos]);
                const cx: f32 = rect.l + pad_x + @as(f32, @floatFromInt(pre_sz.x));
                const cy: f32 = rect.t + (h - line_h) / 2.0;
                self.renderer.drawFilledRect(RectF{
                    .l = cx,
                    .t = cy + line_h - 3.0,
                    .r = cx + 8.0,
                    .b = cy + line_h,
                }, s.inputCursor);
            }

            return changed;
        }

        // ----------------------------------------------------------
        // textArea
        // ----------------------------------------------------------

        /// Scrollable read-only text area with a vertical scrollbar.
        /// `lines` is the full list of lines; `scroll` is the top visible line index.
        /// `areaHeight` is the pixel height of the area widget.
        pub fn textArea(
            self: *Self,
            id: []const u8,
            lines: []const []const u8,
            scroll: *usize,
            areaHeight: f32,
        ) void {
            const s = &self.style;
            const uid = hashId(id);
            const sb_uid = uid ^ 0x5343_0000_0000_0001; // scrollbar thumb ID
            const w: f32 = self.contentWidth();
            const rect = self.allocWidget(w, areaHeight);

            const line_h: i32 = self.renderer.lineHeight() orelse 16;
            const line_hf: f32 = @floatFromInt(line_h);
            const pad_y: f32 = @floatFromInt(s.padding.y);
            const pad_x: f32 = @floatFromInt(s.padding.x);
            const usable_h: f32 = @max(0.0, areaHeight - pad_y * 2.0);
            const lines_visible: usize = @intFromFloat(@floor(usable_h / line_hf));
            const scrollable = lines.len > lines_visible;

            // Scrollbar geometry
            const sb_w = s.scrollbarW;
            const sb_rect = RectF{ .l = rect.r - sb_w, .t = rect.t, .r = rect.r, .b = rect.b };
            const text_r = if (scrollable) rect.r - sb_w - 2.0 else rect.r;

            // Hit-test the text body for page-up/down and mouse wheel
            const body_rect = RectF{ .l = rect.l, .t = rect.t, .r = text_r, .b = rect.b };
            const over_body = self.testHot(uid, body_rect);

            if (over_body) {
                if (self.pageUpPressed and scroll.* > 0) {
                    scroll.* -= 1;
                } else if (self.pageDownPressed) {
                    if (scroll.* + lines_visible < lines.len) {
                        scroll.* += 1;
                    }
                }
                if (scrollable and self.scrollDelta != 0) {
                    const max_scroll_ta = lines.len - lines_visible;
                    if (self.scrollDelta > 0 and scroll.* > 0) {
                        const steps = @max(1, @as(usize, @intFromFloat(self.scrollDelta)));
                        scroll.* -= @min(scroll.*, steps);
                    } else if (self.scrollDelta < 0) {
                        const steps = @max(1, @as(usize, @intFromFloat(-self.scrollDelta)));
                        scroll.* = @min(max_scroll_ta, scroll.* + steps);
                    }
                    self.scrollConsumed = true;
                }
            }

            // Scrollbar interaction
            if (scrollable) {
                const max_scroll = lines.len - lines_visible;
                const over_sb = self.testHot(sb_uid, sb_rect);
                if (over_sb and self.leftPressed) self.activeId = sb_uid;
                if (self.activeId == sb_uid and self.leftDown) {
                    const thumb_h = @max((areaHeight * @as(f32, @floatFromInt(lines_visible))) /
                        @as(f32, @floatFromInt(lines.len)), 12.0);
                    const travel = areaHeight - thumb_h;
                    const my = self.mousePos.y;
                    const t = std.math.clamp((my - sb_rect.t - thumb_h / 2.0) / travel, 0.0, 1.0);
                    scroll.* = @intFromFloat(t * @as(f32, @floatFromInt(max_scroll)));
                }
                // Clamp scroll in case lines shrunk
                if (scroll.* > max_scroll) scroll.* = max_scroll;
            }

            // Background + border
            self.renderer.drawFilledRect(rect, s.textAreaBg);
            self.renderer.drawEnclosingRect(rect, s.textAreaBorder, 1);

            // Draw visible lines clipped to the text column so long lines don't
            // bleed into the scrollbar or past the border.
            const line_clip = RectF{ .l = rect.l + pad_x, .t = rect.t, .r = text_r - pad_x, .b = rect.b };
            var draw_y: i32 = @intFromFloat(rect.t + pad_y);
            const start = scroll.*;
            const end_idx = @min(start + lines_visible, lines.len);
            for (start..end_idx) |i| {
                _ = self.renderer.drawClippedString(lines[i], .{
                    .x = @intFromFloat(rect.l + pad_x),
                    .y = draw_y,
                }, line_clip);
                draw_y += line_h;
            }

            // Draw scrollbar
            if (scrollable) {
                const max_scroll = lines.len - lines_visible;
                const thumb_h = @max((areaHeight * @as(f32, @floatFromInt(lines_visible))) /
                    @as(f32, @floatFromInt(lines.len)), 12.0);
                const scroll_t = if (max_scroll > 0)
                    @as(f32, @floatFromInt(scroll.*)) / @as(f32, @floatFromInt(max_scroll))
                else
                    0.0;
                const travel = areaHeight - thumb_h;
                const thumb_t = sb_rect.t + scroll_t * travel;
                const thumb_rect = RectF{
                    .l = sb_rect.l + 1.0,
                    .t = thumb_t,
                    .r = sb_rect.r - 1.0,
                    .b = thumb_t + thumb_h,
                };

                self.renderer.drawFilledRect(sb_rect, s.scrollbarTrack);
                const is_active = self.activeId == sb_uid;
                const is_hot = self.hotId == sb_uid;
                const thumb_col = if (is_active) s.scrollbarThumbActive else if (is_hot) s.scrollbarThumbHover else s.scrollbarThumb;
                self.renderer.drawFilledRect(thumb_rect, thumb_col);
            }
        }

        // ----------------------------------------------------------
        // slider
        // ----------------------------------------------------------

        /// Horizontal slider. `value` is clamped to [minVal, maxVal].
        /// Returns true if the value changed this frame.
        pub fn slider(
            self: *Self,
            id: []const u8,
            value: *f32,
            minVal: f32,
            maxVal: f32,
        ) bool {
            const s = &self.style;
            const uid = hashId(id);
            const h: f32 = @floatFromInt(s.sliderHeight);
            const w: f32 = self.contentWidth();
            const rect = self.allocWidget(w, h);

            const thumb_w: f32 = @floatFromInt(s.sliderThumbW);
            const track_l = rect.l + thumb_w / 2.0;
            const track_r = rect.r - thumb_w / 2.0;
            const track_range = track_r - track_l;
            const val_range = maxVal - minVal;

            self.registerFocusable(uid);
            const over = self.testHot(uid, rect);

            if (over and self.leftPressed) {
                self.activeId = uid;
                self.focusId = uid;
            }

            var changed = false;
            if (self.activeId == uid and self.leftDown) {
                const mx = self.mousePos.x;
                const t = std.math.clamp((mx - track_l) / track_range, 0.0, 1.0);
                const new_val = minVal + t * val_range;
                if (new_val != value.*) {
                    value.* = new_val;
                    changed = true;
                }
            }

            // Compute thumb center from current value
            const t = std.math.clamp((value.* - minVal) / val_range, 0.0, 1.0);
            const thumb_cx = track_l + t * track_range;
            const track_cy = rect.t + h / 2.0;
            const track_h: f32 = 4.0;

            // Track background
            self.renderer.drawFilledRect(rect, s.sliderTrack);
            self.renderer.drawEnclosingRect(rect, s.windowBorder, 1);

            // Filled portion (left of thumb)
            self.renderer.drawFilledRect(.{
                .l = track_l,
                .t = track_cy - track_h / 2.0,
                .r = thumb_cx,
                .b = track_cy + track_h / 2.0,
            }, s.sliderFill);

            // Thumb
            const thumb_col = if (self.activeId == uid)
                s.sliderThumbActive
            else if (over)
                s.sliderThumbHover
            else
                s.sliderThumb;

            self.renderer.drawFilledRect(.{
                .l = thumb_cx - thumb_w / 2.0,
                .t = rect.t + 2.0,
                .r = thumb_cx + thumb_w / 2.0,
                .b = rect.b - 2.0,
            }, thumb_col);

            // Value label (right-aligned inside the track)
            var val_buf: [24]u8 = undefined;
            const val_str = std.fmt.bufPrint(&val_buf, "{d:.2}", .{value.*}) catch "?";
            const ts = self.renderer.measureString(val_str);
            const line_h: f32 = @floatFromInt(self.renderer.lineHeight() orelse 16);
            _ = self.renderer.drawString(val_str, .{
                .x = @intFromFloat(rect.r - @as(f32, @floatFromInt(ts.x)) - @as(f32, @floatFromInt(s.padding.x))),
                .y = @intFromFloat(track_cy - line_h / 2.0),
            });

            return changed;
        }
    };
}
