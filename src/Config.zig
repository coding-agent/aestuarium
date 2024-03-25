const std = @import("std");
const ini = @import("ini");
const kf = @import("known-folders");
const Allocator = std.mem.Allocator;

const MonitorWallpaper = struct {
    monitor: []const u8,
    wallpaper: []const u8,
};

const Heading = enum { monitors, shaders, animations };

const Config = @This();

allocator: Allocator,
monitor_wallpapers: std.ArrayList(MonitorWallpaper),
parser: ini.Parser(std.fs.File.Reader),
vertex_shader: ?[]const u8 = null,
fragment_shader: ?[]const u8 = null,
animation_loop: bool = false,
fps: ?u64 = null,

pub fn init(allocator: Allocator) !*Config {
    var config_dir = try kf.open(allocator, .roaming_configuration, .{}) orelse return error.MissingConfigFile;
    defer config_dir.close();
    const config_path = try kf.getPath(allocator, .roaming_configuration);
    var config_file = try config_dir.openFile("aestuarium/config.ini", .{});
    defer config_file.close();

    var parser = ini.parse(allocator, config_file.reader());

    var monitor_wallpaper = std.ArrayList(MonitorWallpaper).init(std.heap.c_allocator);

    var config = try allocator.create(Config);

    config.allocator = allocator;
    config.parser = parser;

    var current_header: Heading = undefined;

    while (try parser.next()) |record| {
        switch (record) {
            .section => |heading| {
                current_header = std.meta.stringToEnum(Heading, heading) orelse return error.UnknownHeadingConfigFile;
            },

            .property => |kv| {
                switch (current_header) {
                    .monitors => {
                        try monitor_wallpaper.append(.{
                            .monitor = try allocator.dupe(u8, kv.key),
                            .wallpaper = try allocator.dupe(u8, kv.value),
                        });
                    },
                    .shaders => {
                        if (std.mem.eql(u8, "vertex", kv.key)) {
                            var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
                            config.vertex_shader = try allocator.dupe(u8, try std.fmt.bufPrint(&buf, "{s}/aestuarium/{s}", .{ config_path.?, kv.value }));
                        }
                        if (std.mem.eql(u8, "fragment", kv.key)) {
                            var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
                            config.fragment_shader = try allocator.dupe(u8, try std.fmt.bufPrint(&buf, "{s}/aestuarium/{s}", .{ config_path.?, kv.value }));
                        }
                    },
                    .animations => {
                        if (std.mem.eql(u8, "loop", kv.key)) {
                            if (std.mem.eql(u8, "true", kv.value)) {
                                config.animation_loop = true;
                            }
                        }

                        if (std.mem.eql(u8, "fps", kv.key)) {
                            config.fps = try std.fmt.parseInt(u8, kv.value, 10);
                        }
                    },
                }
            },

            .enumeration => {},
        }
    }
    config.monitor_wallpapers = monitor_wallpaper;
    return config;
}

pub fn deinit(self: *Config) void {
    self.monitor_wallpapers.deinit();
    self.parser.deinit();
    self.allocator.destroy(self);
}
