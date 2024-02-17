const std = @import("std");
const Allocator = std.mem.Allocator;
const zig_args = @import("zig-args");
const args = @import("args.zig");
const Global = @import("globals.zig");
const Output = @import("output.zig");

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
        try listOutputs();
        return 0;
    }

    mainlog.info("Launching app...", .{});

    return 0;
}

fn listOutputs() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var stdout_buf = std.io.bufferedWriter(std.io.getStdOut().writer());
    defer stdout_buf.flush() catch {};
    const writer = stdout_buf.writer();

    var global = try Global.init(arena.allocator());
    defer global.deinit();

    for (global.outputs.?.items) |output| {
        const info = try Output.getOutputInfo(arena.allocator(), output, &global);
        try writer.print("{s}\n\tdescrition: {s}\n\tresolution: {d}x{d}\n", .{ info.name.?, info.description.?, info.width, info.height });
    }
}
