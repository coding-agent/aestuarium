const std = @import("std");
const ini = @import("ini");
const kf = @import("known-folders");
const Allocator = std.mem.Allocator;

const MonitorWallpaper = struct {
    monitor: []const u8,
    wallpaper: []const u8,
};

const Heading = enum {
    monitors,
    shaders,
};

const Config = @This();

allocator: Allocator,
monitor_wallpapers: std.ArrayList(MonitorWallpaper),
parser: ini.Parser(std.fs.File.Reader),
vertex_shader: ?[]const u8,
fragment_shader: ?[]const u8,

pub fn init(allocator: Allocator) !Config {
    var config_dir = try kf.open(allocator, .roaming_configuration, .{}) orelse return error.MissingConfigFile;
    defer config_dir.close();
    const config_path = try kf.getPath(allocator, .roaming_configuration);
    var config_file = try config_dir.openFile("aestuarium/config.ini", .{});
    defer config_file.close();

    var parser = ini.parse(allocator, config_file.reader());

    var monitor_wallpaper = std.ArrayList(MonitorWallpaper).init(std.heap.c_allocator);
    var vertex_shader: ?[]const u8 = try allocator.alloc(u8, std.fs.MAX_PATH_BYTES);
    var fragment_shader: ?[]const u8 = try allocator.alloc(u8, std.fs.MAX_PATH_BYTES);

    vertex_shader = null;
    fragment_shader = null;

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
                            vertex_shader = try allocator.dupe(u8, try std.fmt.bufPrint(&buf, "{s}/aestuarium/{s}", .{ config_path.?, kv.value }));
                        }
                        if (std.mem.eql(u8, "fragment", kv.key)) {
                            var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
                            fragment_shader = try allocator.dupe(u8, try std.fmt.bufPrint(&buf, "{s}/aestuarium/{s}", .{ config_path.?, kv.value }));
                        }
                    },
                }
            },

            .enumeration => {},
        }
    }

    return Config{
        .allocator = allocator,
        .monitor_wallpapers = monitor_wallpaper,
        .parser = parser,
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
    };
}

pub fn deinit(self: *Config) void {
    if (self.vertex_shader) |vs| {
        self.allocator.free(vs);
    }
    if (self.fragment_shader) |fs| {
        self.allocator.free(fs);
    }
    self.monitor_wallpapers.deinit();
    self.parser.deinit();
}
