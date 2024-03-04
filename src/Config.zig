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
};

const Config = @This();

allocator: Allocator,
monitor_wallpapers: []MonitorWallpaper,
parser: ini.Parser(std.fs.File.Reader),

pub fn init(allocator: Allocator) !Config {
    var config_dir = try kf.open(allocator, .roaming_configuration, .{});
    defer config_dir.?.close();
    var config_file = try config_dir.?.openFile("aestuarium/config.ini", .{});
    defer config_file.close();

    var parser = ini.parse(allocator, config_file.reader());

    var monitor_wallpaper = std.ArrayList(MonitorWallpaper).init(allocator);

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
                            .monitor = kv.key,
                            .wallpaper = kv.value,
                        });
                    },
                }
            },

            .enumeration => {},
        }
    }

    return Config{
        .allocator = allocator,
        .monitor_wallpapers = try monitor_wallpaper.toOwnedSlice(),
        .parser = parser,
    };
}

pub fn deinit(self: *Config) void {
    self.allocator.free(self.monitor_wallpapers);
    self.parser.deinit();
}
