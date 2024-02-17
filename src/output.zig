const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @import("ffi.zig").c;
const wayland = @import("wayland");

const wl = wayland.client.wl;
const zxdg = wayland.client.zxdg;
const zwlr = wayland.client.zwlr;

const Global = @import("globals.zig");

const Output = @This();
name: ?[]const u8 = null,
description: ?[]const u8 = null,
x: i32 = 0,
y: i32 = 0,
width: i32 = 0,
height: i32 = 0,

pub fn getOutputInfo(ally: Allocator, output: *wl.Output, global: *Global) !Output {
    _ = ally; // autofix
    var info = Output{};
    const xdg_output = try global.xdg_output_manager.?.getXdgOutput(output);
    xdg_output.setListener(*Output, xdgOutputListener, &info);
    if (global.display.?.roundtrip() != .SUCCESS) return error.RoundtripFail;
    return info;
}

//TODO complete this
pub fn setWallpaper(globals: Global) void {
    _ = globals; // autofix

}

fn xdgOutputListener(_: *zxdg.OutputV1, ev: zxdg.OutputV1.Event, info: *Output) void {
    switch (ev) {
        .name => |e| {
            info.name = std.mem.span(e.name);
        },

        .description => |e| {
            info.description = std.mem.span(e.description);
        },

        .logical_position => |pos| {
            info.x = pos.x;
            info.y = pos.y;
        },

        .logical_size => |size| {
            info.height = size.height;
            info.width = size.width;
        },

        else => |remaining| {
            std.debug.print("what da heck is this: {any}", .{remaining});
        },
    }
}
