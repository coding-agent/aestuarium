const std = @import("std");
const Allocator = std.mem.Allocator;

pub const version = "0.0.0";

const Outputs = struct {};

pub const Opts = struct {
    help: bool = false,
    outputs: bool = false,
    json: bool = false,
    monitor: ?[]const u8 = null,
    preload: ?[]const u8 = null,
    unload: ?[]const u8 = null,
    wallpaper: ?[]const u8 = null,

    pub const shorthands = .{
        .h = "help",
        .j = "json",
        .m = "monitor",
        .p = "preload",
        .u = "unload",
        .w = "wallpaper",
    };
};

pub const Args = union(enum) {};

const help_msg =
    \\Aestuarium v{[version]s} - yet another wayland wallpaper manager 
    \\
    \\usage: {[a0]s} [options] <commands>
    \\
    \\Options:
    \\    --json, -j        Returns the result in json format
    \\    --monitor, -m     Monitor to set wallpaper
    \\
    \\Subcommands:
    \\    {[a0]s} preload   <path>          Preload file into memory
    \\    {[a0]s} wallpaper <path>          Set wallpaper to output
    \\    {[a0]s} unload    <path/"all">    Unload file/s from memory
    \\    {[a0]s} outputs                   Lists the monitors currently available
    \\    {[a0]s} help                      Print this help and exit
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
