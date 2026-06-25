const std = @import("std");
const emulator = @import("emulator");

const default_frames = 2;

const Options = struct {
    frames: usize = default_frames,
    boot_rom_path: ?[]const u8 = null,
    model: emulator.Model = .auto,
};

const Outcome = enum {
    pass,
    skip,
    fail,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;
    const arena = init.arena;
    var args = try init.minimal.args.iterateAllocator(arena.allocator());
    _ = args.next();

    const system_name = args.next() orelse {
        printUsage();
        return error.MissingSystem;
    };
    const path = args.next() orelse {
        printUsage();
        return error.MissingPath;
    };

    var options: Options = .{};
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--frames")) {
            const value = args.next() orelse return error.MissingFrameCount;
            options.frames = try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.eql(u8, arg, "--boot-rom")) {
            options.boot_rom_path = args.next() orelse return error.MissingBootRomPath;
        } else if (std.mem.eql(u8, arg, "--model")) {
            const value = args.next() orelse return error.MissingModel;
            options.model = emulator.Model.from(value) orelse return error.InvalidModel;
        } else {
            return error.UnexpectedArgument;
        }
    }

    const kind = emulator.EmulatorKind.from(system_name) orelse return error.UnsupportedSystem;
    if (kind == .nes and options.model != .auto) return error.ModelNotSupported;

    var boot_rom: ?[]u8 = null;
    defer if (boot_rom) |data| allocator.free(data);
    if (options.boot_rom_path) |boot_rom_path| {
        boot_rom = std.Io.Dir.cwd().readFileAlloc(io, boot_rom_path, allocator, .limited(1024 * 1024 + 1)) catch |err| {
            std.debug.print("FAIL {s}: boot-rom read {s}\n", .{ boot_rom_path, @errorName(err) });
            return error.BootRomReadFailure;
        };
    } else if (kind == .gameboy) {
        printUsage();
        return error.MissingBootRomPath;
    }

    var total: usize = 0;
    var passed: usize = 0;
    var skipped: usize = 0;
    var failed: usize = 0;

    if (hasRomExtension(kind, path)) {
        total += 1;
        if (isBootRomPath(path, options.boot_rom_path)) {
            skipped += 1;
            std.debug.print("SKIP {s}: boot-rom\n", .{path});
            std.debug.print("SUMMARY total={d} pass={d} skip={d} fail={d}\n", .{ total, passed, skipped, failed });
            return;
        }
        switch (try smokeOne(io, allocator, kind, path, options, boot_rom)) {
            .pass => passed += 1,
            .skip => skipped += 1,
            .fail => failed += 1,
        }
    } else {
        var dir = try std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
        defer dir.close(io);

        var iter = dir.iterate();
        while (try iter.next(io)) |entry| {
            if (entry.kind != .file or !hasRomExtension(kind, entry.name)) continue;
            const rom_path = try std.fs.path.join(allocator, &.{ path, entry.name });
            defer allocator.free(rom_path);

            total += 1;
            if (isBootRomPath(rom_path, options.boot_rom_path)) {
                skipped += 1;
                std.debug.print("SKIP {s}: boot-rom\n", .{rom_path});
                continue;
            }
            switch (try smokeOne(io, allocator, kind, rom_path, options, boot_rom)) {
                .pass => passed += 1,
                .skip => skipped += 1,
                .fail => failed += 1,
            }
        }
    }

    std.debug.print("SUMMARY total={d} pass={d} skip={d} fail={d}\n", .{ total, passed, skipped, failed });
    if (failed != 0) return error.SmokeFailure;
}

