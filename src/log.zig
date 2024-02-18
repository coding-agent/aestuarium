const std = @import("std");

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    var stdout_buf = std.io.bufferedWriter(std.io.getStdOut().writer());
    defer stdout_buf.flush() catch {};

    const stdout = stdout_buf.writer();

    const prefix = switch (level) {
        .debug => "D: ",
        .info => "",
        .warn => "W: ",
        .err => "E: ",
    };

    switch (scope) {
        .default => {},
        else => {
            stdout.print("[" ++ @tagName(scope) ++ "] ", args) catch {};
        },
    }

    stdout.print(prefix ++ format ++ "\n", args) catch {};
}
