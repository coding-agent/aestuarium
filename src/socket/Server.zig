const std = @import("std");
const Globals = @import("../Globals.zig");

const fs = std.fs;
const Allocator = std.mem.Allocator;

const Server = @This();

alloc: Allocator,
stream_server: std.net.StreamServer,
fd: c_int,
globals: *Globals,

pub fn init(alloc: Allocator, globals: *Globals) !Server {
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

    std.fs.deleteFileAbsolute(socket_address) catch {};

    const address = try std.net.Address.initUnix(socket_address);
    try server.listen(address);

    std.log.info("Starting IPC server at {s}...", .{socket_address});

    return Server{
        .alloc = alloc,
        .stream_server = server,
        .fd = server.sockfd.?,
        .globals = globals,
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

    std.log.info("incoming message: {s}", .{buff[0..response_size]});

    var it = std.mem.splitAny(u8, buff[0..response_size], " =");

    if (it.next()) |command| {
        if (std.mem.eql(u8, "wallpaper", command)) {
            if (it.next()) |monitor| {
                if (it.next()) |wallpaper| {
                    if (self.globals.rendered_outputs) |rendered_outputs| {
                        for (rendered_outputs, 0..) |output, i| {
                            if (std.mem.eql(u8, output.output_info.name.?, monitor)) {
                                // Trimming because socat add a trailing space
                                self.globals.rendered_outputs.?[i].setWallpaper(std.mem.trim(u8, wallpaper, "\x0a")) catch |err| {
                                    std.log.debug("{s}", .{@errorName(err)});
                                    break;
                                };
                                try writer.writeAll("Changed successfully!");
                                break;
                            }
                        }
                    } else {
                        // TODO initialize new output if available
                        return error.RenderedOutputsNull;
                    }
                }
            }
        }
    }

    try writer.writeByte('\n');
}

pub fn deinit(self: *Server) void {
    self.stream_server.close();
}
