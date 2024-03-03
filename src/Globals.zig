const std = @import("std");
const Outputs = @import("Outputs.zig");
const Allocator = std.mem.Allocator;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const zxdg = wayland.client.zxdg;
const zwlr = wayland.client.zwlr;

alloc: Allocator,
display: *wl.Display,
outputs: std.ArrayList(*wl.Output),
seat: ?*wl.Seat = null,
compositor: ?*wl.Compositor = null,
layer_shell: ?*zwlr.LayerShellV1 = null,
xdg_output_manager: ?*zxdg.OutputManagerV1 = null,
outputs_info: ?Outputs = null,

const Globals = @This();

const EventInterfaces = enum {
    wl_shm,
    wl_compositor,
    wl_output,
    wl_seat,
    wp_viewporter,
    zwlr_layer_shell_v1,
    zxdg_output_manager_v1,
};

pub fn init(alloc: std.mem.Allocator) !Globals {
    const display = try wl.Display.connect(null);
    errdefer display.disconnect();

    const registry = try display.getRegistry();
    defer registry.destroy();

    var self = Globals{
        .alloc = alloc,
        .display = display,
        .outputs = std.ArrayList(*wl.Output).init(alloc),
    };

    registry.setListener(*Globals, Globals.registryListener, &self);

    if (display.roundtrip() != .SUCCESS) return error.RoundtripFail;

    self.outputs_info = try Outputs.init(
        alloc,
        try self.outputs.toOwnedSlice(),
        self.xdg_output_manager,
        self.display,
    );

    inline for (std.meta.fields(Globals)) |*f| {
        if (@typeInfo(@TypeOf(f.type)) == .Optional and
            @field(self, f.name) == null) return error.MissingRequiredGlobals;
    }

    return self;
}

pub fn deinit(self: Globals) void {
    self.display.disconnect();
    self.outputs.deinit();
    if (self.outputs_info) |*o| {
        o.deinit();
    }
}

fn registryListener(registry: *wl.Registry, ev: wl.Registry.Event, data: *Globals) void {
    switch (ev) {
        .global => |global_event| {
            const event = std.meta.stringToEnum(EventInterfaces, std.mem.span(global_event.interface)) orelse return;
            switch (event) {
                .wl_seat => {
                    data.seat = registry.bind(
                        global_event.name,
                        wl.Seat,
                        wl.Seat.generated_version,
                    ) catch |err| @panic(@errorName(err));
                },

                .wl_compositor => {
                    data.compositor = registry.bind(
                        global_event.name,
                        wl.Compositor,
                        wl.Compositor.generated_version,
                    ) catch |err| @panic(@errorName(err));
                },

                .wl_output => {
                    const bound = registry.bind(
                        global_event.name,
                        wl.Output,
                        wl.Output.generated_version,
                    ) catch |err| @panic(@errorName(err));

                    data.outputs.append(bound) catch |err| @panic(@errorName(err));
                },

                .zwlr_layer_shell_v1 => {
                    data.layer_shell = registry.bind(
                        global_event.name,
                        zwlr.LayerShellV1,
                        zwlr.LayerShellV1.generated_version,
                    ) catch |err| @panic(@errorName(err));
                },

                .zxdg_output_manager_v1 => {
                    data.xdg_output_manager = registry.bind(
                        global_event.name,
                        zxdg.OutputManagerV1,
                        zxdg.OutputManagerV1.generated_version,
                    ) catch |err| @panic(@errorName(err));
                },

                else => return,
            }
        },

        .global_remove => |global_remove| {
            _ = global_remove; // autofix

        },
    }
}
