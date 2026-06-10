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
//!   self.ui.beginWindow("win", "My Window", &rect);
//!   self.ui.label("Hello!");
//!   self.ui.image(texture, .{ .x = 64, .y = 64 });
//!   if (self.ui.button("btn1", "Click Me")) { ... }
//!   _ = self.ui.inputText("input1", &buf, &buf_len);
//!   _ = self.ui.inputInt("frame_ms", &frame_ms);
//!   _ = self.ui.checkbox("loop", "Loop", &loop);
//!   _ = self.ui.selectableList("sprites", names, &selection, &scroll, 120);
//!   self.ui.textArea("log", log_lines.items, &scroll, 120);
//!   self.ui.endWindow();
//!   self.ui.end();

const std = @import("std");
const TextRenderer = @import("./renderer/text.zig").TextRenderer;
const ShapeBatchQueue = @import("./renderer/shape.zig").ShapeBatchQueue;
const SpriteBatchQueue = @import("./renderer/sprite_batch.zig").SpriteBatchQueue;
const Texture = @import("./renderer/textures.zig").Texture;
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
    window_resize_handle: Color = Color.from(100, 100, 120, 255),
    window_resize_handle_hover: Color = Color.from(135, 155, 205, 255),
    title_text: Color = Color.from(230, 230, 255, 255),
    button_normal: Color = Color.from(60, 60, 80, 255),
    button_hover: Color = Color.from(90, 90, 120, 255),
    button_pressed: Color = Color.from(40, 40, 60, 255),
    button_disabled: Color = Color.from(45, 45, 50, 200),
    button_text: Color = Color.from(220, 220, 220, 255),
    button_disabled_text: Color = Color.from(100, 100, 100, 255),
    selectable_normal: Color = Color.from(35, 35, 42, 255),
    selectable_hover: Color = Color.from(65, 65, 85, 255),
    selectable_pressed: Color = Color.from(45, 55, 78, 255),
    selectable_selected: Color = Color.from(60, 95, 145, 255),
    selectable_text: Color = Color.from(220, 220, 220, 255),
    checkbox_bg: Color = Color.from(20, 20, 25, 255),
    checkbox_border: Color = Color.from(100, 100, 120, 255),
    checkbox_hover: Color = Color.from(130, 150, 190, 255),
    checkbox_check: Color = Color.from(95, 155, 230, 255),
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
    resize_handle_size: i32 = 14,
    min_window_size: Vec2I = .{ .x = 120, .y = 70 },
    button_height: i32 = 24,
    selectable_height: i32 = 24,
    checkbox_size: i32 = 18,
    input_height: i32 = 24,
    slider_height: i32 = 24,
    slider_thumb_w: i32 = 10,
    scrollbar_w: f32 = 8,
    scrollbar_track: Color = Color.from(20, 20, 28, 255),
    scrollbar_thumb: Color = Color.from(80, 80, 100, 255),
    scrollbar_thumb_hover: Color = Color.from(110, 110, 140, 255),
    scrollbar_thumb_active: Color = Color.from(60, 60, 80, 255),
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
    sprites: *SpriteBatchQueue,
    images: *SpriteBatchQueue,
    shapes: *ShapeBatchQueue,
    text: *TextRenderer,
    style: Style,

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

    /// Scratch text used by the currently focused integer input.
    int_edit_buf: [32]u8,
    int_edit_len: usize,
    int_edit_id: u64,
    int_edit_replace: bool,

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
    window_drag_offset: Vec2F,
    window_resize_start_mouse: Vec2F,
    window_resize_start_size: Vec2F,

    pub fn init(
        mouse: *Mouse,
        keyboard: *Keyboard,
        sprites: *SpriteBatchQueue,
        images: *SpriteBatchQueue,
        shapes: *ShapeBatchQueue,
        text: *TextRenderer,
    ) UiContext {
        return .{
            .hot_id = 0,
            .active_id = 0,
            .focus_id = 0,
            .frame = 0,
            .mouse = mouse,
            .keyboard = keyboard,
            .sprites = sprites,
            .images = images,
            .shapes = shapes,
            .text = text,
            .style = Style{},
            .win_stack = undefined,
            .win_depth = 0,
            .text_input = undefined,
            .text_input_len = 0,
            .backspace_count = 0,
            .delete_count = 0,
            .page_up_pressed = false,
            .page_down_pressed = false,
            .int_edit_buf = undefined,
            .int_edit_len = 0,
            .int_edit_id = 0,
            .int_edit_replace = false,
            .mouse_pos = .{ .x = 0, .y = 0 },
            .left_pressed = false,
            .left_released = false,
            .left_down = false,
            .window_drag_offset = .{ .x = 0, .y = 0 },
            .window_resize_start_mouse = .{ .x = 0, .y = 0 },
            .window_resize_start_size = .{ .x = 0, .y = 0 },
        };
    }

    // ----------------------------------------------------------
    // update() — call once per engine update step in app.update()
    // ----------------------------------------------------------

    /// Latch keyboard and mouse input for this update step.
    /// Must be called from app.update(), after mouse.update().
    pub fn update(self: *UiContext) void {
        // mouse.pos() already returns logical game coordinates ((-1,-1) when
        // the cursor is in a letterbox/pillarbox region), so no extra
        // conversion is needed here.
        self.mouse_pos = self.mouse.pos();
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
        // Scene sprites should be behind all window layers.
        self.sprites.flush();
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

    /// Resize and place a window against one edge of the logical screen.
    /// `percent` controls width for left/right and height for up/down.
    pub fn resizeWindowToSide(self: *UiContext, rect: *RectF, side: WindowSide, percent: f32, screen_size: Vec2I) void {
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

    /// Begin a draggable and bottom-right resizable window.
    /// `rect` stores the persistent bounds and must be matched with endWindow().
    pub fn beginWindow(
        self: *UiContext,
        id: []const u8,
        title: []const u8,
        rect: *RectF,
    ) void {
        const s = &self.style;
        const title_h: f32 = @floatFromInt(s.title_height);
        const pad_x: f32 = @floatFromInt(s.padding.x);
        const pad_y: f32 = @floatFromInt(s.padding.y);
        const resize_size: f32 = @floatFromInt(s.resize_handle_size);
        const uid = hashId(id);
        const move_uid = uid ^ 0x5749_4e44_4f57_0001;
        const resize_uid = uid ^ 0x5749_4e44_4f57_0002;

        var resize_rect = RectF{
            .l = rect.r - resize_size,
            .t = rect.b - resize_size,
            .r = rect.r,
            .b = rect.b,
        };
        const over_resize = self.testHot(resize_uid, resize_rect);
        if (over_resize and self.left_pressed) {
            self.active_id = resize_uid;
            self.focus_id = resize_uid;
            self.window_resize_start_mouse = self.mouse_pos;
            self.window_resize_start_size = .{ .x = rect.width(), .y = rect.height() };
        }
        if (self.active_id == resize_uid and self.left_down) {
            const min_w: f32 = @floatFromInt(s.min_window_size.x);
            const min_h: f32 = @floatFromInt(s.min_window_size.y);
            const width = @max(min_w, self.window_resize_start_size.x + self.mouse_pos.x - self.window_resize_start_mouse.x);
            const height = @max(min_h, self.window_resize_start_size.y + self.mouse_pos.y - self.window_resize_start_mouse.y);
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
        if (over_title and self.left_pressed and self.active_id != resize_uid) {
            self.active_id = move_uid;
            self.focus_id = move_uid;
            self.window_drag_offset = .{
                .x = self.mouse_pos.x - rect.l,
                .y = self.mouse_pos.y - rect.t,
            };
        }
        if (self.active_id == move_uid and self.left_down) {
            const width = rect.width();
            const height = rect.height();
            rect.l = self.mouse_pos.x - self.window_drag_offset.x;
            rect.t = self.mouse_pos.y - self.window_drag_offset.y;
            rect.r = rect.l + width;
            rect.b = rect.t + height;
        }

        // Background
        self.shapes.drawFilledRect(rect.*, s.window_bg);
        self.shapes.drawEnclosingRect(rect.*, s.window_border, 1);

        // Title bar
        title_rect = RectF{
            .l = rect.l,
            .t = rect.t,
            .r = rect.r,
            .b = rect.t + title_h,
        };
        self.shapes.drawFilledRect(title_rect, s.window_title_bg);
        resize_rect = .{
            .l = rect.r - resize_size,
            .t = rect.b - resize_size,
            .r = rect.r,
            .b = rect.b,
        };
        self.shapes.drawFilledRect(
            resize_rect.shrinkFrom(3.0),
            if (over_resize or self.active_id == resize_uid) s.window_resize_handle_hover else s.window_resize_handle,
        );

        // Title text — vertically centered in title bar
        const line_h: f32 = if (self.text.atlas) |a| @floatFromInt(a.maxY) else 16;
        _ = self.text.drawString(title, .{
            .x = @intFromFloat(rect.l + pad_x),
            .y = @intFromFloat(rect.t + (title_h - line_h) / 2.0),
        });

        // Push window context
        std.debug.assert(self.win_depth < self.win_stack.len);
        self.win_stack[self.win_depth] = .{
            .rect = rect.*,
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
        self.shapes.flush();
        self.images.flush();
        self.text.flush();
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

    /// Returns the remaining vertical space inside the current window,
    /// accounting for bottom padding. Useful for filling the rest of the
    /// window with a text area or other expanding widget.
    pub fn remainingHeight(self: *UiContext) f32 {
        const win = self.curWin();
        const pad_y: f32 = @floatFromInt(self.style.padding.y);
        const remaining = win.rect.b - win.content_y - pad_y;
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

    // ----------------------------------------------------------
    // Mouse hit test — uses the position snapshotted in update()
    // ----------------------------------------------------------

    fn testHot(self: *UiContext, id: u64, rect: RectF) bool {
        // mouse_pos is already in logical coordinates (converted in update()).
        // Widget rects live in the same logical space, so compare directly.
        const mp = self.mouse_pos;
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
    // image
    // ----------------------------------------------------------

    /// Draw a texture or atlas subtexture at the requested logical size.
    pub fn image(self: *UiContext, texture: *Texture, size: Vec2I) void {
        const rect = self.allocWidget(
            @floatFromInt(size.x),
            @floatFromInt(size.y),
        );
        self.images.draw(texture, rect, texture.src, .none);
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
    // selectable / selectableList
    // ----------------------------------------------------------

    fn drawSelectable(
        self: *UiContext,
        uid: u64,
        lbl: []const u8,
        selected: bool,
        rect: RectF,
    ) bool {
        const s = &self.style;
        const over = self.testHot(uid, rect);
        var clicked = false;

        if (over and self.left_pressed) {
            self.active_id = uid;
            self.focus_id = uid;
        }
        if (self.active_id == uid and over and self.left_released) {
            clicked = true;
        }

        const bg = if (self.active_id == uid)
            s.selectable_pressed
        else if (selected)
            s.selectable_selected
        else if (over)
            s.selectable_hover
        else
            s.selectable_normal;
        self.shapes.drawFilledRect(rect, bg);

        const pad_x: f32 = @floatFromInt(s.padding.x);
        const line_h: f32 = if (self.text.atlas) |a| @floatFromInt(a.maxY) else 16;
        const text_clip = RectF{ .l = rect.l + pad_x, .t = rect.t, .r = rect.r - pad_x, .b = rect.b };
        _ = self.text.drawClippedString(lbl, .{
            .x = @intFromFloat(rect.l + pad_x),
            .y = @intFromFloat(rect.t + (rect.height() - line_h) / 2.0),
        }, text_clip);

        return clicked;
    }

    /// A single selectable row. Returns true when it is clicked.
    pub fn selectable(self: *UiContext, id: []const u8, lbl: []const u8, selected: bool) bool {
        const h: f32 = @floatFromInt(self.style.selectable_height);
        const rect = self.allocWidget(self.contentWidth(), h);
        return self.drawSelectable(hashId(id), lbl, selected, rect);
    }

    /// Scrollable list of text rows with one optional selection.
    /// Returns true when `selected` changes.
    pub fn selectableList(
        self: *UiContext,
        id: []const u8,
        items: []const []const u8,
        selected: *?usize,
        scroll: *usize,
        area_height: f32,
    ) bool {
        const s = &self.style;
        const uid = hashId(id);
        const sb_uid = uid ^ 0x5343_0000_0000_0002;
        const rect = self.allocWidget(self.contentWidth(), area_height);
        const row_h: f32 = @floatFromInt(s.selectable_height);
        const visible: usize = @max(1, @as(usize, @intFromFloat(@floor(area_height / row_h))));
        const scrollable = items.len > visible;
        const max_scroll = if (scrollable) items.len - visible else 0;
        const sb_w = s.scrollbar_w;
        const row_r = if (scrollable) rect.r - sb_w - 2.0 else rect.r;

        if (scroll.* > max_scroll) scroll.* = max_scroll;
        if (selected.*) |idx| {
            if (idx >= items.len) selected.* = null;
        }

        const body_rect = RectF{ .l = rect.l, .t = rect.t, .r = row_r, .b = rect.b };
        const over_body = self.testHot(uid, body_rect);
        if (over_body) {
            if (self.page_up_pressed and scroll.* > 0) {
                scroll.* -= 1;
            } else if (self.page_down_pressed and scroll.* < max_scroll) {
                scroll.* += 1;
            }
        }

        const sb_rect = RectF{ .l = rect.r - sb_w, .t = rect.t, .r = rect.r, .b = rect.b };
        if (scrollable) {
            const over_sb = self.testHot(sb_uid, sb_rect);
            if (over_sb and self.left_pressed) self.active_id = sb_uid;
            if (self.active_id == sb_uid and self.left_down) {
                const thumb_h = @max((area_height * @as(f32, @floatFromInt(visible))) /
                    @as(f32, @floatFromInt(items.len)), 12.0);
                const travel = area_height - thumb_h;
                const t = std.math.clamp((self.mouse_pos.y - sb_rect.t - thumb_h / 2.0) / travel, 0.0, 1.0);
                scroll.* = @intFromFloat(t * @as(f32, @floatFromInt(max_scroll)));
            }
        }

        self.shapes.drawFilledRect(rect, s.text_area_bg);
        self.shapes.drawEnclosingRect(rect, s.text_area_border, 1);

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
            const thumb_h = @max((area_height * @as(f32, @floatFromInt(visible))) /
                @as(f32, @floatFromInt(items.len)), 12.0);
            const travel = area_height - thumb_h;
            const scroll_t = @as(f32, @floatFromInt(scroll.*)) / @as(f32, @floatFromInt(max_scroll));
            const thumb_t = sb_rect.t + scroll_t * travel;
            const thumb_rect = RectF{
                .l = sb_rect.l + 1.0,
                .t = thumb_t,
                .r = sb_rect.r - 1.0,
                .b = thumb_t + thumb_h,
            };
            self.shapes.drawFilledRect(sb_rect, s.scrollbar_track);
            const thumb_col = if (self.active_id == sb_uid)
                s.scrollbar_thumb_active
            else if (self.hot_id == sb_uid)
                s.scrollbar_thumb_hover
            else
                s.scrollbar_thumb;
            self.shapes.drawFilledRect(thumb_rect, thumb_col);
        }

        return changed;
    }

    // ----------------------------------------------------------
    // checkbox / toggle
    // ----------------------------------------------------------

    /// Boolean toggle rendered as a checkbox and label.
    pub fn checkbox(self: *UiContext, id: []const u8, lbl: []const u8, checked: *bool) bool {
        const s = &self.style;
        const uid = hashId(id);
        const h: f32 = @floatFromInt(s.input_height);
        const rect = self.allocWidget(self.contentWidth(), h);
        const over = self.testHot(uid, rect);
        var changed = false;

        if (over and self.left_pressed) {
            self.active_id = uid;
            self.focus_id = uid;
        }
        if (self.active_id == uid and over and self.left_released) {
            checked.* = !checked.*;
            changed = true;
        }

        const box_size: f32 = @floatFromInt(s.checkbox_size);
        const box = RectF{
            .l = rect.l,
            .t = rect.t + (h - box_size) / 2.0,
            .r = rect.l + box_size,
            .b = rect.t + (h + box_size) / 2.0,
        };
        self.shapes.drawFilledRect(box, s.checkbox_bg);
        self.shapes.drawEnclosingRect(box, if (over) s.checkbox_hover else s.checkbox_border, 1);
        if (checked.*) {
            self.shapes.drawFilledRect(box.shrinkFrom(4.0), s.checkbox_check);
        }

        const item_sp: f32 = @floatFromInt(s.item_spacing);
        const line_h: f32 = if (self.text.atlas) |a| @floatFromInt(a.maxY) else 16;
        _ = self.text.drawString(lbl, .{
            .x = @intFromFloat(box.r + item_sp * 2.0),
            .y = @intFromFloat(rect.t + (h - line_h) / 2.0),
        });

        return changed;
    }

    /// Alias for checkbox when a boolean is conceptually an option toggle.
    pub fn toggle(self: *UiContext, id: []const u8, lbl: []const u8, value: *bool) bool {
        return self.checkbox(id, lbl, value);
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

        // Draw text clipped to the inner content rect so long strings don't
        // overflow the box border.
        const pad_x: f32 = @floatFromInt(s.padding.x);
        const line_h: f32 = if (self.text.atlas) |a| @floatFromInt(a.maxY) else 16;
        const ty: i32 = @intFromFloat(rect.t + (h - line_h) / 2.0);
        const text_clip = RectF{ .l = rect.l + pad_x, .t = rect.t, .r = rect.r - pad_x, .b = rect.b };
        _ = self.text.drawClippedString(buf[0..len.*], .{
            .x = @intFromFloat(rect.l + pad_x),
            .y = ty,
        }, text_clip);

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
    // inputInt
    // ----------------------------------------------------------

    fn beginIntEdit(self: *UiContext, uid: u64, value: i32) void {
        const str = std.fmt.bufPrint(&self.int_edit_buf, "{}", .{value}) catch "0";
        self.int_edit_len = str.len;
        self.int_edit_id = uid;
        self.int_edit_replace = true;
    }

    /// Signed integer input. Typing after focus replaces the current value;
    /// backspace edits the existing value from its end.
    pub fn inputInt(self: *UiContext, id: []const u8, value: *i32) bool {
        const s = &self.style;
        const uid = hashId(id);
        const h: f32 = @floatFromInt(s.input_height);
        const rect = self.allocWidget(self.contentWidth(), h);
        const over = self.testHot(uid, rect);

        if (over and self.left_pressed) {
            if (self.focus_id != uid or self.int_edit_id != uid) {
                self.beginIntEdit(uid, value.*);
            }
            self.focus_id = uid;
        }

        const focused = self.focus_id == uid;
        if (focused and self.int_edit_id != uid) {
            self.beginIntEdit(uid, value.*);
        }

        var changed = false;
        if (focused) {
            for (self.text_input[0..self.text_input_len]) |c| {
                const valid = (c >= '0' and c <= '9') or
                    (c == '-' and (self.int_edit_replace or self.int_edit_len == 0));
                if (!valid) continue;
                if (self.int_edit_replace) {
                    self.int_edit_len = 0;
                    self.int_edit_replace = false;
                }
                if (c == '-' and self.int_edit_len != 0) continue;
                if (self.int_edit_len < self.int_edit_buf.len) {
                    self.int_edit_buf[self.int_edit_len] = c;
                    self.int_edit_len += 1;
                }
            }

            var remove_count = self.backspace_count + self.delete_count;
            if (remove_count > 0) self.int_edit_replace = false;
            while (remove_count > 0 and self.int_edit_len > 0) : (remove_count -= 1) {
                self.int_edit_len -= 1;
            }

            if (self.int_edit_len > 0 and
                !(self.int_edit_len == 1 and self.int_edit_buf[0] == '-'))
            {
                if (std.fmt.parseInt(i32, self.int_edit_buf[0..self.int_edit_len], 10)) |new_value| {
                    if (new_value != value.*) {
                        value.* = new_value;
                        changed = true;
                    }
                } else |_| {}
            }
        }

        self.shapes.drawFilledRect(rect, s.input_bg);
        const border_col = if (focused) s.input_border_focused else if (over) s.input_border_hover else s.input_border;
        self.shapes.drawEnclosingRect(rect, border_col, 1);

        var display_buf: [32]u8 = undefined;
        const value_str = if (focused)
            self.int_edit_buf[0..self.int_edit_len]
        else
            std.fmt.bufPrint(&display_buf, "{}", .{value.*}) catch "?";
        const pad_x: f32 = @floatFromInt(s.padding.x);
        const line_h: f32 = if (self.text.atlas) |a| @floatFromInt(a.maxY) else 16;
        const ty: i32 = @intFromFloat(rect.t + (h - line_h) / 2.0);
        const text_clip = RectF{ .l = rect.l + pad_x, .t = rect.t, .r = rect.r - pad_x, .b = rect.b };
        _ = self.text.drawClippedString(value_str, .{
            .x = @intFromFloat(rect.l + pad_x),
            .y = ty,
        }, text_clip);

        if (focused and (self.frame / 30) % 2 == 0) {
            const pre_sz = self.text.measureString(value_str);
            const cx: f32 = rect.l + pad_x + @as(f32, @floatFromInt(pre_sz.x));
            const cy: f32 = rect.t + (h - line_h) / 2.0;
            self.shapes.drawFilledRect(RectF{
                .l = cx,
                .t = cy + line_h - 3.0,
                .r = cx + 8.0,
                .b = cy + line_h,
            }, s.input_cursor);
        }

        return changed;
    }

    // ----------------------------------------------------------
    // textArea
    // ----------------------------------------------------------

    /// Scrollable read-only text area with a vertical scrollbar.
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
        const sb_uid = uid ^ 0x5343_0000_0000_0001; // scrollbar thumb ID
        const w: f32 = self.contentWidth();
        const rect = self.allocWidget(w, area_height);

        const line_h: i32 = if (self.text.atlas) |a| a.maxY else 16;
        const line_hf: f32 = @floatFromInt(line_h);
        const pad_y: f32 = @floatFromInt(s.padding.y);
        const pad_x: f32 = @floatFromInt(s.padding.x);
        const usable_h: f32 = area_height - pad_y * 2.0;
        const lines_visible: usize = @intFromFloat(@floor(usable_h / line_hf));
        const scrollable = lines.len > lines_visible;

        // Scrollbar geometry
        const sb_w = s.scrollbar_w;
        const sb_rect = RectF{ .l = rect.r - sb_w, .t = rect.t, .r = rect.r, .b = rect.b };
        const text_r = if (scrollable) rect.r - sb_w - 2.0 else rect.r;

        // Hit-test the text body for page-up/down
        const body_rect = RectF{ .l = rect.l, .t = rect.t, .r = text_r, .b = rect.b };
        _ = self.testHot(uid, body_rect);

        if (self.hot_id == uid) {
            if (self.page_up_pressed and scroll.* > 0) {
                scroll.* -= 1;
            } else if (self.page_down_pressed) {
                if (scroll.* + lines_visible < lines.len) {
                    scroll.* += 1;
                }
            }
        }

        // Scrollbar interaction
        if (scrollable) {
            const max_scroll = lines.len - lines_visible;
            const over_sb = self.testHot(sb_uid, sb_rect);
            if (over_sb and self.left_pressed) self.active_id = sb_uid;
            if (self.active_id == sb_uid and self.left_down) {
                const thumb_h = @max((area_height * @as(f32, @floatFromInt(lines_visible))) /
                    @as(f32, @floatFromInt(lines.len)), 12.0);
                const travel = area_height - thumb_h;
                const my = self.mouse_pos.y;
                const t = std.math.clamp((my - sb_rect.t - thumb_h / 2.0) / travel, 0.0, 1.0);
                scroll.* = @intFromFloat(t * @as(f32, @floatFromInt(max_scroll)));
            }
            // Clamp scroll in case lines shrunk
            if (scroll.* > max_scroll) scroll.* = max_scroll;
        }

        // Background + border
        self.shapes.drawFilledRect(rect, s.text_area_bg);
        self.shapes.drawEnclosingRect(rect, s.text_area_border, 1);

        // Draw visible lines clipped to the text column so long lines don't
        // bleed into the scrollbar or past the border.
        const line_clip = RectF{ .l = rect.l + pad_x, .t = rect.t, .r = text_r - pad_x, .b = rect.b };
        var draw_y: i32 = @intFromFloat(rect.t + pad_y);
        const start = scroll.*;
        const end_idx = @min(start + lines_visible, lines.len);
        for (start..end_idx) |i| {
            _ = self.text.drawClippedString(lines[i], .{
                .x = @intFromFloat(rect.l + pad_x),
                .y = draw_y,
            }, line_clip);
            draw_y += line_h;
        }

        // Draw scrollbar
        if (scrollable) {
            const max_scroll = lines.len - lines_visible;
            const thumb_h = @max((area_height * @as(f32, @floatFromInt(lines_visible))) /
                @as(f32, @floatFromInt(lines.len)), 12.0);
            const scroll_t = if (max_scroll > 0)
                @as(f32, @floatFromInt(scroll.*)) / @as(f32, @floatFromInt(max_scroll))
            else
                0.0;
            const travel = area_height - thumb_h;
            const thumb_t = sb_rect.t + scroll_t * travel;
            const thumb_rect = RectF{
                .l = sb_rect.l + 1.0,
                .t = thumb_t,
                .r = sb_rect.r - 1.0,
                .b = thumb_t + thumb_h,
            };

            self.shapes.drawFilledRect(sb_rect, s.scrollbar_track);
            const is_active = self.active_id == sb_uid;
            const is_hot = self.hot_id == sb_uid;
            const thumb_col = if (is_active) s.scrollbar_thumb_active else if (is_hot) s.scrollbar_thumb_hover else s.scrollbar_thumb;
            self.shapes.drawFilledRect(thumb_rect, thumb_col);
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
            const mx = self.mouse_pos.x;
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
