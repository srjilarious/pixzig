const std = @import("std");
const sdl = @import("zsdl");
const gl = @import("zopengl");
const stbi = @import("zstbi");

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    _ = sdl.setHint(sdl.hint_windows_dpi_awareness, "system");

    try sdl.init(.{ .audio = true, .video = true });
    defer sdl.quit();

    stbi.init(std.heap.page_allocator);
    defer stbi.deinit();

    // const gl_major = 3;
    // const gl_minor = 3;
    // try sdl.gl.setAttribute(.context_profile_mask, @intFromEnum(sdl.gl.Profile.core));
    // try sdl.gl.setAttribute(.context_major_version, gl_major);
    // try sdl.gl.setAttribute(.context_minor_version, gl_minor);
    // try sdl.gl.setAttribute(.context_flags, @as(i32, @bitCast(sdl.gl.ContextFlags{ .forward_compatible = true })));

    var window = try sdl.Window.create(
        "zig-gamedev: minimal_sdl_gl",
        sdl.Window.pos_undefined,
        sdl.Window.pos_undefined,
        600,
        600,
        .{
            .opengl = true,
            .allow_highdpi = true,
        },
    );
    defer window.destroy();

    // const gl_context = try sdl.gl.createContext(window);
    // defer sdl.gl.deleteContext(gl_context);
    //
    // try sdl.gl.makeCurrent(window, gl_context);
    // try sdl.gl.setSwapInterval(0);
    //
    // try gl.loadCoreProfile(sdl.gl.getProcAddress, gl_major, gl_minor);
    //
    // {
    //     var w: i32 = undefined;
    //     var h: i32 = undefined;
    //
    //     try window.getSize(&w, &h);
    //     std.debug.print("Window size is {d}x{d}\n", .{ w, h });
    //
    //     sdl.gl.getDrawableSize(window, &w, &h);
    //     std.debug.print("Drawable size is {d}x{d}\n", .{ w, h });
    // }

    // Try to load an image
    var image = try stbi.Image.loadFromFile("assets/pac-tiles.png", 0);
    defer image.deinit();

    var renderer = try sdl.Renderer.create(window, -1, .{ .accelerated = true });
    defer renderer.destroy();

    // var tex: u32 = undefined;
    // gl.genTextures(1, &tex);
    //
    // gl.bindTexture(gl.TEXTURE_2D, tex);
    //
    // gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    // gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    //
    // // if(comp == 3) {
    // //     gl.TexImage2D(gl.TEXTURE_2D, 0, gl.GL_RGB, w, h, 0, gl.GL_RGB, gl.GL_UNSIGNED_BYTE, image);
    // // }
    // // else if(comp == 4) {
    // gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, @intCast(image.width), @intCast(image.height), 0, gl.RGBA, gl.UNSIGNED_BYTE, @ptrCast(image.data));
    // // }
    //
    // gl.bindTexture(gl.TEXTURE_2D, 0);

    std.debug.print("Loaded image, width={}, height={}", .{ image.width, image.height });

    var surf = try sdl.Surface.createRGBSurfaceFrom(image.data, image.width, image.height, 32, image.width * 4, 0x000000FF, // red mask
        0x0000FF00, // green mask
        0x00FF0000, // blue mask
        0xFF000000 // alpha mask
    );

    var tex = try renderer.createTextureFromSurface(surf);

    // var tex = try renderer.createTexture(.rgba8888, .static, @intCast(image.width), @intCast(image.height));
    // defer tex.destroy();
    //
    // var tex_lock = try tex.lock(null);
    // const pitch: usize = @intCast(tex_lock.pitch);
    // const num_elems = 4;
    // for (0..image.height) |y| {
    //     const line_start = y * pitch * num_elems;
    //     const src_line_start = y * image.width;
    //     for (0..image.width) |x| {
    //         var x_start = x + 4;
    //         tex_lock.pixels[line_start + x_start] = image.data[src_line_start + x_start];
    //         tex_lock.pixels[line_start + x_start + 1] = image.data[src_line_start + x_start + 1];
    //         tex_lock.pixels[line_start + x_start + 2] = image.data[src_line_start + x_start + 2];
    //         tex_lock.pixels[line_start + x_start + 3] = image.data[src_line_start + x_start + 3];
    //     }
    // }
    // tex.unlock();

    main_loop: while (true) {
        var event: sdl.Event = undefined;
        while (sdl.pollEvent(&event)) {
            if (event.type == .quit) {
                break :main_loop;
            } else if (event.type == .keydown) {
                if (event.key.keysym.sym == .escape) break :main_loop;
            }
        }
        // gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.2, 0.4, 0.8, 1.0 });
        // sdl.gl.swapWindow(window);
        //

        try renderer.setDrawColorRGB(32, 32, 100);
        try renderer.clear();

        try renderer.setDrawColorRGB(255, 10, 50);
        try renderer.fillRect(.{ .x = 50, .y = 50, .w = 300, .h = 300 });

        var dest = sdl.Rect{ .x = 120, .y = 80, .w = 128, .h = 128 };
        try renderer.copy(tex, null, &dest);

        renderer.present();
    }
}
