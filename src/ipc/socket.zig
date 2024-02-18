const std = @import("std");
const fs = std.fs;
const net = std.net;
const Server = net.StreamServer;
const Allocator = std.mem.Allocator;

const Socket = @This();

pub fn init() !void {
    const logger = std.log.scoped(.IPC);
    var server = Server.init(.{
        .reuse_port = true,
        .reuse_address = true,
    });
    defer server.deinit();

    const path = "/tmp/aestuarium/.aestuarium.sock";

    fs.makeDirAbsolute("/tmp/aestuarium/") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    fs.deleteFileAbsolute("/tmp/aestuarium/.aestuarium.sock") catch {};

    const address = try std.net.Address.initUnix(path);
    try server.listen(address);

    logger.info("Starting IPC server...", .{});

    var buff: [500]u8 = undefined;
    while (true) {
        const conn = try server.accept();

        const bytes = try conn.stream.read(&buff);
        _ = bytes; // autofix
    }
}
