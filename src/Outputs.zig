const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @import("ffi.zig").c;
const wayland = @import("wayland");

const wl = wayland.client.wl;
const zxdg = wayland.client.zxdg;
const zwlr = wayland.client.zwlr;

const Globals = @import("Globals.zig");

pub const OutputInfo = struct {
    name: ?[]const u8 = null,
    description: ?[]const u8 = null,
    height: i32 = 0,
    width: i32 = 0,
    x: i32 = 0,
    y: i32 = 0,
    wl: *wl.Output,
    allocator: Allocator,

    pub fn deinit(self: OutputInfo) void {
        if (self.name) |name| self.allocator.free(name);
        if (self.description) |description| self.allocator.free(description);
    }
};

const ListOutputsOptions = struct {
    json: bool = false,
};

available_outputs: []OutputInfo,
allocator: Allocator,

const Outputs = @This();

const XdgOutputListenerData = struct {
    info: *OutputInfo,
    alloc: std.mem.Allocator,
};

pub fn init(alloc: std.mem.Allocator, wl_outputs: []*wl.Output, xdg_output_manager: ?*zxdg.OutputManagerV1, display: *wl.Display) !Outputs {
    var info_list = try alloc.alloc(OutputInfo, wl_outputs.len);
    errdefer {
        for (info_list) |inf| inf.deinit();
        alloc.free(info_list);
    }

    for (wl_outputs, 0..) |wl_output, i| {
        var info = OutputInfo{
            .wl = wl_output,
            .allocator = alloc,
        };
        const xdg_output = try xdg_output_manager.?.getXdgOutput(wl_output);
        defer xdg_output.destroy();
        xdg_output.setListener(
            *const XdgOutputListenerData,
            xdgOutputListener,
            &.{
                .alloc = alloc,
                .info = &info,
            },
        );
        if (display.roundtrip() != .SUCCESS) return error.RoundtripFail;
        info_list[i] = info;
    }

    return Outputs{ .available_outputs = info_list, .allocator = alloc };
}

pub fn deinit(self: Outputs) void {
    for (self.available_outputs) |inf| inf.deinit();
    self.allocator.free(self.available_outputs);
}

// Caller must free both the returned slice as well as its elements using the supplied allocator.
pub fn listOutputs(self: Outputs, allocator: std.mem.Allocator, options: ListOutputsOptions) ![][]u8 {
    if (options.json) {
        const json = @import("json");
        var formatted_list = try allocator.alloc([]u8, 1);

        // TODO use serialization sbt to prevent memory allocations
        const OutputInfoJson = struct {
            name: ?[]const u8 = null,
            description: ?[]const u8 = null,
            height: i32 = 0,
            width: i32 = 0,
            x: i32 = 0,
            y: i32 = 0,
        };
        var json_outputs = std.ArrayList(OutputInfoJson).init(allocator);
        defer json_outputs.deinit();
        for (self.available_outputs) |o| {
            try json_outputs.append(.{
                .name = o.name,
                .description = o.description,
                .height = o.height,
                .width = o.width,
                .x = o.x,
                .y = o.y,
            });
        }

        formatted_list[0] = @constCast(try json.toPrettySlice(
            allocator,
            json_outputs.items,
        ));
        return formatted_list;
    }

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
        if (std.mem.eql(u8, output.name.?, name)) return output;
    }
    return null;
}

pub fn findOutputByNameWithFallback(self: Outputs, name: ?[]const u8) OutputInfo {
    for (self.available_outputs) |output| {
        if (std.mem.eql(u8, output.name.?, name.?)) return output;
    }

    return self.available_outputs[0];
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
