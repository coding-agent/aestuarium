const std = @import("std");
const zig_args = @import("zig-args");
const zigimg = @import("zigimg");
const Image = zigimg.Image;
const c = @import("ffi.zig");

const args = @import("args.zig");
const Globals = @import("Globals.zig");
const Outputs = @import("Outputs.zig");
const Ipc = @import("ipc/socket.zig");

const Allocator = std.mem.Allocator;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const zxdg = wayland.client.zxdg;
const zwlr = wayland.client.zwlr;

pub const std_options = .{
    .logFn = @import("log.zig").log,
    .log_level = .debug,
};

pub fn main() !u8 {
    // Use a GPA in debug builds and the C alloc otherwise
    var dbg_gpa = if (@import("builtin").mode == .Debug) std.heap.GeneralPurposeAllocator(.{}){} else {};
    defer if (@TypeOf(dbg_gpa) != void) {
        _ = dbg_gpa.deinit();
    };
    const alloc = if (@TypeOf(dbg_gpa) != void) dbg_gpa.allocator() else std.heap.c_allocator;

    const opts = zig_args.parseWithVerbForCurrentProcess(args.Opts, args.Args, alloc, .print) catch |err|
        switch (err) {
        error.InvalidArguments => {
            std.log.err("Invalid argument", .{});
            try args.printHelp(alloc);
            return 1;
        },
        else => return err,
    };
    defer opts.deinit();

    if (opts.options.help) {
        try args.printHelp(alloc);
        return 0;
    }

    if (opts.options.outputs) {
        var globals = try Globals.init(alloc);
        defer globals.deinit();

        const outputs = try Outputs.init(alloc, globals);
        defer outputs.deinit(alloc);

        // TODO: make this directly write to a writer instead of allocating
        const output_list = try outputs.listOutputs(alloc, .{ .json = opts.options.json });
        defer {
            for (output_list) |o| alloc.free(o);
            alloc.free(output_list);
        }

        var stdout_buf = std.io.bufferedWriter(std.io.getStdOut().writer());
        const writer = stdout_buf.writer();

        for (output_list) |output| {
            try writer.print("{s}\n", .{output});
        }

        try stdout_buf.flush();
        return 0;
    }

    if (opts.options.json) {
        try args.printHelp(alloc);
        return 1;
    }

    return runMainLoop(alloc);
}

fn layerSurfaceListener(lsurf: *zwlr.LayerSurfaceV1, ev: zwlr.LayerSurfaceV1.Event, winsize: *[2]c_int) void {
    switch (ev) {
        .configure => |configure| {
            winsize.* = .{ @intCast(configure.width), @intCast(configure.height) };
            lsurf.setSize(configure.width, configure.height);
            lsurf.ackConfigure(configure.serial);
        },
        else => {},
    }
}

