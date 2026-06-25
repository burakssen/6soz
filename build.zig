const std = @import("std");
const raylib = @import("raylib");
const web_roms = @import("build/web_roms.zig");

fn linuxDisplayBackend(b: *std.Build) raylib.LinuxDisplayBackend {
    return if (b.graph.environ_map.get("WAYLAND_DISPLAY") != null) .Wayland else .X11;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const is_web = target.result.os.tag == .emscripten;

    // Dependencies
    const raylib_dep = if (is_web)
        b.dependency("raylib", .{
            .target = target,
            .optimize = optimize,
            .opengl_version = .gles_3,
        })
    else
        b.dependency("raylib", .{
            .target = target,
            .optimize = optimize,
            .linux_display_backend = linuxDisplayBackend(b),
        });

    const nes_dep = b.dependency("nes", .{
        .target = target,
        .optimize = optimize,
    });

    const gameboy_dep = b.dependency("gameboy", .{
        .target = target,
        .optimize = optimize,
    });

    // Shared modules
    const common_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/common/root.zig"),
    });

    const emulator_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/host/emulator.zig"),
        .imports = &.{
            .{ .name = "common", .module = common_mod },
            .{ .name = "nes", .module = nes_dep.module("nes") },
            .{ .name = "gameboy", .module = gameboy_dep.module("gameboy") },
        },
    });

    const raylib_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/frontend/raylib/raylib.zig"),
    });
    raylib_mod.addIncludePath(raylib_dep.path("src"));

    const menu_ui_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/frontend/raylib/menu_ui.zig"),
        .imports = &.{
            .{ .name = "emulator", .module = emulator_mod },
            .{ .name = "raylib", .module = raylib_mod },
        },
    });
    menu_ui_mod.linkLibrary(raylib_dep.artifact("raylib"));
    menu_ui_mod.addIncludePath(raylib_dep.path("src"));

    const session_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/host/session.zig"),
        .imports = &.{
            .{ .name = "emulator", .module = emulator_mod },
        },
    });

    const config_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/host/config.zig"),
        .imports = &.{
            .{ .name = "emulator", .module = emulator_mod },
        },
    });

    const roms_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/host/roms.zig"),
        .imports = &.{
            .{ .name = "emulator", .module = emulator_mod },
            .{ .name = "config", .module = config_mod },
        },
    });

    const app_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/frontend/raylib/app.zig"),
        .imports = &.{
            .{ .name = "emulator", .module = emulator_mod },
            .{ .name = "session", .module = session_mod },
            .{ .name = "config", .module = config_mod },
            .{ .name = "raylib", .module = raylib_mod },
        },
    });
    app_mod.linkLibrary(raylib_dep.artifact("raylib"));
    app_mod.addIncludePath(raylib_dep.path("src"));

    // Web build
    if (is_web) {
        const web_rom_assets = web_roms.collect(b);
        const generated = b.addWriteFiles();
        const web_manifest_path = generated.add("web_rom_manifest.zig", web_roms.manifestSource(b, web_rom_assets));
        const web_manifest_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = web_manifest_path,
            .imports = &.{
                .{ .name = "emulator", .module = emulator_mod },
            },
        });
        const web_video_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/frontend/raylib/video.zig"),
            .imports = &.{
                .{ .name = "raylib", .module = raylib_mod },
            },
        });
        web_video_mod.linkLibrary(raylib_dep.artifact("raylib"));
        web_video_mod.addIncludePath(raylib_dep.path("src"));

        const web_audio_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/frontend/raylib/audio.zig"),
            .imports = &.{
                .{ .name = "raylib", .module = raylib_mod },
            },
        });
        web_audio_mod.linkLibrary(raylib_dep.artifact("raylib"));
        web_audio_mod.addIncludePath(raylib_dep.path("src"));

        const web_app_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/web/app.zig"),
            .imports = &.{
                .{ .name = "audio", .module = web_audio_mod },
                .{ .name = "emulator", .module = emulator_mod },
                .{ .name = "raylib", .module = raylib_mod },
                .{ .name = "video", .module = web_video_mod },
            },
        });
        web_app_mod.linkLibrary(raylib_dep.artifact("raylib"));
        web_app_mod.addIncludePath(raylib_dep.path("src"));

        const web_root_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/web/main.zig"),
            .imports = &.{
                .{ .name = "app", .module = web_app_mod },
                .{ .name = "emulator", .module = emulator_mod },
                .{ .name = "raylib", .module = raylib_mod },
                .{ .name = "menu_ui", .module = menu_ui_mod },
                .{ .name = "web_rom_manifest", .module = web_manifest_mod },
            },
        });
        web_root_mod.linkLibrary(raylib_dep.artifact("raylib"));
        web_root_mod.addIncludePath(raylib_dep.path("src"));

        const web_wasm = b.addLibrary(.{
            .name = "index",
            .linkage = .static,
            .root_module = web_root_mod,
        });

        var emcc_flags = raylib.emsdk.emccDefaultFlags(b.allocator, .{
            .optimize = optimize,
            .asyncify = true,
        });
        emcc_flags.put("-sMINIFY_HTML=0", {}) catch @panic("OOM");

        var emcc_settings = raylib.emsdk.emccDefaultSettings(b.allocator, .{
            .optimize = optimize,
            .es3 = true,
            .memory_growth = true,
        });
        emcc_settings.put("EXIT_RUNTIME", "0") catch @panic("OOM");
        emcc_settings.put("STACK_SIZE", "16777216") catch @panic("OOM");

        const emcc_step = raylib.emsdk.emccStep(
            b,
            raylib_dep.artifact("raylib"),
            web_wasm,
            .{
                .optimize = optimize,
                .flags = emcc_flags,
                .settings = emcc_settings,
                .use_preload_plugins = true,
                .preload_paths = web_roms.preloadPaths(b, web_rom_assets),
                .install_dir = .{ .custom = "web" },
                .shell_file_path = b.path("src/web/shell.html"),
            },
        );

        b.getInstallStep().dependOn(emcc_step);
        return;
    }

    // Native executables
    const menu_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/frontend/raylib/menu.zig"),
        .imports = &.{
            .{ .name = "config", .module = config_mod },
            .{ .name = "emulator", .module = emulator_mod },
            .{ .name = "roms", .module = roms_mod },
            .{ .name = "raylib", .module = raylib_mod },
            .{ .name = "menu_ui", .module = menu_ui_mod },
        },
    });
    menu_mod.linkLibrary(raylib_dep.artifact("raylib"));
    menu_mod.addIncludePath(raylib_dep.path("src"));

    const main_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/cli/main.zig"),
        .imports = &.{
            .{ .name = "app", .module = app_mod },
            .{ .name = "config", .module = config_mod },
            .{ .name = "emulator", .module = emulator_mod },
            .{ .name = "menu", .module = menu_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "6soz",
        .root_module = main_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the 6soz executable");
    run_step.dependOn(&run_cmd.step);

    const bench_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/cli/bench.zig"),
        .imports = &.{
            .{ .name = "app", .module = app_mod },
            .{ .name = "emulator", .module = emulator_mod },
        },
    });

    const bench = b.addExecutable(.{
        .name = "bench",
        .root_module = bench_mod,
    });

    const bench_cmd = b.addRunArtifact(bench);
    bench_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| bench_cmd.addArgs(args);

    const bench_step = b.step("bench", "Run the benchmark executable");
    bench_step.dependOn(&bench_cmd.step);

    const smoke_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/cli/smoke.zig"),
        .imports = &.{
            .{ .name = "app", .module = app_mod },
            .{ .name = "emulator", .module = emulator_mod },
        },
    });

    const smoke = b.addExecutable(.{
        .name = "smoke",
        .root_module = smoke_mod,
    });

    const smoke_cmd = b.addRunArtifact(smoke);
    smoke_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| smoke_cmd.addArgs(args);

    const smoke_step = b.step("smoke", "Run headless compatibility smoke checks");
    smoke_step.dependOn(&smoke_cmd.step);

    const test_step = b.step("test", "Run unit tests");

    inline for (&.{
        common_mod,
        emulator_mod,
        session_mod,
        config_mod,
        roms_mod,
        app_mod,
        smoke_mod,
    }) |mod| {
        const tests = b.addTest(.{
            .root_module = mod,
        });

        test_step.dependOn(&b.addRunArtifact(tests).step);
    }
}
