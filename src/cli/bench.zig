const std = @import("std");
const emulator = @import("emulator");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;
    const arena = init.arena;
    var args = try init.minimal.args.iterateAllocator(arena.allocator());
    _ = args.next(); // Skip executable name

    const system = args.next() orelse {
        std.debug.print("Usage: bench <system> <rom_path> [frames_count] [--boot-rom <path>]\n", .{});
        std.process.exit(2);
    };

    const rom_path = args.next() orelse {
        std.debug.print("Usage: bench <system> <rom_path> [frames_count] [--boot-rom <path>]\n", .{});
        std.process.exit(2);
    };

    var frames_count: usize = 1000;
    var boot_rom_path: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--boot-rom")) {
            boot_rom_path = args.next() orelse {
                std.debug.print("Missing value for --boot-rom\n", .{});
                std.process.exit(2);
            };
        } else {
            frames_count = try std.fmt.parseInt(usize, arg, 10);
        }
    }

    const kind = emulator.EmulatorKind.from(system) orelse {
        std.debug.print("Unsupported system: {s}\n", .{system});
        std.process.exit(2);
    };

    var emu = emulator.Emulator.init(kind, allocator);
    defer emu.deinit();

    // Read ROM
    const max_rom_size = emu.metadata().max_rom_size;
    const rom_data = try std.Io.Dir.cwd().readFileAlloc(io, rom_path, allocator, .limited(max_rom_size));
    defer allocator.free(rom_data);

    try emu.load(rom_data);

    if (boot_rom_path) |path| {
        const boot_rom = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024 + 1));
        defer allocator.free(boot_rom);
        try emu.loadBootRom(boot_rom);
    } else if (emu.requiresBootRom()) {
        std.debug.print("Boot ROM required for Game Boy\n", .{});
        std.process.exit(2);
    }

    try emu.reset();

    std.debug.print("Benchmarking {s} ({s}) for {d} frames...\n", .{ system, rom_path, frames_count });

    const start_time = std.Io.Timestamp.now(io, .awake);

    var i: usize = 0;
    while (i < frames_count) : (i += 1) {
        emu.setInput(.{});
        _ = try emu.stepFrame();
    }

    const elapsed = start_time.untilNow(io, .awake).toNanoseconds();
    const elapsed_s = @as(f64, @floatFromInt(elapsed)) / 1_000_000_000.0;
    const fps = @as(f64, @floatFromInt(frames_count)) / elapsed_s;

    std.debug.print("Done in {d:.3} seconds.\n", .{elapsed_s});
    std.debug.print("Average performance: {d:.2} FPS ({d:.2}x speed)\n", .{ fps, fps / @as(f64, @floatFromInt(emu.metadata().frame_rate)) });
}