fn runMainLoop(alloc: Allocator) !u8 {
    // TODO check for existing instances of the app running
    std.log.info("Launching app...", .{});
    //_ = try std.Thread.spawn(.{}, Ipc.init, .{});

    var globals = try Globals.init(alloc);
    defer globals.deinit();

    const info = try Outputs.init(alloc, globals);
    defer info.deinit(alloc);

    const surface = try globals.compositor.?.createSurface();
    defer surface.destroy();

    // initialize EGL context with OpenGL
    if (c.eglBindAPI(c.EGL_OPENGL_API) == 0) return error.EGLError;
    const egl_dpy = c.eglGetDisplay(@ptrCast(globals.display)) orelse return error.EGLError;
    if (c.eglInitialize(egl_dpy, null, null) != c.EGL_TRUE) return error.EGLError;
    defer _ = c.eglTerminate(egl_dpy);

    const config = egl_conf: {
        var config: c.EGLConfig = undefined;
        var n_config: i32 = 0;
        if (c.eglChooseConfig(
            egl_dpy,
            &[_]i32{
                c.EGL_SURFACE_TYPE,    c.EGL_WINDOW_BIT,
                c.EGL_RENDERABLE_TYPE, c.EGL_OPENGL_BIT,
                c.EGL_RED_SIZE,        8,
                c.EGL_GREEN_SIZE,      8,
                c.EGL_BLUE_SIZE,       8,
                c.EGL_NONE,
            },
            &config,
            1,
            &n_config,
        ) != c.EGL_TRUE) return error.EGLError;
        break :egl_conf config;
    };

    const egl_ctx = c.eglCreateContext(
        egl_dpy,
        config,
        c.EGL_NO_CONTEXT,
        &[_]i32{
            c.EGL_CONTEXT_MAJOR_VERSION,       4,
            c.EGL_CONTEXT_MINOR_VERSION,       3,
            c.EGL_CONTEXT_OPENGL_DEBUG,        c.EGL_TRUE,
            c.EGL_CONTEXT_OPENGL_PROFILE_MASK, c.EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT,
            c.EGL_NONE,
        },
    ) orelse return error.EGLError;
    defer _ = c.eglDestroyContext(egl_dpy, egl_ctx);

    const layer_surface = try globals.layer_shell.?.getLayerSurface(
        surface,
        globals.outputs.items[0],
        .background,
        "aestuarium",
    );
    defer layer_surface.destroy();

    var winsize: [2]c_int = undefined;
    layer_surface.setListener(*[2]c_int, layerSurfaceListener, &winsize);

    layer_surface.setAnchor(.{
        .top = true,
        .right = true,
        .bottom = true,
        .left = true,
    });

    layer_surface.setExclusiveZone(-1);

    surface.commit();

    if (globals.display.roundtrip() != .SUCCESS) return error.RoundtripFail;

    const egl_window = try wl.EglWindow.create(surface, winsize[0], winsize[1]);
    defer egl_window.destroy();

    // create EGL surface on EGL window
    const egl_surface = c.eglCreateWindowSurface(
        egl_dpy,
        config,
        @ptrCast(egl_window),
        null,
    ) orelse return error.EGLError;
    defer _ = c.eglDestroySurface(egl_dpy, egl_surface);

    // set current OpenGL context to EGL-created context
    if (c.eglMakeCurrent(
        egl_dpy,
        egl_surface,
        egl_surface,
        egl_ctx,
    ) != c.EGL_TRUE) return error.EGLError;

    const path = "/home/coding-agent/dev/wallpapers/aqua.png";
    var image = try Image.fromFilePath(alloc, path);
    defer image.deinit();

    var pixel_list = std.ArrayList(c.GLfloat).init(alloc);
    defer pixel_list.deinit();

    const width: c_int = @intCast(image.width);
    const height: c_int = @intCast(image.height);
    const texture = image.rawBytes();

    render(texture, width, height);

    try getEglError();
    // swap double-buffered framebuffer
    if (c.eglSwapBuffers(egl_dpy, egl_surface) != c.EGL_TRUE) return error.EGLError;

    while (globals.display.dispatch() == .SUCCESS) {}

    return 1;
}

fn getEglError() !void {
    switch (c.eglGetError()) {
        c.EGL_SUCCESS => return std.log.info("EGL Successful", .{}),
        c.GL_INVALID_ENUM => return error.GLInvalidEnum,
        c.GL_INVALID_VALUE => return error.GLInvalidValue,
        c.GL_INVALID_OPERATION => return error.GLInvalidOperation,
        c.GL_INVALID_FRAMEBUFFER_OPERATION => return error.GLInvalidFramebufferOperation,
        c.GL_OUT_OF_MEMORY => return error.GLOutOfMemory,
        else => return error.unkown,
    }
}

