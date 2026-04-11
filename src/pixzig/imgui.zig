//! Immediate mode GUI for pixzig.
//!
//! Call ui.update() once per engine update step (in app.update()).
//! Call ui.begin() / widgets / ui.end() once per render frame (in app.render()).
//!
//! Usage:
//!   // In app.update():
//!   self.ui.update();
//!
//!   // In app.render(), inside renderer.begin()/end():
//!   self.ui.begin();
//!   self.ui.beginWindow("win", "My Window", rect);
//!   self.ui.label("Hello!");
//!   if (self.ui.button("btn1", "Click Me")) { ... }
//!   _ = self.ui.inputText("input1", &buf, &buf_len);
//!   self.ui.textArea("log", log_lines.items, &scroll, 120);
//!   self.ui.endWindow();
//!   self.ui.end();

const std = @import("std");
const TextRenderer = @import("./renderer/text.zig").TextRenderer;
const ShapeBatchQueue = @import("./renderer/shape.zig").ShapeBatchQueue;
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
    window_bg: Color = Color.from(30, 30, 35, 230),
    window_border: Color = Color.from(80, 80, 90, 255),
    window_title_bg: Color = Color.from(50, 50, 70, 255),
    title_text: Color = Color.from(230, 230, 255, 255),
    button_normal: Color = Color.from(60, 60, 80, 255),
    button_hover: Color = Color.from(90, 90, 120, 255),
    button_pressed: Color = Color.from(40, 40, 60, 255),
    button_disabled: Color = Color.from(45, 45, 50, 200),
    button_text: Color = Color.from(220, 220, 220, 255),
    button_disabled_text: Color = Color.from(100, 100, 100, 255),
    input_bg: Color = Color.from(20, 20, 25, 255),
    input_border: Color = Color.from(70, 70, 80, 255),
    input_border_hover: Color = Color.from(100, 100, 120, 255),
    input_border_focused: Color = Color.from(100, 130, 200, 255),
    input_text: Color = Color.from(220, 220, 220, 255),
    input_cursor: Color = Color.from(180, 220, 255, 200),
    label_text: Color = Color.from(220, 220, 220, 255),
    text_area_bg: Color = Color.from(15, 15, 20, 255),
    text_area_border: Color = Color.from(60, 60, 70, 255),
    slider_track: Color = Color.from(30, 30, 40, 255),
    slider_fill: Color = Color.from(60, 100, 160, 255),
    slider_thumb: Color = Color.from(100, 150, 220, 255),
    slider_thumb_hover: Color = Color.from(130, 180, 255, 255),
    slider_thumb_active: Color = Color.from(80, 120, 200, 255),
    slider_text: Color = Color.from(220, 220, 220, 255),
    padding: Vec2I = .{ .x = 8, .y = 6 },
    item_spacing: i32 = 4,
    title_height: i32 = 22,
    button_height: i32 = 24,
    input_height: i32 = 24,
    slider_height: i32 = 24,
    slider_thumb_w: i32 = 10,
};

// ============================================================
// ButtonState / ButtonResult
// ============================================================

pub const ButtonState = enum { normal, hover, pressed, disabled };

pub const ButtonResult = struct {
    clicked: bool,
    state: ButtonState,
};

// ============================================================
// Internal per-window layout state
// ============================================================

const WindowCtx = struct {
    rect: RectF,
    content_y: f32, // next widget baseline Y
    last_x: f32, // top-left of last placed widget
    last_y: f32,
    last_w: f32, // size of last placed widget
    last_h: f32,
    same_line: bool, // if true, next widget placed to the right
};

// ============================================================
// UiContext
// ============================================================

