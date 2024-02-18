const std = @import("std");
const Allocator = std.mem.Allocator;

pub const version = "0.0.0";

const Outputs = struct {};

pub const Opts = struct {
    help: bool = false,
    outputs: bool = false,
    json: bool = false,

    pub const shorthands = .{
        .h = "help",
        .j = "json",
    };
};

pub const Args = union(enum) {};

const help_msg =
    \\Aestuarium v{[version]s} - yet another wayland background manager 
    \\
    \\usage: {[a0]s} [options] <commands>
    \\
    \\Options:
    \\    --json, -j        Returns the result in json format
    \\
    \\subcommands:
    \\    --outputs               Lists the monitors currently available
    \\    --help                  Print this help and exit
;

pub fn printHelp(alloc: Allocator) !void {
    var stdout_buf = std.io.bufferedWriter(std.io.getStdOut().writer());
    defer stdout_buf.flush() catch {};

    var args = try std.process.argsWithAllocator(alloc);
    args.deinit();

    try stdout_buf.writer().print(help_msg, .{
        .a0 = std.fs.path.basename(args.next() orelse return error.BorkedArgs),
        .version = version,
    });
}