fn render(texture: ?[]const u8, width: c_int, height: c_int) void {
    // Vertex Shader
    const vertexShaderSource = @embedFile("shaders/main_vertex_shader.glsl");
    // Fragment Shader
    const fragmentShaderSource = @embedFile("shaders/main_fragment_shader.glsl");

    const vshader = c.glCreateShader(c.GL_VERTEX_SHADER);
    const fshader = c.glCreateShader(c.GL_FRAGMENT_SHADER);
    defer c.glDeleteShader(vshader);
    defer c.glDeleteShader(fshader);

    c.glShaderSource(
        vshader,
        1,
        @ptrCast(&vertexShaderSource),
        &[_]c_int{@as(c_int, @intCast(vertexShaderSource.len))},
    );
    c.glShaderSource(
        fshader,
        1,
        @ptrCast(&fragmentShaderSource),
        &[_]c_int{@as(c_int, @intCast(fragmentShaderSource.len))},
    );

    c.glCompileShader(vshader);
    c.glCompileShader(fshader);

    // check vertex shader compilation errors
    var vshader_success: c_int = 0;
    c.glGetShaderiv(vshader, c.GL_COMPILE_STATUS, &vshader_success);
    if (vshader_success == 0) {
        var log: [512]u8 = undefined;
        c.glGetShaderInfoLog(vshader, 512, null, &log);
        std.log.err("vertext shader {s}", .{log});
    }

    var fshader_success: c_int = 0;
    // check fragment shader compilation errors
    c.glGetShaderiv(vshader, c.GL_COMPILE_STATUS, &fshader_success);
    if (fshader_success == 0) {
        var log: [512]u8 = undefined;
        c.glGetShaderInfoLog(fshader, 512, null, &log);
        std.log.err("fragment shader {s}", .{log});
    }

    const shaderProgram = c.glCreateProgram();
    c.glAttachShader(shaderProgram, vshader);
    c.glAttachShader(shaderProgram, fshader);
    c.glLinkProgram(shaderProgram);
    var link_success: c_int = undefined;
    // check linking errors in shader program
    c.glGetProgramiv(shaderProgram, c.GL_LINK_STATUS, &link_success);
    if (link_success == 0) {
        var log: [512]u8 = undefined;
        c.glGetProgramInfoLog(shaderProgram, 512, null, &log);
        std.log.err("shader program linking {s}", .{log});
    }

    c.glUseProgram(shaderProgram);

    const vertices = &[_]f32{
        // positions    // colors       // texture coords
        0.5, 0.5, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0, // top right
        0.5, -0.5, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, // bottom right
        -0.5, -0.5, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, // bottom left
        -0.5, 0.5, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0, // top left
    };

    const indices = &[_]u8{
        0, 1, 3, // first triangle
        1, 2, 3, // second triangle
    };
    var VAO: c_uint = undefined;
    var VBO: c_uint = undefined;
    var EBO: c_uint = undefined;

    c.glGenVertexArrays(1, &VAO);
    c.glGenBuffers(1, &VBO);
    c.glGenBuffers(1, &EBO);

    defer c.glDeleteVertexArrays(1, &VAO);
    defer c.glDeleteBuffers(1, &VBO);
    defer c.glDeleteBuffers(1, &EBO);

    c.glBindVertexArray(VAO);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, VBO);
    c.glBufferData(c.GL_ARRAY_BUFFER, vertices.len * 4, vertices, c.GL_STATIC_DRAW);

    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, EBO);
    c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, indices.len * 4, indices, c.GL_STATIC_DRAW);

    const stride = 8 * @sizeOf(f32);
    // position attribute
    c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(0));
    c.glEnableVertexAttribArray(0);
    // color attribute
    c.glVertexAttribPointer(1, 3, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(3 * @sizeOf(f32)));
    c.glEnableVertexAttribArray(1);
    // texture coord attribute
    c.glVertexAttribPointer(2, 2, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(6 * @sizeOf(f32)));
    c.glEnableVertexAttribArray(2);

    c.glBindVertexArray(VAO);

    var texture_id: c.GLuint = undefined;
    c.glGenTextures(1, &texture_id);
    c.glBindTexture(c.GL_TEXTURE_2D, texture_id);

    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);

    c.glTexImage2D(
        c.GL_TEXTURE_2D,
        0,
        c.GL_RGBA,
        width,
        height,
        0,
        c.GL_RGBA,
        c.GL_UNSIGNED_BYTE,
        texture.?.ptr,
    );

    c.glGenerateMipmap(c.GL_TEXTURE_2D);

    c.glClearColor(0.0, 0.0, 0.1, 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT);

    c.glDrawElements(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_BYTE, @ptrFromInt(0));
}
