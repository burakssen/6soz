const std = @import("std");
const emulator = @import("emulator");
const config = @import("config");
const App = @import("app");
const menu = @import("menu");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;
    const arena = init.arena;
    var args = try init.minimal.args.iterateAllocator(arena.allocator());
    _ = args.next(); // Skip the executable name

    var parsed: Args = .{};
    while (args.next()) |argument| {
        if (std.mem.eql(u8, argument, "--boot-rom")) {
            parsed.boot_rom_path = args.next() orelse {
                std.debug.print("Missing value for --boot-rom\n", .{});
                std.process.exit(2);
            };
        } else if (std.mem.eql(u8, argument, "--model")) {
            const value = args.next() orelse {
                std.debug.print("Missing value for --model\n", .{});
                std.process.exit(2);
            };
            parsed.model = emulator.Model.from(value) orelse {
                std.debug.print("Invalid model: {s}\n", .{value});
                std.process.exit(2);
            };
            parsed.model_set = true;
        } else if (std.mem.eql(u8, argument, "--config")) {
            parsed.config_path = args.next() orelse {
                std.debug.print("Missing value for --config\n", .{});
                std.process.exit(2);
            };
        } else {
            if (std.mem.startsWith(u8, argument, "--")) {
                std.debug.print("Unknown option: {s}\n", .{argument});
                printUsage();
                std.process.exit(2);
            }
            if (parsed.system == null) {
                parsed.system = argument;
            } else if (parsed.rom_path == null) {
                parsed.rom_path = argument;
            } else {
                std.debug.print("Unexpected argument: {s}\n", .{argument});
                printUsage();
                std.process.exit(2);
            }
        }
    }

    if ((parsed.system == null) != (parsed.rom_path == null)) {
        printUsage();
        std.process.exit(2);
    }

    var cfg = config.loadOrCreate(io, allocator, parsed.config_path) catch |err| {
        std.debug.print("Failed to load config {s}: {s}\n", .{ parsed.config_path, @errorName(err) });
        std.process.exit(1);
    };
    defer config.deinit(allocator, cfg);

    if (parsed.system) |system| {
        const rom_path = parsed.rom_path.?;
        const kind = emulator.EmulatorKind.from(system) orelse {
            std.debug.print("Unsupported system: {s}\n\n", .{system});
            printUsage();
            std.process.exit(2);
        };
        const model = if (parsed.model_set) parsed.model else if (kind == .gameboy) cfg.gameboy_model else .auto;
        const boot_rom_path = parsed.boot_rom_path orelse config.bootRomPath(cfg, kind, model);
        try launch(io, allocator, cfg, kind, rom_path, boot_rom_path, model);
        return;
    }

    var selection = (try menu.run(io, allocator, cfg)) orelse return;
    defer selection.deinit(allocator);

    try config.withLastRom(allocator, &cfg, selection.kind, selection.rom_path);
    config.save(io, allocator, parsed.config_path, cfg) catch |err| {
        std.debug.print("Warning: failed to save config: {s}\n", .{@errorName(err)});
    };

    try launch(io, allocator, cfg, selection.kind, selection.rom_path, selection.boot_rom_path, selection.model);
}

const Args = struct {
    system: ?[]const u8 = null,
    rom_path: ?[]const u8 = null,
    boot_rom_path: ?[]const u8 = null,
    model: emulator.Model = .auto,
    model_set: bool = false,
    config_path: []const u8 = config.default_path,
};

fn launch(
    io: std.Io,
    allocator: std.mem.Allocator,
    cfg: config.Config,
    kind: emulator.EmulatorKind,
    rom_path: []const u8,
    boot_rom_path: ?[]const u8,
    model: emulator.Model,
) !void {
    var selected_emulator = emulator.Emulator.init(kind, allocator);
    errdefer selected_emulator.deinit();

    if (selected_emulator.requiresBootRom()) {
        _ = boot_rom_path orelse {
            std.debug.print("Game Boy requires a configured or explicit boot ROM path.\n", .{});
            std.process.exit(2);
        };
    }

    const app_options = App.optionsFromConfig(cfg) catch |err| {
        std.debug.print("Invalid control mapping in config: {s}\n", .{@errorName(err)});
        std.process.exit(2);
    };

    var app = try App.initWithOptions(io, allocator, selected_emulator, app_options);
    defer app.deinit();

    app.run(rom_path, boot_rom_path, model) catch |err| {
        std.debug.print("Failed to run emulator: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}

fn printUsage() void {
    std.debug.print("Usage: 6soz [<system> <rom_path>] [--boot-rom <path>] [--model auto|dmg|cgb] [--config <path>]\n", .{});
    std.debug.print("Supported systems: nes, gameboy (alias: gb)\n", .{});
}
