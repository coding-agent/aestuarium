const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

const Server = @This();

alloc: Allocator,
stream_server: std.net.StreamServer,
fd: c_int,

pub fn init(alloc: Allocator) !Server {
    var server = std.net.StreamServer.init(.{
        .reuse_port = true,
        .reuse_address = true,
    });

    var env_map = try std.process.getEnvMap(alloc);
    defer env_map.deinit();

    const xdg_runtime_dir = env_map.get("XDG_RUNTIME_DIR") orelse return error.MissingXDGRuntimeDir;

    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const socket_address = try std.fmt.bufPrintZ(
        &buf,
        "{s}/aestuarium.sock",
        .{xdg_runtime_dir},
    );
    const address = try std.net.Address.initUnix(socket_address);
    try server.listen(address);

    std.log.info("Starting IPC server at {s}...", .{socket_address});
    return Server{
        .alloc = alloc,
        .stream_server = server,
        .fd = server.sockfd.?,
    };
}

pub fn handleConnection(self: *Server) !void {
    const connection = try self.stream_server.accept();
    defer connection.stream.close();
    std.log.info("Accepting incoming connection...", .{});

    var buff: [std.fs.MAX_PATH_BYTES + 200]u8 = undefined;
    var reader = connection.stream.reader();
    var writer = connection.stream.writer();
    const response_size = try reader.readAll(&buff);

    std.log.debug("incoming message: {s}", .{buff[0..response_size]});
    const reply = try interpretMessage(buff[0..response_size]);

    try writer.writeAll(reply);
}

pub fn deinit(self: *Server) void {
    self.stream_server.close();
}

fn interpretMessage(message: []const u8) ![]const u8 {
    var it = std.mem.split(u8, message, " =");

    if (it.next()) |word| {
        if (std.mem.eql(u8, "wallpaper", word)) {
            if (it.next()) |monitor| {
                if (it.next()) |wallpaper| {
                    var buf: [4096]u8 = undefined;
                    return std.fmt.bufPrintZ(&buf, "{s}={s}", .{ monitor, wallpaper });
                }
            }
        }
    }

    return "unknown message";
}
