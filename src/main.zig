const std = @import("std");
const zig_args = @import("zig-args");
const c = @import("ffi.zig");

const args = @import("args.zig");
const Globals = @import("Globals.zig");
const Outputs = @import("Outputs.zig");
const Config = @import("Config.zig");
const render = @import("render.zig");
const Server = @import("ipc/Server.zig");

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
        defer outputs.deinit();

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

    // TODO check for existing instances of the app running
    std.log.info("Launching app...", .{});
    try runMainInstance(alloc);
    return 0;
}

fn runMainInstance(alloc: Allocator) !void {
    const config = try Config.init(alloc);
    defer config.deinit();

    var globals = try Globals.init(alloc);
    defer globals.deinit();

    var rendered_outputs = try alloc.alloc(render, config.monitor_wallpapers.len);
    defer alloc.free(rendered_outputs);

    for (config.monitor_wallpapers, 0..) |mw, i| {
        rendered_outputs[i] = try render.init(alloc, globals, mw.monitor, mw.wallpaper);
    }
    defer for (rendered_outputs, 0..) |_, i| {
        rendered_outputs[i].deinit();
    };

    while (globals.display.dispatch() == .SUCCESS) {}

    //var server = try Server.init(alloc);
    //try server.run();
}
