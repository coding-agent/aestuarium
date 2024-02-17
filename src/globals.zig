const std = @import("std");
const Allocator = std.mem.Allocator;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const zxdg = wayland.client.zxdg;
const zwlr = wayland.client.zwlr;

const Collected = @This();
display: ?*wl.Display,
outputs: ?std.ArrayList(*wl.Output),
seat: ?*wl.Seat = null,
compositor: ?*wl.Compositor = null,
layer_shell: ?*zwlr.LayerShellV1 = null,
xdg_output_manager: ?*zxdg.OutputManagerV1 = null,

const EventInterfaces = enum {
    wl_shm,
    wl_compositor,
    wl_output,
    wl_seat,
    wp_viewporter,
    zwlr_layer_shell_v1,
    zxdg_output_manager_v1,
};

pub fn init(ally: Allocator) !Collected {
    const display = try wl.Display.connect(null);
    errdefer display.disconnect();

    const registry = try display.getRegistry();
    defer registry.destroy();

    const collector = try ally.create(Collected);
    collector.* = Collected{
        .display = display,
        .outputs = std.ArrayList(*wl.Output).init(std.heap.c_allocator),
    };

    registry.setListener(*Collected, Collected.registryListener, collector);

    if (display.roundtrip() != .SUCCESS) return error.RoundtripFail;
    inline for (std.meta.fields(Collected)) |*f| {
        if (@field(collector, f.name) == null) return error.MissingRequiredGlobals;
    }

    return collector.*;
}

pub fn deinit(self: Collected) void {
    self.display.?.disconnect();
    self.outputs.?.deinit();
}

fn registryListener(registry: *wl.Registry, ev: wl.Registry.Event, data: *Collected) void {
    switch (ev) {
        .global => |global_event| {
            const event = std.meta.stringToEnum(EventInterfaces, std.mem.span(global_event.interface)) orelse return;
            switch (event) {
                .wl_seat => {
                    data.seat = registry.bind(
                        global_event.name,
                        wl.Seat,
                        global_event.version,
                    ) catch |err| @panic(@errorName(err));
                },

                .wl_compositor => {
                    data.compositor = registry.bind(
                        global_event.name,
                        wl.Compositor,
                        global_event.version,
                    ) catch |err| @panic(@errorName(err));
                },

                .wl_output => {
                    const bound = registry.bind(
                        global_event.name,
                        wl.Output,
                        global_event.version,
                    ) catch |err| @panic(@errorName(err));

                    data.outputs.?.append(bound) catch |err| @panic(@errorName(err));
                },

                .zwlr_layer_shell_v1 => {
                    data.layer_shell = registry.bind(
                        global_event.name,
                        zwlr.LayerShellV1,
                        global_event.version,
                    ) catch |err| @panic(@errorName(err));
                },

                .zxdg_output_manager_v1 => {
                    data.xdg_output_manager = registry.bind(
                        global_event.name,
                        zxdg.OutputManagerV1,
                        global_event.version,
                    ) catch |err| @panic(@errorName(err));
                },

                else => return,
            }
        },

        .global_remove => {},
    }
}
