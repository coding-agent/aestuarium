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

pub fn init(allocator: Allocator) !Config {
    const config_dir = try kf.open(allocator, .roaming_configuration, .{});
    const config_file = try config_dir.?.openFile("aestuarium/config.ini", .{});

    var parser = ini.parse(allocator, config_file.reader());

    var monitor_wallpaper = std.ArrayList(MonitorWallpaper).init(allocator);
    defer monitor_wallpaper.deinit();

    var current_header: Heading = undefined;

    while (try parser.next()) |record| {
        switch (record) {
            .section => |heading| {
                current_header = std.meta.stringToEnum(Heading, heading) orelse return error.UnkownHeadingConfigFile;
            },

            .property => |kv| {
                switch (current_header) {
                    .monitors => {
                        try monitor_wallpaper.append(MonitorWallpaper{
                            .monitor = kv.key,
                            .wallpaper = kv.value,
                        });
                    },
                }
            },

            .enumeration => {},
        }
    }
    var mw = try allocator.alloc(MonitorWallpaper, monitor_wallpaper.items.len);
    mw = try monitor_wallpaper.toOwnedSlice();

    return Config{
        .allocator = allocator,
        .monitor_wallpapers = mw,
    };
}

pub fn deinit(self: Config) void {
    for (self.monitor_wallpapers) |_| {
        self.allocator.free(self.monitor_wallpapers);
    }
}
