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
    wl_output: *wl.Output,
};

const Output = @This();
available_outputs: []OutputInfo,

pub fn init(global: *Global) !Output {
    var info_list = std.ArrayList(OutputInfo).init(std.heap.c_allocator);
    defer info_list.deinit();

    for (global.outputs.?.items) |wl_output| {
        var info = OutputInfo{
            .wl_output = wl_output,
        };
        const xdg_output = try global.xdg_output_manager.?.getXdgOutput(wl_output);
        xdg_output.setListener(*OutputInfo, xdgOutputListener, &info);
        if (global.display.?.roundtrip() != .SUCCESS) return error.RoundtripFail;
        try info_list.append(info);
    }

    return Output{
        .available_outputs = try info_list.toOwnedSlice(),
    };
}

const ListOutputsOptions = struct {
    format: enum {
        normal,
        json,
    } = .normal,
};

pub fn listOutputs(self: Output, options: ListOutputsOptions) ![][]const u8 {
    switch (options.format) {
        .json => {
            // TODO return json string
            return error.JsonNotYetImplemented;
        },
        .normal => {
            const allocator: Allocator = std.heap.c_allocator;
            var formated_list = std.ArrayList([]const u8).init(allocator);
            defer formated_list.deinit();

            for (self.available_outputs) |output| {
                const formated = try std.fmt.allocPrint(
                    allocator,
                    "{s}\n\tdescrition: {s}\n\tresolution: {d}x{d}\n\tLogical Position:\n\t\tx: {d}\n\t\ty: {d}",
                    .{ output.name, output.description, output.width, output.height, output.x, output.y },
                );
                try formated_list.append(formated);
            }
            return formated_list.toOwnedSlice();
        },
    }
}

pub fn findOutputByName(self: Output, name: []const u8) !OutputInfo {
    for (self.available_outputs) |output| {
        if (std.mem.eql(u8, output.name, name)) return output;
    }
    return error.NoSuchOutput;
}

pub fn findOutputByLogicalPosition(self: Output) !OutputInfo {
    _ = self; // autofix

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

        else => {},
    }
}