pub const UiContext = struct {
    hot_id: u64, // widget the mouse is currently over
    active_id: u64, // widget being clicked/dragged
    focus_id: u64, // widget with keyboard focus
    frame: u64, // frame counter (used for cursor blink)

    mouse: *Mouse,
    keyboard: *Keyboard,
    shapes: *ShapeBatchQueue,
    text: *TextRenderer,
    style: Style,
    /// Scale factor from engine (logical → render pixels).
    scale_factor: f32,

    win_stack: [8]WindowCtx,
    win_depth: usize,

    // ----------------------------------------------------------
    // Input accumulated by update() — consumed each render frame
    // ----------------------------------------------------------

    /// Typed characters accumulated across all update() calls this frame.
    text_input: [64]u8,
    text_input_len: usize,
    /// Number of backspace presses accumulated this frame.
    backspace_count: usize,
    /// Number of delete presses accumulated this frame.
    delete_count: usize,
    /// Whether page-up was pressed in any update step this frame.
    page_up_pressed: bool,
    /// Whether page-down was pressed in any update step this frame.
    page_down_pressed: bool,

    // ----------------------------------------------------------
    // Mouse state snapshotted by update()
    // ----------------------------------------------------------

    /// Mouse position in render coordinates (already scaled).
    mouse_pos: Vec2F,
    /// True if the left button was pressed in any update step this frame.
    left_pressed: bool,
    /// True if the left button was released in any update step this frame.
    left_released: bool,
    /// True if the left button is currently held.
    left_down: bool,

    pub fn init(
        mouse: *Mouse,
        keyboard: *Keyboard,
        shapes: *ShapeBatchQueue,
        text: *TextRenderer,
        scale_factor: f32,
    ) UiContext {
        return .{
            .hot_id = 0,
            .active_id = 0,
            .focus_id = 0,
            .frame = 0,
            .mouse = mouse,
            .keyboard = keyboard,
            .shapes = shapes,
            .text = text,
            .style = Style{},
            .scale_factor = scale_factor,
            .win_stack = undefined,
            .win_depth = 0,
            .text_input = undefined,
            .text_input_len = 0,
            .backspace_count = 0,
            .delete_count = 0,
            .page_up_pressed = false,
            .page_down_pressed = false,
            .mouse_pos = .{ .x = 0, .y = 0 },
            .left_pressed = false,
            .left_released = false,
            .left_down = false,
        };
    }

    // ----------------------------------------------------------
    // update() — call once per engine update step in app.update()
    // ----------------------------------------------------------

    /// Latch keyboard and mouse input for this update step.
    /// Must be called from app.update(), after mouse.update().
    pub fn update(self: *UiContext) void {
        // Store raw GLFW logical pixel coordinates (0..window_width, 0..window_height).
        // testHot() compensates for scale_factor when comparing against render rects.
        const mp = self.mouse.pos();
        self.mouse_pos = mp;
        self.left_down = self.mouse.down(.left);
        if (self.mouse.pressed(.left)) self.left_pressed = true;
        if (self.mouse.released(.left)) self.left_released = true;

        // Accumulate typed characters
        var buf: [8]u8 = undefined;
        const n = self.keyboard.text(&buf);
        for (buf[0..n]) |c| {
            if (self.text_input_len < self.text_input.len) {
                self.text_input[self.text_input_len] = c;
                self.text_input_len += 1;
            }
        }

        // Accumulate special key presses
        if (self.keyboard.pressed(.backspace)) self.backspace_count += 1;
        if (self.keyboard.pressed(.delete)) self.delete_count += 1;
        if (self.keyboard.pressed(.page_up)) self.page_up_pressed = true;
        if (self.keyboard.pressed(.page_down)) self.page_down_pressed = true;
    }

    // ----------------------------------------------------------
    // Frame lifecycle — begin/end wrap all widget calls in render()
    // ----------------------------------------------------------

    /// Call at the start of each render frame before any widgets.
    pub fn begin(self: *UiContext) void {
        self.hot_id = 0;
        self.frame +%= 1;
    }

    /// Call at the end of each render frame after all widgets.
    /// Clears accumulated input state for the next frame.
    pub fn end(self: *UiContext) void {
        // Handle focus: click on empty space clears it
        if (self.left_pressed and self.hot_id == 0) {
            self.focus_id = 0;
        }
        // Release active widget when mouse released
        if (self.left_released) {
            self.active_id = 0;
        }

        // Clear accumulated input for next frame
        self.text_input_len = 0;
        self.backspace_count = 0;
        self.delete_count = 0;
        self.page_up_pressed = false;
        self.page_down_pressed = false;
        self.left_pressed = false;
        self.left_released = false;
    }

    // ----------------------------------------------------------
    // Window
    // ----------------------------------------------------------

    /// Begin a window. Draws title bar and background. Must be matched with endWindow().
    pub fn beginWindow(
        self: *UiContext,
        id: []const u8,
        title: []const u8,
        rect: RectF,
    ) void {
        const s = &self.style;
        const title_h: f32 = @floatFromInt(s.title_height);
        const pad_x: f32 = @floatFromInt(s.padding.x);
        const pad_y: f32 = @floatFromInt(s.padding.y);

        // Background
        self.shapes.drawFilledRect(rect, s.window_bg);
        self.shapes.drawEnclosingRect(rect, s.window_border, 1);

        // Title bar
        const title_rect = RectF{
            .l = rect.l,
            .t = rect.t,
            .r = rect.r,
            .b = rect.t + title_h,
        };
        self.shapes.drawFilledRect(title_rect, s.window_title_bg);

        // Title text — vertically centered in title bar
        const line_h: f32 = if (self.text.atlas) |a| @floatFromInt(a.maxY) else 16;
        _ = self.text.drawString(title, .{
            .x = @intFromFloat(rect.l + pad_x),
            .y = @intFromFloat(rect.t + (title_h - line_h) / 2.0),
        });

        _ = id;

        // Push window context
        std.debug.assert(self.win_depth < self.win_stack.len);
        self.win_stack[self.win_depth] = .{
            .rect = rect,
            .content_y = rect.t + title_h + pad_y,
            .last_x = rect.l + pad_x,
            .last_y = rect.t + title_h + pad_y,
            .last_w = 0,
            .last_h = 0,
            .same_line = false,
        };
        self.win_depth += 1;
    }

    /// End the current window.
    pub fn endWindow(self: *UiContext) void {
        std.debug.assert(self.win_depth > 0);
        self.win_depth -= 1;
    }

    // ----------------------------------------------------------
    // Layout helpers
    // ----------------------------------------------------------

    fn curWin(self: *UiContext) *WindowCtx {
        return &self.win_stack[self.win_depth - 1];
    }

    /// Allocate a rect for the next widget, advancing the layout cursor.
    fn allocWidget(self: *UiContext, w: f32, h: f32) RectF {
        const win = self.curWin();
        const pad_x: f32 = @floatFromInt(self.style.padding.x);
        const item_sp: f32 = @floatFromInt(self.style.item_spacing);

        var x: f32 = undefined;
        var y: f32 = undefined;

        if (win.same_line) {
            x = win.last_x + win.last_w + item_sp;
            y = win.last_y;
            win.same_line = false;
        } else {
            x = win.rect.l + pad_x;
            y = win.content_y;
        }

        const rect = RectF{ .l = x, .t = y, .r = x + w, .b = y + h };

        win.last_x = x;
        win.last_y = y;
        win.last_w = w;
        win.last_h = h;

        const new_bottom = y + h + item_sp;
        if (new_bottom > win.content_y) {
            win.content_y = new_bottom;
        }

        return rect;
    }

    /// Place the next widget on the same line as the previous widget.
    pub fn sameLine(self: *UiContext) void {
        self.curWin().same_line = true;
    }

    /// Add extra vertical space.
    pub fn spacing(self: *UiContext) void {
        const win = self.curWin();
        win.content_y += @as(f32, @floatFromInt(self.style.item_spacing)) * 2.0;
    }

    fn contentWidth(self: *UiContext) f32 {
        const win = self.curWin();
        const pad_x: f32 = @floatFromInt(self.style.padding.x);
        return win.rect.r - win.rect.l - pad_x * 2.0;
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

    // ----------------------------------------------------------
    // Mouse hit test — uses the position snapshotted in update()
    // ----------------------------------------------------------

    fn testHot(self: *UiContext, id: u64, rect: RectF) bool {
        // mouse_pos is in GLFW logical pixels [0, window_w].
        // Widget rects are in render pixels [0, window_w * sf].
        // Multiply cursor by sf to bring it into render space for comparison.
        const sf = self.scale_factor;
        const mp = Vec2F{ .x = self.mouse_pos.x * sf, .y = self.mouse_pos.y * sf };
        const over = mp.x >= rect.l and mp.x < rect.r and
            mp.y >= rect.t and mp.y < rect.b;
        if (over) self.hot_id = id;
        return over;
    }

    // ----------------------------------------------------------
    // label
    // ----------------------------------------------------------

    pub fn label(self: *UiContext, str: []const u8) void {
        const s = &self.style;
        const line_h: i32 = if (self.text.atlas) |a| a.maxY else 16;
        const h: f32 = @floatFromInt(line_h + s.item_spacing);
        const w: f32 = self.contentWidth();
        const rect = self.allocWidget(w, h);
        _ = self.text.drawString(str, .{
            .x = @intFromFloat(rect.l),
            .y = @intFromFloat(rect.t),
        });
    }

    // ----------------------------------------------------------
    // button / buttonEx
    // ----------------------------------------------------------

    /// Draw a button. Returns true if clicked this frame.
    pub fn button(self: *UiContext, id: []const u8, lbl: []const u8) bool {
        return self.buttonEx(id, lbl, false).clicked;
    }

    /// Draw a button with explicit disabled state.
    pub fn buttonEx(
        self: *UiContext,
        id: []const u8,
        lbl: []const u8,
        disabled: bool,
    ) ButtonResult {
        const s = &self.style;
        const uid = hashId(id);
        const h: f32 = @floatFromInt(s.button_height);
        const w: f32 = self.contentWidth();
        const rect = self.allocWidget(w, h);

        var state = ButtonState.normal;
        var clicked = false;

        if (disabled) {
            state = .disabled;
        } else {
            const over = self.testHot(uid, rect);
            if (over and self.left_pressed) {
                self.active_id = uid;
                self.focus_id = uid;
            }
            if (self.active_id == uid) {
                state = .pressed;
                if (over and self.left_released) {
                    clicked = true;
                }
            } else if (over) {
                state = .hover;
            }
        }

        const bg = switch (state) {
            .normal => s.button_normal,
            .hover => s.button_hover,
            .pressed => s.button_pressed,
            .disabled => s.button_disabled,
        };
        self.shapes.drawFilledRect(rect, bg);
        self.shapes.drawEnclosingRect(rect, s.window_border, 1);

        // Centered label
        const ts = self.text.measureString(lbl);
        const line_h: f32 = if (self.text.atlas) |a| @floatFromInt(a.maxY) else 16;
        const tx: i32 = @intFromFloat(rect.l + (w - @as(f32, @floatFromInt(ts.x))) / 2.0);
        const ty: i32 = @intFromFloat(rect.t + (h - line_h) / 2.0);
        _ = self.text.drawString(lbl, .{ .x = tx, .y = ty });

        return .{ .clicked = clicked, .state = state };
    }

    // ----------------------------------------------------------
    // inputText
    // ----------------------------------------------------------

    /// Single-line text input. Returns true if the buffer changed this frame.
    /// `buf` is the text buffer; `len` is the current text length (in/out).
    pub fn inputText(
        self: *UiContext,
        id: []const u8,
        buf: []u8,
        len: *usize,
    ) bool {
        const s = &self.style;
        const uid = hashId(id);
        const h: f32 = @floatFromInt(s.input_height);
        const w: f32 = self.contentWidth();
        const rect = self.allocWidget(w, h);

        var changed = false;

        // Click to focus
        const over = self.testHot(uid, rect);
        if (over and self.left_pressed) {
            self.focus_id = uid;
        }

        const focused = self.focus_id == uid;

        if (focused) {
            // Consume accumulated typed characters
            for (self.text_input[0..self.text_input_len]) |c| {
                if (len.* < buf.len - 1) {
                    buf[len.*] = c;
                    len.* += 1;
                    changed = true;
                }
            }
            // Consume accumulated backspaces
            var bs = self.backspace_count;
            while (bs > 0 and len.* > 0) : (bs -= 1) {
                len.* -= 1;
                buf[len.*] = 0;
                changed = true;
            }
            // Consume accumulated deletes (treat as backspace from end)
            var del = self.delete_count;
            while (del > 0 and len.* > 0) : (del -= 1) {
                len.* -= 1;
                buf[len.*] = 0;
                changed = true;
            }
        }

        // Draw background + border
        self.shapes.drawFilledRect(rect, s.input_bg);
        const border_col = if (focused) s.input_border_focused else if (over) s.input_border_hover else s.input_border;
        self.shapes.drawEnclosingRect(rect, border_col, 1);

        // Draw text
        const pad_x: f32 = @floatFromInt(s.padding.x);
        const line_h: f32 = if (self.text.atlas) |a| @floatFromInt(a.maxY) else 16;
        const ty: i32 = @intFromFloat(rect.t + (h - line_h) / 2.0);
        _ = self.text.drawString(buf[0..len.*], .{
            .x = @intFromFloat(rect.l + pad_x),
            .y = ty,
        });

        // Blinking cursor
        if (focused) {
            const blink_on = (self.frame / 30) % 2 == 0;
            if (blink_on) {
                const pre_sz = self.text.measureString(buf[0..len.*]);
                const cx: f32 = rect.l + pad_x + @as(f32, @floatFromInt(pre_sz.x));
                const cy: f32 = rect.t + (h - line_h) / 2.0;
                self.shapes.drawFilledRect(RectF{
                    .l = cx,
                    .t = cy + line_h - 3.0,
                    .r = cx + 8.0,
                    .b = cy + line_h,
                }, s.input_cursor);
            }
        }

        return changed;
    }

    // ----------------------------------------------------------
    // textArea
    // ----------------------------------------------------------

    /// Scrollable read-only text area.
    /// `lines` is the full list of lines; `scroll` is the top visible line index.
    /// `area_height` is the pixel height of the area widget.
    pub fn textArea(
        self: *UiContext,
        id: []const u8,
        lines: []const []const u8,
        scroll: *usize,
        area_height: f32,
    ) void {
        const s = &self.style;
        const uid = hashId(id);
        const w: f32 = self.contentWidth();
        const rect = self.allocWidget(w, area_height);

        _ = self.testHot(uid, rect);

        const line_h: i32 = if (self.text.atlas) |a| a.maxY else 16;
        const pad_y: f32 = @floatFromInt(s.padding.y);
        const usable_h: f32 = area_height - pad_y * 2.0;
        const lines_visible: usize = @intFromFloat(@floor(usable_h / @as(f32, @floatFromInt(line_h))));

        // Page Up/Down scrolling when hovered
        if (self.hot_id == uid) {
            if (self.page_up_pressed and scroll.* > 0) {
                scroll.* -= 1;
            } else if (self.page_down_pressed) {
                if (scroll.* + lines_visible < lines.len) {
                    scroll.* += 1;
                }
            }
        }

        // Background + border
        self.shapes.drawFilledRect(rect, s.text_area_bg);
        self.shapes.drawEnclosingRect(rect, s.text_area_border, 1);

        // Draw visible lines
        const pad_x: f32 = @floatFromInt(s.padding.x);
        var draw_y: i32 = @intFromFloat(rect.t + pad_y);
        const start = scroll.*;
        const end_idx = @min(start + lines_visible, lines.len);
        for (start..end_idx) |i| {
            _ = self.text.drawString(lines[i], .{
                .x = @intFromFloat(rect.l + pad_x),
                .y = draw_y,
            });
            draw_y += line_h;
        }
    }

    // ----------------------------------------------------------
    // slider
    // ----------------------------------------------------------

    /// Horizontal slider. `value` is clamped to [min_val, max_val].
    /// Returns true if the value changed this frame.
    pub fn slider(
        self: *UiContext,
        id: []const u8,
        value: *f32,
        min_val: f32,
        max_val: f32,
    ) bool {
        const s = &self.style;
        const uid = hashId(id);
        const h: f32 = @floatFromInt(s.slider_height);
        const w: f32 = self.contentWidth();
        const rect = self.allocWidget(w, h);

        const thumb_w: f32 = @floatFromInt(s.slider_thumb_w);
        const track_l = rect.l + thumb_w / 2.0;
        const track_r = rect.r - thumb_w / 2.0;
        const track_range = track_r - track_l;
        const val_range = max_val - min_val;

        const over = self.testHot(uid, rect);

        if (over and self.left_pressed) {
            self.active_id = uid;
            self.focus_id = uid;
        }

        var changed = false;
        if (self.active_id == uid and self.left_down) {
            const sf = self.scale_factor;
            const mx = self.mouse_pos.x * sf;
            const t = std.math.clamp((mx - track_l) / track_range, 0.0, 1.0);
            const new_val = min_val + t * val_range;
            if (new_val != value.*) {
                value.* = new_val;
                changed = true;
            }
        }

        // Compute thumb center from current value
        const t = std.math.clamp((value.* - min_val) / val_range, 0.0, 1.0);
        const thumb_cx = track_l + t * track_range;
        const track_cy = rect.t + h / 2.0;
        const track_h: f32 = 4.0;

        // Track background
        self.shapes.drawFilledRect(rect, s.slider_track);
        self.shapes.drawEnclosingRect(rect, s.window_border, 1);

        // Filled portion (left of thumb)
        self.shapes.drawFilledRect(.{
            .l = track_l,
            .t = track_cy - track_h / 2.0,
            .r = thumb_cx,
            .b = track_cy + track_h / 2.0,
        }, s.slider_fill);

        // Thumb
        const thumb_col = if (self.active_id == uid)
            s.slider_thumb_active
        else if (over)
            s.slider_thumb_hover
        else
            s.slider_thumb;

        self.shapes.drawFilledRect(.{
            .l = thumb_cx - thumb_w / 2.0,
            .t = rect.t + 2.0,
            .r = thumb_cx + thumb_w / 2.0,
            .b = rect.b - 2.0,
        }, thumb_col);

        // Value label (right-aligned inside the track)
        var val_buf: [24]u8 = undefined;
        const val_str = std.fmt.bufPrint(&val_buf, "{d:.2}", .{value.*}) catch "?";
        const ts = self.text.measureString(val_str);
        const line_h: f32 = if (self.text.atlas) |a| @floatFromInt(a.maxY) else 16;
        _ = self.text.drawString(val_str, .{
            .x = @intFromFloat(rect.r - @as(f32, @floatFromInt(ts.x)) - @as(f32, @floatFromInt(s.padding.x))),
            .y = @intFromFloat(track_cy - line_h / 2.0),
        });

        return changed;
    }
};
