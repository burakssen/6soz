const std = @import("std");
const emulator = @import("emulator");

const default_frames = 2;

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

    var frames: usize = default_frames;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--frames")) {
            const value = args.next() orelse return error.MissingFrameCount;
            frames = try std.fmt.parseInt(usize, value, 10);
        } else {
            return error.UnexpectedArgument;
        }
    }

    const kind = emulator.EmulatorKind.from(system_name) orelse return error.UnsupportedSystem;
    if (kind != .nes) return error.UnsupportedSmokeSystem;

    var total: usize = 0;
    var passed: usize = 0;
    var skipped: usize = 0;
    var failed: usize = 0;

    if (hasNesExtension(path)) {
        total += 1;
        switch (try smokeOne(io, allocator, kind, path, frames)) {
            .pass => passed += 1,
            .skip => skipped += 1,
            .fail => failed += 1,
        }
    } else {
        var dir = try std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
        defer dir.close(io);

        var iter = dir.iterate();
        while (try iter.next(io)) |entry| {
            if (entry.kind != .file or !hasNesExtension(entry.name)) continue;
            const rom_path = try std.fs.path.join(allocator, &.{ path, entry.name });
            defer allocator.free(rom_path);

            total += 1;
            switch (try smokeOne(io, allocator, kind, rom_path, frames)) {
                .pass => passed += 1,
                .skip => skipped += 1,
                .fail => failed += 1,
            }
        }
    }

    std.debug.print("SUMMARY total={d} pass={d} skip={d} fail={d}\n", .{ total, passed, skipped, failed });
    if (failed != 0) return error.SmokeFailure;
}

fn smokeOne(io: std.Io, allocator: std.mem.Allocator, kind: emulator.EmulatorKind, rom_path: []const u8, frames: usize) !Outcome {
    var emu = emulator.Emulator.init(kind, allocator);
    defer emu.deinit();

    const rom = std.Io.Dir.cwd().readFileAlloc(io, rom_path, allocator, .limited(emu.metadata().max_rom_size)) catch |err| {
        std.debug.print("FAIL {s}: read {s}\n", .{ rom_path, @errorName(err) });
        return .fail;
    };
    defer allocator.free(rom);

    emu.load(rom) catch |err| {
        switch (err) {
            error.UnsupportedMapper, error.UnsupportedMirroring, error.UnsupportedTimingMode => {
                std.debug.print("SKIP {s}: load {s}\n", .{ rom_path, @errorName(err) });
                return .skip;
            },
            else => {
                std.debug.print("FAIL {s}: load {s}\n", .{ rom_path, @errorName(err) });
                return .fail;
            },
        }
    };
    emu.reset() catch |err| {
        std.debug.print("FAIL {s}: reset {s}\n", .{ rom_path, @errorName(err) });
        return .fail;
    };

    var i: usize = 0;
    while (i < frames) : (i += 1) {
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

fn hasNesExtension(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".nes") or std.mem.endsWith(u8, path, ".NES");
}

fn printUsage() void {
    std.debug.print("Usage: smoke <system> <rom_or_directory> [--frames count]\n", .{});
    std.debug.print("Supported smoke system: nes\n", .{});
}
