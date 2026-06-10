//! Example that demonstrates the pixzig immediate mode GUI.
//!
//! Shows:
//!   - A window with title bar
//!   - Label text
//!   - Normal / disabled buttons
//!   - Text input box
//!   - Integer input and checkbox
//!   - Selectable list
//!   - Embedded image preview
//!   - Draggable, resizable, and dockable windows
//!   - Scrollable text area (log)

const std = @import("std");
const pixzig = @import("pixzig");
const zmath = pixzig.zmath;
const RectF = pixzig.common.RectF;
const Color = pixzig.common.Color;

const input = pixzig.input;
const imgui = pixzig.imgui;

pub const panic = pixzig.system.panic;
pub const std_options = pixzig.system.std_options;

const AppRunner = pixzig.PixzigAppRunner(App, .{
    .rendererOpts = .{
        .textRendering = true,
    },
    .inputOpts = .{ .mouse = true },
});

const MaxLogLines = 200;
const InputBufLen = 128;
const SpriteNames = [_][]const u8{
    "player_idle_0",
    "player_idle_1",
    "player_walk_0",
    "player_walk_1",
    "player_jump",
    "player_land",
};

pub const App = struct {
    alloc: std.mem.Allocator,
    ui: imgui.UiContext,
    preview: *pixzig.Texture,
    main_window: RectF,
    editor_window: RectF,

    // Text input buffer
    input_buf: [InputBufLen]u8,
    input_len: usize,

    // Log lines displayed in the text area
    log: std.ArrayListUnmanaged([]const u8),
    log_scroll: usize,

    // Counter shown in the window title
    click_count: u32,

    // Slider values
    slider_a: f32,
    slider_b: f32,

    // Editor-oriented widgets
    loop_animation: bool,
    frame_ms: i32,
    selected_sprite: ?usize,
    sprite_scroll: usize,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        const app = try alloc.create(App);

        app.* = .{
            .alloc = alloc,
            .ui = imgui.UiContext.init(
                &eng.inputs.mouse,
                &eng.inputs.keyboard,
                &eng.renderer.impl.batches[0],
                &eng.renderer.impl.overlays,
                &eng.renderer.impl.shapes,
                &eng.renderer.impl.text,
            ),
            .preview = undefined,
            .main_window = RectF.fromPosSize(30, 30, 380, 430),
            .editor_window = RectF.fromPosSize(440, 30, 300, 430),
            .input_buf = std.mem.zeroes([InputBufLen]u8),
            .input_len = 0,
            .log = .empty,
            .log_scroll = 0,
            .click_count = 0,
            .slider_a = 0.5,
            .slider_b = 25.0,
            .loop_animation = true,
            .frame_ms = 100,
            .selected_sprite = 0,
            .sprite_scroll = 0,
        };
        const sheet = try eng.resources.loadTexture("imgui_tiles", "assets/mario_grassish2.png");
        app.preview = try eng.resources.addSubTexture(
            sheet,
            "imgui_preview",
            RectF.fromCoords(32, 32, 32, 32, 512, 512),
        );

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
        if (eng.inputs.keyboard.pressed(.escape)) return false;

        self.ui.update();
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.Engine) void {
        eng.renderer.clear(0.15, 0.15, 0.40, 1.0);
        eng.renderer.begin(eng.projMat);

        self.ui.begin();

        // Main demo window
        self.ui.beginWindow("demo_win", "Pixzig IMGUI Demo", &self.main_window);

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

        // --- Sliders ---
        self.ui.label("Float (0.0 - 1.0):");
        if (self.ui.slider("slider_a", &self.slider_a, 0.0, 1.0)) {
            var buf: [64]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "slider_a = {d:.3}", .{self.slider_a}) catch "slider_a changed";
            self.addLog(msg) catch {};
        }

        self.ui.label("Int range (0 - 100):");
        if (self.ui.slider("slider_b", &self.slider_b, 0.0, 100.0)) {
            var buf: [64]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "slider_b = {d:.0}", .{self.slider_b}) catch "slider_b changed";
            self.addLog(msg) catch {};
        }

        self.ui.spacing();

        // --- Disabled button demo ---
        self.ui.label("Disabled button:");
        _ = self.ui.buttonEx("disabled_btn", "Unavailable", true);

        self.ui.spacing();

        // --- Text area ---
        self.ui.label("Log:");
        self.ui.textArea("log_area", self.log.items, &self.log_scroll, self.ui.remainingHeight());

        self.ui.endWindow();

        // Editor widget preview window
        self.ui.beginWindow("editor_widgets_win", "Editor Widgets", &self.editor_window);
        self.ui.label("Sprites:");
        if (self.ui.selectableList("sprite_list", &SpriteNames, &self.selected_sprite, &self.sprite_scroll, 72)) {
            if (self.selected_sprite) |selected| {
                var buf: [96]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "Selected: {s}", .{SpriteNames[selected]}) catch "Selection changed";
                self.addLog(msg) catch {};
            }
        }
        self.ui.spacing();
        self.ui.label("Preview:");
        self.ui.image(self.preview, .{ .x = 48, .y = 48 });
        _ = self.ui.toggle("loop_animation", "Loop animation", &self.loop_animation);
        self.ui.label("Frame duration (ms):");
        _ = self.ui.inputInt("frame_ms", &self.frame_ms);
        self.ui.spacing();

        if (self.ui.button("dock_left", "Dock Left (35%)")) {
            self.ui.resizeWindowToSide(&self.editor_window, .left, 0.35, eng.viewport.logical_size);
        }
        if (self.ui.button("dock_right", "Dock Right (35%)")) {
            self.ui.resizeWindowToSide(&self.editor_window, .right, 0.35, eng.viewport.logical_size);
        }
        if (self.ui.button("dock_up", "Dock Up (45%)")) {
            self.ui.resizeWindowToSide(&self.editor_window, .up, 0.45, eng.viewport.logical_size);
        }
        if (self.ui.button("dock_down", "Dock Down (45%)")) {
            self.ui.resizeWindowToSide(&self.editor_window, .down, 0.45, eng.viewport.logical_size);
        }

        var count_buf: [64]u8 = undefined;
        const selected_str = if (self.selected_sprite) |selected|
            SpriteNames[selected]
        else
            "(none)";
        const count_str = std.fmt.bufPrint(
            &count_buf,
            "Selected: {s}",
            .{selected_str},
        ) catch "Selected: ?";
        self.ui.label(count_str);

        const cursorStr = std.fmt.bufPrint(
            &count_buf,
            "Frame: {d} ms",
            .{self.frame_ms},
        ) catch "Frame: ?";
        self.ui.label(cursorStr);

        self.ui.label("ESC to quit");
        self.ui.endWindow();

        self.ui.end();

        eng.renderer.end();
    }
};

pub fn main(init: std.process.Init) !void {
    std.log.info("Pixzig IMGUI Test", .{});
    const appRunner = try AppRunner.init(
        "Pixzig: IMGUI Test",
        init.gpa,
        .{
            .scalePolicy = .integer_fit,
            .logicalSize = .{ .x = 1200, .y = 720 },
            .renderInitOpts = .{ .fontFace = "assets/Roboto-Medium.ttf" },
        },
    );
    const app = try App.init(init.gpa, appRunner.engine);
    appRunner.run(app);
}
