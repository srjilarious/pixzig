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
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;

const input = pixzig.input;
const imgui = pixzig.imgui;
const manifest_options = @import("manifest_options");
const AppRunner = pixzig.AppRunner(App, .{
    // textInput arms the OS text-input machinery, which is what makes
    // Keyboard.text() -- and so the UI's text fields -- produce anything.
    .inputOpts = .{ .mouse = true, .textInput = true },
    .manifestOpts = manifest_options,
});
const UiContext = imgui.UiContext(AppRunner.Engine);

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
    ui: UiContext,
    preview: *pixzig.TextureHandle,
    mainWindow: RectF,
    editorWindow: RectF,

    // Text input buffer
    inputBuf: [InputBufLen]u8,
    inputLen: usize,

    // Log lines displayed in the text area
    log: std.ArrayListUnmanaged([]const u8),
    logScroll: usize,

    // Counter shown in the window title
    clickCount: u32,

    // Slider values
    sliderA: f32,
    sliderB: f32,

    // Editor-oriented widgets
    loopAnimation: bool,
    frameMs: i32,
    selectedSprite: ?usize,
    spriteScroll: usize,

    pub fn init(alloc: std.mem.Allocator, eng: *AppRunner.Engine) !*App {
        const app = try alloc.create(App);

        app.* = .{
            .alloc = alloc,
            .ui = UiContext.init(eng),
            .preview = undefined,
            .mainWindow = RectF.fromPosSize(30, 30, 380, 430),
            .editorWindow = RectF.fromPosSize(440, 30, 300, 430),
            .inputBuf = std.mem.zeroes([InputBufLen]u8),
            .inputLen = 0,
            .log = .empty,
            .logScroll = 0,
            .clickCount = 0,
            .sliderA = 0.5,
            .sliderB = 25.0,
            .loopAnimation = true,
            .frameMs = 100,
            .selectedSprite = 0,
            .spriteScroll = 0,
        };
        const sheet = try eng.resources.loadTexture("imgui_tiles", "assets/mario_grassish2.png");
        app.preview = try eng.resources.addSubTexture(
            sheet,
            "imgui_preview",
            RectI.init(32, 32, 32, 32),
        );
        app.ui.setClipboardWindow(eng.window);

        try app.addLog("GUI test started. Type something and press Submit.");
        try app.addLog("Hover/click buttons to see state changes.");

        return app;
    }

    fn addLog(self: *App, msg: []const u8) !void {
        const copy = try self.alloc.dupe(u8, msg);
        errdefer self.alloc.free(copy);
        try self.appendLog(copy);
    }

    fn appendLog(self: *App, msg: []const u8) !void {
        try self.log.append(self.alloc, msg);
        // Keep scroll at the bottom
        if (self.log.items.len > 5) {
            self.logScroll = self.log.items.len - 5;
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
        eng.renderer.clear(38, 38, 102, 255);
        eng.renderer.begin(.logical);

        self.ui.begin();

        // Main demo window
        self.ui.beginWindow("demo_win", "Pixzig IMGUI Demo", &self.mainWindow);

        // --- Labels ---
        self.ui.label("Text input:");
        const input_res = self.ui.inputTextEx("name_input", &self.inputBuf, &self.inputLen, .{
            .submitOnEnter = true,
        });

        self.ui.spacing();

        // --- Submit button (enabled) ---

        // --- Submit + Clear on the same row using sameLine ---
        const btn_w = (self.ui.contentWidth() - @as(f32, @floatFromInt(self.ui.style.itemSpacing))) / 2.0;
        const submit_clicked = self.ui.buttonSized("submit_btn", "Submit", btn_w);
        if (input_res.submitted or submit_clicked) {
            const text = self.inputBuf[0..self.inputLen];
            if (text.len > 0) {
                const msg = std.fmt.allocPrint(
                    self.alloc,
                    "Submitted: {s}",
                    .{text},
                ) catch "Submitted!";
                self.appendLog(msg) catch {};
                @memset(&self.inputBuf, 0);
                self.inputLen = 0;
                self.clickCount += 1;
            } else {
                self.addLog("(empty input)") catch {};
            }
        }
        self.ui.sameLine();
        if (self.ui.buttonSized("clear_btn", "Clear Log", btn_w)) {
            for (self.log.items) |line| self.alloc.free(line);
            self.log.clearRetainingCapacity();
            self.logScroll = 0;
            self.addLog("Log cleared.") catch {};
        }

        self.ui.spacing();

        // --- Sliders ---
        self.ui.label("Float (0.0 - 1.0):");
        if (self.ui.slider("slider_a", &self.sliderA, 0.0, 1.0)) {
            var buf: [64]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "slider_a = {d:.3}", .{self.sliderA}) catch "slider_a changed";
            self.addLog(msg) catch {};
        }

        self.ui.label("Int range (0 - 100):");
        if (self.ui.slider("slider_b", &self.sliderB, 0.0, 100.0)) {
            var buf: [64]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "slider_b = {d:.0}", .{self.sliderB}) catch "slider_b changed";
            self.addLog(msg) catch {};
        }

        self.ui.spacing();

        // --- Disabled button demo ---
        self.ui.label("Disabled button:");
        _ = self.ui.buttonEx("disabled_btn", "Unavailable", true);

        self.ui.spacing();

        // --- Text area ---
        self.ui.label("Log:");
        self.ui.textArea("log_area", self.log.items, &self.logScroll, self.ui.remainingHeight());

        self.ui.endWindow();

        // Editor widget preview window
        self.ui.beginWindow("editor_widgets_win", "Editor Widgets", &self.editorWindow);
        self.ui.label("Sprites:");
        if (self.ui.selectableList("sprite_list", &SpriteNames, &self.selectedSprite, &self.spriteScroll, 128)) {
            if (self.selectedSprite) |selected| {
                var buf: [96]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "Selected: {s}", .{SpriteNames[selected]}) catch "Selection changed";
                self.addLog(msg) catch {};
            }
        }
        self.ui.spacing();
        self.ui.label("Preview:");
        self.ui.image(self.preview, .{ .x = 48, .y = 48 });
        _ = self.ui.toggle("loop_animation", "Loop animation", &self.loopAnimation);
        self.ui.label("Frame duration (ms):");
        _ = self.ui.inputInt("frame_ms", &self.frameMs);
        self.ui.spacing();

        if (self.ui.button("dock_left", "Dock Left (35%)")) {
            self.ui.resizeWindowToSide(&self.editorWindow, .left, 0.35, eng.viewport.logicalSize);
        }
        if (self.ui.button("dock_right", "Dock Right (35%)")) {
            self.ui.resizeWindowToSide(&self.editorWindow, .right, 0.35, eng.viewport.logicalSize);
        }
        if (self.ui.button("dock_up", "Dock Up (45%)")) {
            self.ui.resizeWindowToSide(&self.editorWindow, .up, 0.45, eng.viewport.logicalSize);
        }
        if (self.ui.button("dock_down", "Dock Down (45%)")) {
            self.ui.resizeWindowToSide(&self.editorWindow, .down, 0.45, eng.viewport.logicalSize);
        }

        var count_buf: [64]u8 = undefined;
        const selected_str = if (self.selectedSprite) |selected|
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
            .{self.frameMs},
        ) catch "Frame: ?";
        self.ui.label(cursorStr);

        self.ui.label("ESC to quit");
        self.ui.endWindow();

        self.ui.end();

        eng.renderer.end();
    }
};

pub fn main(init: std.process.Init) !void {
    const appRunner = try AppRunner.init(
        "Pixzig: IMGUI Test",
        init.gpa,
        .{
            .scalePolicy = .integer_fit,
            .logicalSize = .{ .x = 1200, .y = 720 },
            .renderInitOpts = .{ .font = .{ .id = "Roboto-Medium" } },
        },
    );
    defer appRunner.deinit();

    const app = try App.init(init.gpa, appRunner.engine);
    defer app.deinit();

    appRunner.run(app);
}
