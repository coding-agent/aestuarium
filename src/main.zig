const std = @import("std");
const c = @import("ffi.zig").c;
const wayland = @import("wayland");

const wl = wayland.client.wl;
const zxdg = wayland.client.zxdg;
const zwlr = wayland.client.zwlr;

const Global = @import("globals.zig");

pub fn main() !void {
    std.log.info("Launching aestuarium...", .{});

    const global = try Global.init();
    defer global.deinit();

    std.debug.print("{any}\n", .{global});
}
