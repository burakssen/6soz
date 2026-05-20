const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
        .linux_display_backend = .Wayland,
    });

    const raylib_artifact = raylib_dep.artifact("raylib");
    const raylib_path = raylib_dep.path("src");

    const nes_dep = b.dependency("nes", .{
        .target = target,
        .optimize = optimize,
    });

    const nes_mod = nes_dep.module("nes");

    const backend_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/backends/backend.zig"),
        .imports = &.{
            .{ .name = "nes", .module = nes_mod },
        },
    });

    const app_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/app/app.zig"),
        .imports = &.{
            .{ .name = "backend", .module = backend_mod },
        },
    });

    app_mod.linkLibrary(raylib_artifact);
    app_mod.addIncludePath(raylib_path);

    const exe_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
        .imports = &.{
            .{ .name = "app", .module = app_mod },
            .{ .name = "backend", .module = backend_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "6soz",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the 6soz executable");
    run_step.dependOn(&run_cmd.step);
}
