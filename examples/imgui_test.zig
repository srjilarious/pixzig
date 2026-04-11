//! imgui_test — demonstrates the pixzig immediate mode GUI.
//!
//! Shows:
//!   - A window with title bar
//!   - Label text
//!   - Normal / disabled buttons
//!   - Text input box
//!   - Scrollable text area (log)

const std = @import("std");
const pixzig = @import("pixzig");
const glfw = pixzig.glfw;
const zmath = pixzig.zmath;
const RectF = pixzig.common.RectF;
const Color = pixzig.common.Color;

const input = pixzig.input;
const imgui = pixzig.imgui;

pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.PixzigAppRunner(App, .{
    .rendererOpts = .{
        .textRenderering = true,
    },
});

const MaxLogLines = 200;
const InputBufLen = 128;

pub const App = struct {
    alloc: std.mem.Allocator,
    mouse: input.Mouse,
    ui: imgui.UiContext,

    // Text input buffer
    input_buf: [InputBufLen]u8,
    input_len: usize,

    // Log lines displayed in the text area
    log: std.ArrayListUnmanaged([]const u8),
    log_scroll: usize,

    // Counter shown in the window title
    click_count: u32,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        const app = try alloc.create(App);

        var mouse = input.Mouse.init(eng.window, alloc);
        mouse.update();

        app.* = .{
            .alloc = alloc,
            .mouse = mouse,
            .ui = imgui.UiContext.init(
                &app.mouse,
                &eng.keyboard,
                &eng.renderer.impl.shapes,
                &eng.renderer.impl.text,
                eng.scaleFactor,
            ),
            .input_buf = std.mem.zeroes([InputBufLen]u8),
            .input_len = 0,
            .log = std.ArrayListUnmanaged([]const u8){},
            .log_scroll = 0,
            .click_count = 0,
        };

        try app.addLog("GUI test started. Type something and press Submit.");
        try app.addLog("Hover/click buttons to see state changes.");

        return app;
    }

    fn addLog(self: *App, msg: []const u8) !void {
        const copy = try self.alloc.dupe(u8, msg);
        try self.log.append(self.alloc, copy);
        // Keep scroll at the bottom
        if (self.log.items.len > 5) {
            self.log_scroll = self.log.items.len - 5;
        }
    }

    pub fn deinit(self: *App) void {
        for (self.log.items) |line| self.alloc.free(line);
        self.log.deinit(self.alloc);
        self.alloc.destroy(self);
    }

    pub fn update(self: *App, eng: *AppRunner.Engine, _delta: f64) bool {
        _ = _delta;
        if (eng.keyboard.pressed(.escape)) return false;

        self.mouse.update();
        self.ui.update();
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0.15, 0.15, 0.20, 1.0);
        eng.renderer.begin(eng.projMat);

        self.ui.begin();

        // Main demo window
        const win_rect = RectF.fromPosSize(30, 30, 380, 460);
        self.ui.beginWindow("demo_win", "Pixzig IMGUI Demo", win_rect);

        // --- Labels ---
        self.ui.label("Text input:");
        _ = self.ui.inputText("name_input", &self.input_buf, &self.input_len);

        self.ui.spacing();

        // --- Submit button (enabled) ---
        if (self.ui.button("submit_btn", "Submit")) {
            const text = self.input_buf[0..self.input_len];
            if (text.len > 0) {
                const msg = std.fmt.allocPrint(
                    self.alloc,
                    "Submitted: {s}",
                    .{text},
                ) catch "Submitted!";
                self.addLog(msg) catch {};
                @memset(&self.input_buf, 0);
                self.input_len = 0;
                self.click_count += 1;
            } else {
                self.addLog("(empty input)") catch {};
            }
        }

        // --- Clear log button (same line as counter label) ---
        if (self.ui.button("clear_btn", "Clear Log")) {
            for (self.log.items) |line| self.alloc.free(line);
            self.log.clearRetainingCapacity();
            self.log_scroll = 0;
            self.addLog("Log cleared.") catch {};
        }

        self.ui.spacing();

        // --- Disabled button demo ---
        self.ui.label("Disabled button:");
        _ = self.ui.buttonEx("disabled_btn", "Unavailable", true);

        self.ui.spacing();

        // --- Text area ---
        self.ui.label("Log (Page Up/Down to scroll):");
        self.ui.textArea("log_area", self.log.items, &self.log_scroll, 180);

        self.ui.endWindow();

        // Second smaller window
        const win2_rect = RectF.fromPosSize(440, 30, 250, 140);
        self.ui.beginWindow("info_win", "Info", win2_rect);
        var count_buf: [64]u8 = undefined;
        const count_str = std.fmt.bufPrint(
            &count_buf,
            "Submits: {}",
            .{self.click_count},
        ) catch "Submits: ?";
        self.ui.label(count_str);
        self.ui.spacing();

        const cursorStr = std.fmt.bufPrint(
            &count_buf,
            "Cursor: ({d}, {d})",
            .{
                @as(i32, @intFromFloat(self.ui.mouse_pos.x)),
                @as(i32, @intFromFloat(self.ui.mouse_pos.y)),
            },
        ) catch "Cursor: (?, ?)";
        self.ui.label(cursorStr);
        self.ui.spacing();

        self.ui.label("ESC to quit");
        self.ui.endWindow();

        self.ui.end();

        eng.renderer.end();
    }
};

pub fn main() !void {
    std.log.info("Pixzig IMGUI Test", .{});
    const alloc = std.heap.c_allocator;
    const appRunner = try AppRunner.init(
        "Pixzig: IMGUI Test",
        alloc,
        .{ .renderInitOpts = .{ .fontFace = "assets/Roboto-Medium.ttf" } },
    );
    const app = try App.init(alloc, appRunner.engine);
    appRunner.run(app);
}
