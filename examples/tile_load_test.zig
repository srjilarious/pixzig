// zig fmt: off
const std = @import("std");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const gl = @import("zopengl");
const stbi = @import ("zstbi");
const pixzig = @import("pixzig");
const RectF = pixzig.common.RectF;
const RectI = pixzig.common.RectI;
const Color = pixzig.common.Color;

const math = @import("zmath");
const EngOptions = pixzig.PixzigEngineOptions;

const tile = pixzig.tile;
const Flip = pixzig.sprites.Flip;
const Frame = pixzig.sprites.Frame;
const Vec2I = pixzig.common.Vec2I;

pub fn main() !void {
    std.log.info("Pixzig Tilemap test!", .{});
    
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var eng = try pixzig.PixzigEngine.init("Glfw Eng Test.", gpa, EngOptions{});
    defer eng.deinit();

    // Orthographic projection matrix
    const projMat = math.orthographicOffCenterLhGl(0, 800, 0, 600, -0.1, 1000);

    // Try to load an image
    // const texture = try eng.textures.loadTexture("tiles", "assets/mario_grassish2.png");
    // _ = texture;

    var texShader = try pixzig.shaders.Shader.init(
            &pixzig.shaders.TexVertexShader,
            &pixzig.shaders.TexPixelShader
        );
    defer texShader.deinit();
    
    const tex = try eng.textures.loadTexture("tiles", "assets/mario_grassish2.png");
    const map = try tile.TileMap.initFromFile("assets/level1a.tmx", std.heap.page_allocator);
    // defer map.deinit();

    var mapRender = try tile.TileMapRenderer.init(std.heap.page_allocator, &texShader);
    defer mapRender.deinit();

    try mapRender.recreateVertices(&map.tilesets.items[0], &map.layers.items[1]);

    var scroll_offset = Vec2I{ .x = 0, .y = 0 };
    scroll_offset.x = 0;

    std.debug.print("Starting main loop...\n", .{});
    // Main loop
    while (!eng.window.shouldClose() and eng.window.getKey(.escape) != .press) {
        glfw.pollEvents();

        eng.keyboard.update();

        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.0, 0.0, 0.0, 1.0 });
        
        if (eng.keyboard.pressed(.one)) std.debug.print("one!\n", .{});
        if (eng.keyboard.pressed(.two)) std.debug.print("two!\n", .{});
        if (eng.keyboard.pressed(.three)) std.debug.print("three!\n", .{});
        if (eng.keyboard.pressed(.left)) {
            std.debug.print("Left!\n", .{});
        }
        if (eng.keyboard.pressed(.right)) {
            std.debug.print("Right!\n", .{});
        }

        try mapRender.draw(tex, &map.layers.items[0], projMat);
       
        // const fb_size = eng.window.getFramebufferSize();
        //
        // zgui.backend.newFrame(@intCast(fb_size[0]), @intCast(fb_size[1]));
        //
        // // Set the starting window position and size to custom values
        // zgui.setNextWindowPos(.{ .x = 20.0, .y = 20.0, .cond = .first_use_ever });
        // zgui.setNextWindowSize(.{ .w = -1.0, .h = -1.0, .cond = .first_use_ever });
        //
        // if (zgui.begin("My window", .{})) {
        //     if (zgui.button("Press me!", .{ .w = 200.0 })) {
        //         std.debug.print("Button pressed\n", .{});
        //     }
        // }
        // zgui.end();
        //
        // zgui.backend.draw();

        eng.window.swapBuffers();
    }

    std.debug.print("Cleaning up...\n", .{});


        // if (eng.keyboard.down(.escape)) break :main_loop;
        // // if (eng.keyboard.pressed(.@"1")) fr1.apply(&spr);
        // // if (eng.keyboard.pressed(.@"2")) fr2.apply(&spr);
        // // if (eng.keyboard.pressed(.@"3")) fr3.apply(&spr);
        // if (eng.keyboard.down(.left)) {
        //     scroll_offset.x -= 1;
        // }
        // if (eng.keyboard.down(.right)) {
        //     scroll_offset.x += 1;
        // }
        // if (eng.keyboard.down(.up)) {
        //     scroll_offset.y -= 1;
        // }
        // if (eng.keyboard.pressed(.down)) {
        //     scroll_offset.y += 1;
        // }

    //     try renderer.setDrawColorRGB(32, 32, 100);
    //     try renderer.clear();
    //
    //     try renderer.setDrawColorRGB(128, 10, 10);
    //     try renderer.fillRect(.{ .x = 50, .y = 50, .w = 300, .h = 300 });
    //
    //
    //     // actor.update(30, &spr);
    //     // try spr.draw(renderer);
    //     renderer.present();
    // }
}
