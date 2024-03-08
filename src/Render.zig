const std = @import("std");
const c = @import("ffi.zig");
const wayland = @import("wayland");
const zigimg = @import("zigimg");

const Globals = @import("Globals.zig");
const OutputInfo = @import("Outputs.zig").OutputInfo;
const Preload = @import("Preload.zig");

const Allocator = std.mem.Allocator;
const Image = zigimg.Image;
const wl = wayland.client.wl;
const zxdg = wayland.client.zxdg;
const zwlr = wayland.client.zwlr;

const Render = @This();

allocator: Allocator,
surface: *wl.Surface,
layer: *zwlr.LayerSurfaceV1,
egl_display: c.EGLDisplay,
egl_context: c.EGLContext,
egl_window: *wl.EglWindow,
egl_surface: c.EGLSurface,
output_info: OutputInfo,
preload: *Preload,

pub fn init(
    alloc: Allocator,
    compositor: ?*wl.Compositor,
    display: *wl.Display,
    layer_shell: ?*zwlr.LayerShellV1,
    output_info: OutputInfo,
    preload: *Preload,
) !Render {
    const surface = try compositor.?.createSurface();

    // initialize EGL context with OpenGL
    if (c.eglBindAPI(c.EGL_OPENGL_API) == 0) return error.EGLError;
    const egl_dpy = c.eglGetDisplay(@ptrCast(display)) orelse return error.EGLError;
    if (c.eglInitialize(egl_dpy, null, null) != c.EGL_TRUE) return error.EGLError;

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

    const layer_surface = try layer_shell.?.getLayerSurface(
        surface,
        output_info.wl,
        .background,
        "aestuarium",
    );

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

    if (display.roundtrip() != .SUCCESS) return error.RoundtripFail;

    const egl_window = try wl.EglWindow.create(surface, winsize[0], winsize[1]);

    // create EGL surface on EGL window
    const egl_surface = c.eglCreateWindowSurface(
        egl_dpy,
        config,
        @ptrCast(egl_window),
        null,
    ) orelse return error.EGLError;

    // set current OpenGL context to EGL-created context
    if (c.eglMakeCurrent(
        egl_dpy,
        egl_surface,
        egl_surface,
        egl_ctx,
    ) != c.EGL_TRUE) return error.EGLError;

    return Render{
        .allocator = alloc,
        .egl_display = egl_dpy,
        .egl_surface = egl_surface,
        .egl_window = egl_window,
        .egl_context = egl_ctx,
        .layer = layer_surface,
        .surface = surface,
        .output_info = output_info,
        .preload = preload,
    };
}

pub fn setWallpaper(self: *Render, path: []const u8) !void {
    const preloaded = self.preload.findPreloaded(path) orelse return error.ImageNotPreloaded;

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
        1.0, 1.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0, // top right
        1.0, -1.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, // bottom right
        -1.0, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, // bottom left
        -1.0, 1.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0, // top left
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
    c.glVertexAttribPointer(1, 3, c.GL_FLOAT, c.GL_TRUE, stride, @ptrFromInt(3 * @sizeOf(f32)));
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
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR_MIPMAP_LINEAR);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);

    c.glTexImage2D(
        c.GL_TEXTURE_2D,
        0,
        preloaded.format,
        preloaded.width,
        preloaded.height,
        0,
        @intCast(preloaded.format),
        c.GL_UNSIGNED_BYTE,
        preloaded.bytes.ptr,
    );

    c.glGenerateMipmap(c.GL_TEXTURE_2D);

    c.glClearColor(0.0, 0.0, 0.0, 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT);

    c.glDrawElements(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_BYTE, @ptrFromInt(0));

    try getEglError();
    // swap double-buffered framebuffer
    if (c.eglSwapBuffers(self.egl_display, self.egl_surface) != c.EGL_TRUE) return error.EGLError;
}

pub fn deinit(self: *Render) void {
    self.surface.destroy();
    self.layer.destroy();
    _ = c.eglTerminate(self.egl_display);
    _ = c.eglDestroyContext(self.egl_display, self.egl_context);
    _ = c.eglDestroySurface(self.egl_display, self.egl_surface);
}

fn getEglError() !void {
    switch (c.eglGetError()) {
        c.EGL_SUCCESS => return std.log.debug("EGL Successful", .{}),
        c.GL_INVALID_ENUM => return error.GLInvalidEnum,
        c.GL_INVALID_VALUE => return error.GLInvalidValue,
        c.GL_INVALID_OPERATION => return error.GLInvalidOperation,
        c.GL_INVALID_FRAMEBUFFER_OPERATION => return error.GLInvalidFramebufferOperation,
        c.GL_OUT_OF_MEMORY => return error.OutOfMemory,
        else => return error.UnknownEglError,
    }
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
