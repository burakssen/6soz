const std = @import("std");
const emulator = @import("emulator");
const App = @import("app");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;
    const arena = init.arena;
    var args = try init.minimal.args.iterateAllocator(arena.allocator());
    _ = args.next(); // Skip the executable name

    const system = args.next() orelse {
        printUsage();
        std.process.exit(2);
    };

    const rom_path = args.next() orelse {
        printUsage();
        std.process.exit(2);
    };

    var boot_rom_path: ?[]const u8 = null;
    var model: emulator.Model = .auto;
    while (args.next()) |argument| {
        if (std.mem.eql(u8, argument, "--boot-rom")) {
            boot_rom_path = args.next() orelse {
                std.debug.print("Missing value for --boot-rom\n", .{});
                std.process.exit(2);
            };
        } else if (std.mem.eql(u8, argument, "--model")) {
            const value = args.next() orelse {
                std.debug.print("Missing value for --model\n", .{});
                std.process.exit(2);
            };
            model = emulator.Model.from(value) orelse {
                std.debug.print("Invalid model: {s}\n", .{value});
                std.process.exit(2);
            };
        } else {
            std.debug.print("Unknown option: {s}\n", .{argument});
            printUsage();
            std.process.exit(2);
        }
    }

    const kind = emulator.EmulatorKind.from(system) orelse {
        std.debug.print("Unsupported system: {s}\n\n", .{system});
        printUsage();
        std.process.exit(2);
    };
    const selected_emulator = emulator.Emulator.init(kind, allocator);

    if (selected_emulator.requiresBootRom()) {
        _ = boot_rom_path orelse {
            std.debug.print("Game Boy requires --boot-rom with a 256-byte DMG or 2304-byte CGB boot ROM.\n", .{});
            std.process.exit(2);
        };
    }

    var app = try App.init(io, allocator, selected_emulator);
    defer app.deinit();

    app.run(rom_path, boot_rom_path, model) catch |err| {
        std.debug.print("Failed to run emulator: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}

fn printUsage() void {
    std.debug.print("Usage: 6soz <system> <rom_path> [--boot-rom <path>] [--model auto|dmg|cgb]\n", .{});
    std.debug.print("Supported systems: nes, gameboy (alias: gb)\n", .{});
}
