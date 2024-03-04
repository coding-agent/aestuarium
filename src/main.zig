const std = @import("std");
const zig_args = @import("zig-args");
const c = @import("ffi.zig");

const args = @import("args.zig");
const Globals = @import("Globals.zig");
const Outputs = @import("Outputs.zig");
const Config = @import("Config.zig");
const Render = @import("Render.zig");
const Server = @import("socket/Server.zig");

const Allocator = std.mem.Allocator;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const zxdg = wayland.client.zxdg;
const zwlr = wayland.client.zwlr;

pub const std_options = .{
    .logFn = @import("log.zig").log,
    .log_level = .debug,
};

pub fn main() !u8 {
    // Use a GPA in debug builds and the C alloc otherwise
    var dbg_gpa = if (@import("builtin").mode == .Debug) std.heap.GeneralPurposeAllocator(.{}){} else {};
    defer if (@TypeOf(dbg_gpa) != void) {
        _ = dbg_gpa.deinit();
    };
    const alloc = if (@TypeOf(dbg_gpa) != void) dbg_gpa.allocator() else std.heap.c_allocator;

    const opts = zig_args.parseWithVerbForCurrentProcess(args.Opts, args.Args, alloc, .print) catch |err|
        switch (err) {
        error.InvalidArguments => {
            std.log.err("Invalid argument", .{});
            try args.printHelp(alloc);
            return 1;
        },
        else => return err,
    };
    defer opts.deinit();

    if (opts.options.help) {
        try args.printHelp(alloc);
        return 0;
    }

    if (opts.options.outputs) {
        var globals = try Globals.init(alloc);
        defer globals.deinit();

        // TODO: make this directly write to a writer instead of allocating
        const output_list = try globals.outputs_info.?.listOutputs(alloc, .{ .json = opts.options.json });
        defer {
            for (output_list) |o| alloc.free(o);
            alloc.free(output_list);
        }

        var stdout_buf = std.io.bufferedWriter(std.io.getStdOut().writer());
        const writer = stdout_buf.writer();

        for (output_list) |output| {
            try writer.print("{s}\n", .{output});
        }

        try stdout_buf.flush();
        return 0;
    }

    if (opts.options.json) {
        try args.printHelp(alloc);
        return 1;
    }

    // TODO check for existing instances of the app running
    return try runMainInstance(alloc);
}

fn runMainInstance(alloc: Allocator) !u8 {
    std.log.info("Launching app...", .{});
    var config = try Config.init(alloc);
    defer config.deinit();

    var globals = try Globals.init(alloc);
    defer globals.deinit();

    const rendered_outputs = std.ArrayList(*Render).init(alloc);
    defer rendered_outputs.deinit();

    for (config.monitor_wallpapers) |mw| {
        const output_info = globals.outputs_info.?.findOutputByName(mw.monitor) orelse {
            std.log.warn("Monitor {s} not found", .{mw.monitor});
            continue;
        };
        var rendered = try Render.init(
            alloc,
            globals.compositor,
            globals.display,
            globals.layer_shell,
            output_info,
        );
        try rendered.setWallpaper(mw.wallpaper);
    }
    defer for (rendered_outputs.items, 0..) |_, i| {
        rendered_outputs.items[i].deinit();
    };

    var server = try Server.init(alloc);
    defer server.deinit();

    const display_fd = globals.display.getFd();

    const epoll_fd = c.epoll_create1(0);
    if (epoll_fd == -1) {
        std.log.err("failed to create epoll fd", .{});
        return 1;
    }

    var ev: c.epoll_event = undefined;
    ev.events = c.EPOLLIN;
    ev.data.fd = display_fd;
    if (c.epoll_ctl(epoll_fd, c.EPOLL_CTL_ADD, display_fd, &ev) == -1) {
        std.log.err("failed to add wayland display event to epoll", .{});
        return 1;
    }

    ev.events = c.EPOLLIN;
    ev.data.fd = server.fd;
    if (c.epoll_ctl(epoll_fd, c.EPOLL_CTL_ADD, server.fd, &ev) == -1) {
        std.log.err("failed to add socket server event to epoll", .{});
        return 1;
    }

    while (true) {
        var epoll_events: [2]c.epoll_event = undefined;
        const ev_count = c.epoll_wait(epoll_fd, &epoll_events, 2, -1);
        if (ev_count == -1) {
            std.log.err("epoll wait failed", .{});
            return 1;
        }

        var i: usize = 0;
        while (i <= ev_count) : (i += 1) {
            if (epoll_events[i].data.fd == display_fd) {
                std.log.info("epoll display global event", .{});
                if (globals.display.dispatch() != .SUCCESS) return error.foo;
            }
            if (epoll_events[i].data.fd == server.fd) {
                std.log.info("epoll socket server event", .{});
                try server.handleConnection();
            }
        }
    }

    return 0;
}

fn registryListener(display: *wl.Display) !void {
    while (display.dispatch() == .SUCCESS) {}
}
