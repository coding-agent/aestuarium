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

    return Server{
        .alloc = alloc,
        .stream_server = server,
        .fd = server.sockfd.?,
        .globals = globals,
    };
}

pub fn handleConnection(self: *Server) !void {
    const connection = try self.stream_server.accept();
    errdefer connection.stream.close();

    var buff: [std.fs.MAX_PATH_BYTES + 200]u8 = undefined;
    const response_size = try connection.stream.read(&buff);

    var it = std.mem.splitAny(u8, buff[0..response_size], " =");

    if (it.next()) |command| {
        if (std.mem.eql(u8, "preload", command)) {
            if (it.next()) |wallpaper| {
                self.globals.preloaded.?.preload(std.mem.trim(u8, wallpaper, "\x0a")) catch |err| {
                    std.log.err("{s}", .{@errorName(err)});
                    _ = try connection.stream.write(@errorName(err));
                    return;
                };
                _ = try connection.stream.writer().print("Preloaded!\nCurrent mem usage {d}mb\n", .{self.globals.preloaded.?.mem_usage / (1024 * 1024)});
                return;
            }
        }

        if (std.mem.eql(u8, "wallpaper", command)) {
            if (it.next()) |monitor| {
                if (it.next()) |wallpaper| {
                    if (self.globals.rendered_outputs) |rendered_outputs| {
                        for (rendered_outputs, 0..) |output, i| {
                            if (std.mem.eql(u8, output.output_info.name.?, monitor)) {
                                // Trimming because socat add a trailing space
                                self.globals.rendered_outputs.?[i].setWallpaper(std.mem.trim(u8, wallpaper, "\x0a")) catch |err| {
                                    std.log.err("{s}", .{@errorName(err)});
                                    _ = try connection.stream.write(@errorName(err));
                                    connection.stream.close();
                                    return;
                                };
                                _ = try connection.stream.writer().write("Changed successfully!\n");
                                break;
                            }
                        }
                    } else {
                        // TODO initialize new output if available
                        return error.RenderedOutputsNull;
                    }
                }
                return;
            }
            _ = try connection.stream.write("wrong syntax");
        }
        if (std.mem.eql(u8, "unload", command)) {
            if (it.next()) |wallpaper| {
                self.globals.preloaded.?.unload(wallpaper);
                _ = try connection.stream.writer().print("Unloaded!\nCurrent mem usage {d}MB\n", .{self.globals.preloaded.?.mem_usage});
            }
        }
    }
}

pub fn deinit(self: *Server) void {
    self.stream_server.close();
}
