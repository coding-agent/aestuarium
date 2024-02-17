const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @import("ffi.zig").c;
const wayland = @import("wayland");

const wl = wayland.client.wl;
const zxdg = wayland.client.zxdg;
const zwlr = wayland.client.zwlr;

const Global = @import("globals.zig");

const OutputInfo = struct {
    name: []const u8 = "",
    description: []const u8 = "",
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
};

const Output = @This();
available_outputs: []OutputInfo,

pub fn init(global: *Global) !Output {
    var info_list = std.ArrayList(OutputInfo).init(std.heap.c_allocator);
    defer info_list.deinit();

    for (global.outputs.?.items) |wl_output| {
        var info = OutputInfo{};
        const xdg_output = try global.xdg_output_manager.?.getXdgOutput(wl_output);
        xdg_output.setListener(*OutputInfo, xdgOutputListener, &info);
        if (global.display.?.roundtrip() != .SUCCESS) return error.RoundtripFail;
        try info_list.append(info);
    }

    return Output{
        .available_outputs = try info_list.toOwnedSlice(),
    };
}

pub fn listOutputs(self: Output) !void {
    var stdout_buf = std.io.bufferedWriter(std.io.getStdOut().writer());
    defer stdout_buf.flush() catch {};
    const writer = stdout_buf.writer();

    for (self.available_outputs) |output| {
        try writer.print("{s}\n\tdescrition: {s}\n\tresolution: {d}x{d}\n", .{ output.name, output.description, output.width, output.height });
    }
}

fn xdgOutputListener(_: *zxdg.OutputV1, ev: zxdg.OutputV1.Event, info: *OutputInfo) void {
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
