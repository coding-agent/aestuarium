const std = @import("std");
const Globals = @import("../Globals.zig");

const fs = std.fs;
const Allocator = std.mem.Allocator;

const Client = @This();

alloc: Allocator,
stream: std.net.Stream,

pub fn init(alloc: Allocator) !Client {
    var env_map = try std.process.getEnvMap(alloc);
    defer env_map.deinit();

    const xdg_runtime_dir = env_map.get("XDG_RUNTIME_DIR") orelse return error.MissingXDGRuntimeDir;

    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;

    const server_address = try std.fmt.bufPrintZ(
        &buf,
        "{s}/aestuarium.sock",
        .{xdg_runtime_dir},
    );

    const client = try std.net.connectUnixSocket(server_address);

    return Client{
        .alloc = alloc,
        .stream = client,
    };
}

pub fn preload(self: *Client, path: []const u8) !void {
    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    if (!std.fs.path.isAbsolute(path)) {
        return error.PathNotAbsolute;
    }
    try self.stream.writeAll(try std.fmt.bufPrintZ(&buf, "preload {s}", .{path}));
    const reply_len = try self.stream.read(&buf);
    try std.io.getStdOut().writeAll(buf[0 .. reply_len - 1]);
    try std.io.getStdOut().writer().writeByte('\n');
}

pub fn wallpaper(self: *Client, monitor: ?[]const u8, path: []const u8) !void {
    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;

    if (!std.fs.path.isAbsolute(path)) {
        return error.PathNotAbsolute;
    }

    try self.stream.writeAll(try std.fmt.bufPrintZ(&buf, "wallpaper {s}={s}", .{ monitor orelse "", path }));

    const reply_len = try self.stream.read(&buf);
    try std.io.getStdOut().writeAll(buf[0 .. reply_len - 1]);
    try std.io.getStdOut().writer().writeByte('\n');
}

// unload can be a path or "all" to unload all wallpapers
pub fn unload(self: *Client, path: []const u8) !void {
    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;

    if (!std.fs.path.isAbsolute(path) and !std.mem.eql(u8, "all", path)) {
        return error.PathNotAbsolute;
    }

    try self.stream.writeAll(try std.fmt.bufPrintZ(&buf, "unload {s}", .{path}));
    const reply_len = try self.stream.read(&buf);
    try std.io.getStdOut().writeAll(buf[0 .. reply_len - 1]);
    try std.io.getStdOut().writer().writeByte('\n');
}

pub fn deinit(self: *Client) void {
    self.stream.close();
}
