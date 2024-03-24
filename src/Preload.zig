const std = @import("std");
const zigimg = @import("zigimg");
const c = @import("ffi.zig");

const Allocator = std.mem.Allocator;
const Image = zigimg.Image;

const Preload = @This();

alloc: Allocator,
pool: std.heap.MemoryPool(ImageData),
preloaded_list: std.ArrayList(*ImageData),
mem_usage: usize = 0,

pub const ImageData = struct {
    path: []const u8,
    height: c_int,
    width: c_int,
    bytes: [][]const u8,
    // OpenGL Format
    format: c_int,
    zigimg: *Image,
    is_animation: bool = false,
};

pub fn init(alloc: Allocator) Preload {
    return .{
        .alloc = alloc,
        .pool = std.heap.MemoryPool(ImageData).init(alloc),
        .preloaded_list = std.ArrayList(*ImageData).init(alloc),
    };
}

pub fn preload(self: *Preload, path: []const u8) !void {
    if (self.findImageData(path) != null) {
        std.log.warn("Already preloaded", .{});
        return;
    }

    var image = try zigimg.Image.fromFilePath(self.alloc, path);

    var preloaded = try self.pool.create();

    const new_mem_path = try self.alloc.alloc(u8, path.len);
    @memcpy(new_mem_path, path);
    preloaded.path = new_mem_path;
    preloaded.height = @intCast(image.height);
    preloaded.width = @intCast(image.width);
    preloaded.zigimg = &image;
    preloaded.is_animation = image.isAnimation();

    if (image.isAnimation()) {
        preloaded.bytes = try self.alloc.alloc([]u8, image.animation.frames.items.len);
        for (image.animation.frames.items, 0..) |frame, i| {
            var bytes = try self.alloc.alloc(u8, frame.pixels.asBytes().len);
            bytes = frame.pixels.asBytes();
            self.mem_usage += bytes.len;
            preloaded.bytes[i] = bytes;
        }
    } else {
        preloaded.bytes = try self.alloc.alloc([]u8, 1);
        var bytes = try self.alloc.alloc(u8, image.rawBytes().len);
        bytes = try self.alloc.dupe(u8, image.rawBytes());
        self.mem_usage += bytes.len;
        preloaded.bytes[0] = bytes;
    }

    std.log.info("Mem Usage: {d}MB", .{self.mem_usage / (1024 * 1024)});

    preloaded.format = try switch (image.pixelFormat()) {
        .rgba32, .rgba64 => c.GL_RGBA,
        .rgb24, .rgb48, .rgb565, .rgb555 => c.GL_RGB,
        .bgr24, .bgr555 => c.GL_BGR,
        .bgra32 => c.GL_BGRA,
        else => error.FormatUnsuported,
    };

    try self.preloaded_list.append(preloaded);
}

pub fn findImageData(self: Preload, path: []const u8) ?*ImageData {
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
        self.preloaded_list = std.ArrayList(*ImageData).init(self.alloc);
        self.mem_usage = 0;
        return;
    }
    if (self.findImageData(path)) |preloaded| {
        preloaded.zigimg.deinit();
        self.alloc.destroy(preloaded);
        for (self.preloaded_list.items, 0..) |preloaded_img, i| {
            if (std.mem.eql(u8, preloaded_img.path, path)) {
                self.pool.destroy(self.preloaded_list.items[i]);
                _ = self.preloaded_list.swapRemove(i);
            }
            break;
        }
        self.mem_usage -= preloaded.bytes.len;
    }
}

pub fn deinit(self: *Preload) void {
    for (self.preloaded_list.items) |preloaded| {
        self.alloc.free(preloaded.bytes);
        self.alloc.free(preloaded.path);
        preloaded.zigimg.deinit();
        self.alloc.destroy(preloaded);
    }
    self.preloaded_list.deinit();
}
