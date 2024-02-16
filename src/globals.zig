const std = @import("std");
const wayland = @import("wayland");
const c = @import("ffi.zig").c;
const wl = wayland.client.wl;
const zxdg = wayland.client.zxdg;
const zwlr = wayland.client.zwlr;

const Collected = @This();
display: *wl.Display,
seat: ?*wl.Seat,
compositor: ?*wl.Compositor,
layer_shell: ?*zwlr.LayerShellV1,
xdg_output_manager: ?*zxdg.OutputManagerV1,

const EventInterfaces = enum {
    wl_shm,
    wl_compositor,
    wl_output,
    wl_seat,
    wp_viewporter,
    zwlr_layer_shell_v1,
    zxdg_output_manager_v1,
};

pub fn init() !Collected {
    const display = try wl.Display.connect(null);

    const registry = try display.getRegistry();
    defer registry.destroy();

    var collector = Collected{
        .display = display,
        .compositor = null,
        .xdg_output_manager = null,
        .seat = null,
        .layer_shell = null,
    };

    registry.setListener(*Collected, Collected.registryListener, &collector);

    if (display.roundtrip() != .SUCCESS) return error.RoundtripFail;

    return collector;
}

pub fn registryListener(registry: *wl.Registry, ev: wl.Registry.Event, data: *Collected) void {
    switch (ev) {
        .global => |global_event| {
            const event = std.meta.stringToEnum(EventInterfaces, std.mem.span(global_event.interface)) orelse return;
            switch (event) {
                .wl_seat => {
                    data.seat = registry.bind(
                        global_event.name,
                        wl.Seat,
                        global_event.version,
                    ) catch @panic("OOM");
                },

                .wl_compositor => {
                    data.compositor = registry.bind(
                        global_event.name,
                        wl.Compositor,
                        global_event.version,
                    ) catch @panic("OOM");
                },

                .zwlr_layer_shell_v1 => {
                    data.layer_shell = registry.bind(
                        global_event.name,
                        zwlr.LayerShellV1,
                        global_event.version,
                    ) catch @panic("OOM");
                },

                .zxdg_output_manager_v1 => {
                    data.xdg_output_manager = registry.bind(
                        global_event.name,
                        zxdg.OutputManagerV1,
                        global_event.version,
                    ) catch @panic("OOM");
                },

                else => return,
            }

            std.log.info("Binding Global\n \tname: {d}\n \tinterface: {s}\n \tversion: {d}\n", .{
                global_event.name,
                global_event.interface,
                global_event.version,
            });
        },

        .global_remove => {},
    }
}

pub fn deinit(self: *Collected) !void {
    self.display.?.disconnect();
    self.compositor.?.destroy();
    self.layer_shell.?.destroy();
    self.seat.?.destroy();
    self.xdg_output_manager.destroy();
}
