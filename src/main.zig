const std = @import("std");
const c = @import("ffi.zig");
const Allocator = std.mem.Allocator;
const zig_args = @import("zig-args");
const args = @import("args.zig");
const Global = @import("globals.zig");
const Output = @import("output.zig");
const ipc = @import("ipc/socket.zig");

const wayland = @import("wayland");
const wl = wayland.client.wl;
const zxdg = wayland.client.zxdg;
const zwlr = wayland.client.zwlr;

pub const std_options = .{
    .logFn = @import("log.zig").log,
    .log_level = .debug,
};

pub fn main() !u8 {
    const mainlog = std.log.scoped(.aestuarium);
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const opts = zig_args.parseWithVerbForCurrentProcess(args.Opts, args.Args, arena.allocator(), .print) catch |err|
        switch (err) {
        error.InvalidArguments => {
            std.log.err("Invalid argument", .{});
            try args.printHelp(arena.allocator());
            return 1;
        },
        else => {
            @panic(@errorName(err));
        },
    };
    defer opts.deinit();

    if (opts.options.help) {
        try args.printHelp(arena.allocator());
        return 0;
    }

    if (opts.options.outputs) {
        var global = try Global.init(arena.allocator());
        defer global.deinit();
        const outputs = try Output.init(&global);
        const output_list = if (opts.options.json)
            try outputs.listOutputs(.{ .format = .json })
        else
            try outputs.listOutputs(.{});

        var stdout_buf = std.io.bufferedWriter(std.io.getStdOut().writer());
        defer stdout_buf.flush() catch {};
        const writer = stdout_buf.writer();

        for (output_list) |output| {
            try writer.print("{s}\n", .{output});
        }
        return 0;
    }

    if (opts.options.json) {
        try args.printHelp(arena.allocator());
        return 1;
    }

    // TODO check for existing instances of the app running
    mainlog.info("Launching app...", .{});

    try ipc.init();
    return 0;
}

fn loop(allocator: Allocator) !u8 {
    var global = try Global.init(allocator);
    defer global.deinit();

    const info = try Output.init(&global);

    const surface = try global.compositor.?.createSurface();

    const layer_surface = try global.layer_shell.?.getLayerSurface(
        surface,
        global.outputs.?.items[0],
        .background,
        "aestuarium",
    );

    var winsize: ?[2]c_int = null;
    layer_surface.setListener(*?[2]c_int, layerSurfaceListener, &winsize);

    layer_surface.setAnchor(.{
        .top = true,
        .right = true,
        .bottom = true,
        .left = true,
    });

    layer_surface.setExclusiveZone(-1);

    var buff: [10000]u8 = undefined;

    const egl_window = try wl.EglWindow.create(surface, @as(c_int, info.available_outputs[0].width), @as(c_int, info.available_outputs[0].height));
    errdefer egl_window.destroy();
    const egl_dpy = c.eglGetDisplay(@ptrCast(global.display.?)) orelse return error.EGLError;
    const egl_image = c.eglCreateImage(global.display.?, c.EGL_NO_CONTEXT, c.EGL_GL_TEXTURE_2D, @ptrCast(&buff), null);
    _ = egl_image; // autofix

    const egl_surf = c.eglCreateWindowSurface(egl_dpy, null, @ptrCast(egl_window), null);
    const resmc = c.eglMakeCurrent(egl_dpy, egl_surf, egl_surf, null);
    if (resmc != c.EGL_TRUE) return error.MakeCurrentFail;
    surface.attach(@ptrCast(egl_surf), 0, 0);

    c.glTextureImage2DEXT(c.GL_2D, 0, c.GL_RGBA, 0, 1920, 1080, 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, @ptrCast(&buff));
    surface.commit();

    if (global.display.?.dispatch() != .SUCCESS) return error.DispatchFail;

    while (true) {
        //todo implement main loop
    }

    return 0;
}

fn layerSurfaceListener(lsurf: *zwlr.LayerSurfaceV1, ev: zwlr.LayerSurfaceV1.Event, winsize: *?[2]c_int) void {
    switch (ev) {
        .configure => |configure| {
            winsize.* = .{ @intCast(configure.width), @intCast(configure.height) };
            lsurf.setSize(configure.width, configure.height);
            lsurf.ackConfigure(configure.serial);
        },
        else => {},
    }
}
