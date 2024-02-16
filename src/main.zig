const std = @import("std");
const c = @import("ffi.zig").c;
const wayland = @import("wayland");

const wl = wayland.client.wl;
const zxdg = wayland.client.zxdg;
const zwlr = wayland.client.zwlr;

const Global = @import("globals.zig");
const Output = @import("output.zig");

pub fn main() !void {
    std.log.info("Launching aestuarium...", .{});
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();

    var global = try Global.init(arena.allocator());
    defer global.deinit();

    var outputs = std.ArrayList(Output).init(arena.allocator());
    for (global.outputs.?.items) |output| {
        const info = try Output.getOutputInfo(arena.allocator(), output, &global);
        try outputs.append(info);
    }

    if (global.display.?.roundtrip() != .SUCCESS) return error.RoundtipFail;
}
