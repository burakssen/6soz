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
    const gameboy_dep = b.dependency("gameboy", .{
        .target = target,
        .optimize = optimize,
    });
    const gameboy_mod = gameboy_dep.module("gameboy");

    const emulator_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/emulator.zig"),
        .imports = &.{
            .{ .name = "nes", .module = nes_mod },
            .{ .name = "gameboy", .module = gameboy_mod },
        },
    });

    const app_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/app/app.zig"),
        .imports = &.{
            .{ .name = "emulator", .module = emulator_mod },
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
            .{ .name = "emulator", .module = emulator_mod },
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

    const emulator_tests = b.addTest(.{
        .root_module = emulator_mod,
    });

    const app_tests = b.addTest(.{
        .root_module = app_mod,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(emulator_tests).step);
    test_step.dependOn(&b.addRunArtifact(app_tests).step);
}
