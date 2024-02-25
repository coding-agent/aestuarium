const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @import("ffi.zig").c;
const wayland = @import("wayland");

const wl = wayland.client.wl;
const zxdg = wayland.client.zxdg;
const zwlr = wayland.client.zwlr;

const Globals = @import("Globals.zig");

const OutputInfo = struct {
    name: ?[]const u8 = null,
    description: ?[]const u8 = null,
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,

    pub fn deinit(self: OutputInfo, alloc: std.mem.Allocator) void {
        if (self.name) |name| alloc.free(name);
        if (self.description) |description| alloc.free(description);
    }
};

available_outputs: []OutputInfo,

const Outputs = @This();

const XdgOutputListenerData = struct {
    info: *OutputInfo,
    alloc: std.mem.Allocator,
};

pub fn init(alloc: std.mem.Allocator, globals: Globals) !Outputs {
    var info_list = try alloc.alloc(OutputInfo, globals.outputs.items.len);
    errdefer {
        for (info_list) |inf| inf.deinit(alloc);
        alloc.free(info_list);
    }

    for (globals.outputs.items, 0..) |wl_output, i| {
        var info = OutputInfo{};
        const xdg_output = try globals.xdg_output_manager.?.getXdgOutput(wl_output);
        defer xdg_output.destroy();
        xdg_output.setListener(
            *const XdgOutputListenerData,
            xdgOutputListener,
            &.{
                .alloc = alloc,
                .info = &info,
            },
        );
        if (globals.display.roundtrip() != .SUCCESS) return error.RoundtripFail;
        info_list[i] = info;
    }

    return Outputs{ .available_outputs = info_list };
}

pub fn deinit(self: Outputs, alloc: std.mem.Allocator) void {
    for (self.available_outputs) |inf| inf.deinit(alloc);
    alloc.free(self.available_outputs);
}

// TODO optionally add return for json string
/// Caller must free both the returned slice as well as its elements using the supplied allocator.
pub fn listOutputs(self: Outputs, allocator: std.mem.Allocator) ![][]u8 {
    var formatted_list = try allocator.alloc([]u8, self.available_outputs.len);
    // Free both list and elements on error
    errdefer {
        for (formatted_list) |elem| allocator.free(elem);
        allocator.free(formatted_list);
    }

    for (self.available_outputs, 0..) |output, i| {
        const formatted = try std.fmt.allocPrint(allocator,
            \\{?s}
            \\    Description: {?s}
            \\    Resolution: {d}x{d}
            \\    Logical Position: x = {d}; y = {d}
        , .{
            output.name,
            output.description,
            output.width,
            output.height,
            output.x,
            output.y,
        });
        formatted_list[i] = formatted;
    }
    return formatted_list;
}

pub fn findOutputByName(self: Outputs, name: []const u8) ?OutputInfo {
    for (self.available_outputs) |output| {
        if (std.mem.eql(u8, output.name, name)) return output;
    }
    return null;
}

fn xdgOutputListener(
    _: *zxdg.OutputV1,
    ev: zxdg.OutputV1.Event,
    info: *const XdgOutputListenerData,
) void {
    switch (ev) {
        .name => |e| {
            if (info.info.name) |n| info.alloc.free(n);
            // TODO: proper error handling
            info.info.name = info.alloc.dupe(u8, std.mem.span(e.name)) catch @panic("OOM");
        },

        .description => |e| {
            if (info.info.description) |d| info.alloc.free(d);
            // TODO: proper error handling
            info.info.description = info.alloc.dupe(u8, std.mem.span(e.description)) catch @panic("OOM");
        },

        .logical_position => |pos| {
            info.info.x = pos.x;
            info.info.y = pos.y;
        },

        .logical_size => |size| {
            info.info.height = size.height;
            info.info.width = size.width;
        },

        else => {},
    }
}
