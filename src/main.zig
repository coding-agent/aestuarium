const std = @import("std");
const Allocator = std.mem.Allocator;
const zig_args = @import("zig-args");
const args = @import("args.zig");
const Global = @import("globals.zig");
const Output = @import("output.zig");

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

    const opts = zig_args.parseForCurrentProcess(args.Opts, arena.allocator(), .print) catch |err|
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
        const output_list = try outputs.listOutputs();

        var stdout_buf = std.io.bufferedWriter(std.io.getStdOut().writer());
        defer stdout_buf.flush() catch {};
        const writer = stdout_buf.writer();

        for (output_list) |output| {
            try writer.print("{s}\n", .{output});
        }
        return 0;
    }

    // TODO check for existing instances of the app running
    mainlog.info("Launching app...", .{});

    var global = try Global.init(arena.allocator());
    defer global.deinit();

    const info = try Output.init(&global);

    const surface = try global.compositor.?.createSurface();
    const egl_window = try wl.EglWindow.create(surface, @as(c_int, info.available_outputs[0].width), @as(c_int, info.available_outputs[0].height));
    errdefer egl_window.destroy();

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

    surface.commit();

    while (global.display.?.dispatch() == .SUCCESS) {
        //TODO main loop

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
