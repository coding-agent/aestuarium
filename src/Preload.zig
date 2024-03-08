const std = @import("std");
const zigimg = @import("zigimg");
const c = @import("ffi.zig");

const Allocator = std.mem.Allocator;
const Image = zigimg.Image;

const Preload = @This();

alloc: Allocator,
preloaded_list: std.ArrayList(*Preloaded),

const Preloaded = struct {
    index: usize,
    path: []const u8,
    height: c_int,
    width: c_int,
    bytes: []const u8,
    format: c_int,
    zigimg: *Image,
};

pub fn init(alloc: Allocator) Preload {
    return .{
        .alloc = alloc,
        .preloaded_list = std.ArrayList(*Preloaded).init(alloc),
    };
}

pub fn preload(self: *Preload, path: []const u8) !void {
    if (self.findPreloaded(path) != null) {
        std.log.warn("Already preloaded", .{});
        return;
    }

    var image = try zigimg.Image.fromFilePath(self.alloc, path);

    var preloaded = try self.alloc.create(Preloaded);

    std.debug.print("to preload: {s}", .{path});
    const new_mem_path = try self.alloc.alloc(u8, path.len);
    @memcpy(new_mem_path, path);
    preloaded.path = new_mem_path;
    preloaded.bytes = image.rawBytes();
    preloaded.height = @intCast(image.height);
    preloaded.width = @intCast(image.width);
    preloaded.zigimg = &image;

    preloaded.format = try switch (image.pixelFormat()) {
        .rgba32, .rgba64 => c.GL_RGBA,
        .rgb24, .rgb48, .rgb565, .rgb555 => c.GL_RGB,
        .bgr24, .bgr555 => c.GL_BGR,
        .bgra32 => c.GL_BGRA,
        else => error.FormatUnsuported,
    };

    try self.preloaded_list.append(preloaded);

    preloaded.index = self.preloaded_list.items.len - 1;
}

pub fn findPreloaded(self: Preload, path: []const u8) ?*Preloaded {
    for (self.preloaded_list.items) |preloaded| {
        if (std.mem.eql(u8, preloaded.path, path)) {
            return preloaded;
        }
    }
    return null;
}

pub fn unload(self: *Preload, path: []const u8) void {
    if (std.mem.eql(u8, "all", path)) {
        self.preloaded_list.deinit();
        self.preloaded_list = std.ArrayList(*Preloaded).init(self.alloc);
        return;
    }
    if (self.findPreloaded(path)) |preloaded| {
        preloaded.zigimg.deinit();
        self.alloc.destroy(preloaded);
        _ = self.preloaded_list.orderedRemove(preloaded.index);
    }
}

pub fn deinit(self: *Preload) void {
    for (self.preloaded_list.items) |preloaded| {
        preloaded.zigimg.deinit();
        self.alloc.free(preloaded.path);
        self.alloc.destroy(preloaded);
    }
    self.preloaded_list.deinit();
}
