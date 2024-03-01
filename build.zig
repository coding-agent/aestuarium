const std = @import("std");
const Scanner = @import("zig-wayland").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zig_args_mod = b.dependency("zig-args", .{
        .target = target,
        .optimize = optimize,
    }).module("args");

    const zigimg_mod = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    }).module("zigimg");

    const getty_mod = b.dependency("json", .{
        .target = target,
        .optimize = optimize,
    }).module("json");

    const ini_mod = b.dependency("ini", .{
        .target = target,
        .optimize = optimize,
    }).module("ini");

    const known_folders_mod = b.dependency("known-folders", .{}).module("known-folders");

    const scanner = Scanner.create(b, .{});
    const wayland_mod = scanner.mod;

    const exe = b.addExecutable(.{
        .name = "aestuarium",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("wayland", wayland_mod);
    exe.root_module.addImport("zig-args", zig_args_mod);
    exe.root_module.addImport("zigimg", zigimg_mod);
    exe.root_module.addImport("json", getty_mod);
    exe.root_module.addImport("ini", ini_mod);
    exe.root_module.addImport("known-folders", known_folders_mod);

    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addSystemProtocol("unstable/xdg-output/xdg-output-unstable-v1.xml");
    scanner.addCustomProtocol("protocols/wlr-layer-shell-unstable-v1.xml");

    scanner.generate("wl_compositor", 5);
    scanner.generate("wl_shm", 1);
    scanner.generate("zwlr_layer_shell_v1", 4);
    scanner.generate("zxdg_output_manager_v1", 3);
    scanner.generate("xdg_wm_base", 5);
    scanner.generate("wl_seat", 8);
    scanner.generate("wl_output", 4);

    exe.root_module.linkSystemLibrary("wayland-client", .{});
    exe.root_module.linkSystemLibrary("wayland-egl", .{});
    exe.root_module.linkSystemLibrary("EGL", .{});
    exe.root_module.linkSystemLibrary("GL", .{});

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