fn smokeOne(
    io: std.Io,
    allocator: std.mem.Allocator,
    kind: emulator.EmulatorKind,
    rom_path: []const u8,
    options: Options,
    boot_rom: ?[]const u8,
) !Outcome {
    var emu = emulator.Emulator.init(kind, allocator);
    defer emu.deinit();

    const rom = std.Io.Dir.cwd().readFileAlloc(io, rom_path, allocator, .limited(emu.metadata().max_rom_size)) catch |err| {
        std.debug.print("FAIL {s}: read {s}\n", .{ rom_path, @errorName(err) });
        return .fail;
    };
    defer allocator.free(rom);

    emu.setModel(options.model) catch |err| {
        std.debug.print("FAIL {s}: model {s}\n", .{ rom_path, @errorName(err) });
        return .fail;
    };

    emu.load(rom) catch |err| {
        switch (err) {
            error.UnsupportedMapper, error.UnsupportedMirroring, error.UnsupportedTimingMode, error.UnsupportedCartridge => {
                std.debug.print("SKIP {s}: load {s}\n", .{ rom_path, @errorName(err) });
                return .skip;
            },
            else => {
                std.debug.print("FAIL {s}: load {s}\n", .{ rom_path, @errorName(err) });
                return .fail;
            },
        }
    };
    if (boot_rom) |data| {
        emu.loadBootRom(data) catch |err| {
            std.debug.print("FAIL {s}: boot-rom {s}\n", .{ rom_path, @errorName(err) });
            return .fail;
        };
    }
    emu.reset() catch |err| {
        std.debug.print("FAIL {s}: reset {s}\n", .{ rom_path, @errorName(err) });
        return .fail;
    };

    var i: usize = 0;
    while (i < options.frames) : (i += 1) {
        emu.setInput(.{});
        _ = emu.stepFrame() catch |err| {
            std.debug.print("FAIL {s}: frame {d} {s}\n", .{ rom_path, i, @errorName(err) });
            return .fail;
        };
    }

    const state = emu.saveState(allocator) catch |err| {
        std.debug.print("FAIL {s}: save-state {s}\n", .{ rom_path, @errorName(err) });
        return .fail;
    };
    defer allocator.free(state);

    emu.loadState(state) catch |err| {
        std.debug.print("FAIL {s}: load-state {s}\n", .{ rom_path, @errorName(err) });
        return .fail;
    };

    std.debug.print("PASS {s}\n", .{rom_path});
    return .pass;
}

fn hasRomExtension(kind: emulator.EmulatorKind, path: []const u8) bool {
    return switch (kind) {
        .nes => hasExtension(path, ".nes"),
        .gameboy => hasExtension(path, ".gb") or hasExtension(path, ".gbc"),
    };
}

fn hasExtension(path: []const u8, extension: []const u8) bool {
    if (path.len < extension.len) return false;
    return std.ascii.eqlIgnoreCase(path[path.len - extension.len ..], extension);
}

fn isBootRomPath(rom_path: []const u8, boot_rom_path: ?[]const u8) bool {
    const path = boot_rom_path orelse return false;
    if (std.mem.eql(u8, rom_path, path)) return true;
    return std.mem.eql(u8, std.fs.path.basename(rom_path), std.fs.path.basename(path));
}

fn printUsage() void {
    std.debug.print("Usage: smoke <system> <rom_or_directory> [--frames count] [--boot-rom path] [--model auto|dmg|cgb]\n", .{});
    std.debug.print("Supported smoke systems: nes, gb\n", .{});
}

test "ROM extension matching is system-specific and case-insensitive" {
    try std.testing.expect(hasRomExtension(.nes, "game.NES"));
    try std.testing.expect(!hasRomExtension(.nes, "game.gb"));
    try std.testing.expect(hasRomExtension(.gameboy, "game.GB"));
    try std.testing.expect(hasRomExtension(.gameboy, "game.GBC"));
    try std.testing.expect(!hasRomExtension(.gameboy, "game.nes"));
}

test "boot ROM matching accepts exact paths and matching basenames" {
    try std.testing.expect(isBootRomPath("roms/gb/boot.rom.gb", "roms/gb/boot.rom.gb"));
    try std.testing.expect(isBootRomPath("roms/gb/boot.rom.gb", "boot.rom.gb"));
    try std.testing.expect(!isBootRomPath("roms/gb/game.gb", "boot.rom.gb"));
    try std.testing.expect(!isBootRomPath("roms/gb/boot.rom.gb", null));
}
