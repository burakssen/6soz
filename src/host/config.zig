const std = @import("std");
const emulator = @import("emulator");

pub const default_path = "config.zon";

const default_source =
    \\.{
    \\    .roms_path = "roms",
    \\    .default_system = .nes,
    \\    .gameboy_model = .auto,
    \\    .boot_roms = .{
    \\        .dmg = "roms/gb/boot.rom.gb",
    \\        .cgb = null,
    \\    },
    \\    .video = .{
    \\        .scale = null,
    \\    },
    \\    .audio = .{
    \\        .enabled = true,
    \\    },
    \\    .saves = .{
    \\        .save_dir = null,
    \\        .state_dir = null,
    \\    },
    \\    .controls = .{
    \\        .a = "Z",
    \\        .b = "X",
    \\        .select = "RightShift",
    \\        .start = "Enter",
    \\        .up = "Up",
    \\        .down = "Down",
    \\        .left = "Left",
    \\        .right = "Right",
    \\    },
    \\    .last = .{
    \\        .system = null,
    \\        .rom_path = null,
    \\    },
    \\}
;

pub const BootRoms = struct {
    dmg: ?[]const u8 = "roms/gb/boot.rom.gb",
    cgb: ?[]const u8 = null,
};

pub const Video = struct {
    scale: ?f32 = null,
};

pub const Audio = struct {
    enabled: bool = true,
};

pub const Saves = struct {
    save_dir: ?[]const u8 = null,
    state_dir: ?[]const u8 = null,
};

pub const Controls = struct {
    a: []const u8 = "Z",
    b: []const u8 = "X",
    select: []const u8 = "RightShift",
    start: []const u8 = "Enter",
    up: []const u8 = "Up",
    down: []const u8 = "Down",
    left: []const u8 = "Left",
    right: []const u8 = "Right",
};

pub const Last = struct {
    system: ?emulator.EmulatorKind = null,
    rom_path: ?[]const u8 = null,
};

pub const Config = struct {
    roms_path: []const u8 = "roms",
    default_system: emulator.EmulatorKind = .nes,
    gameboy_model: emulator.Model = .auto,
    boot_roms: BootRoms = .{},
    video: Video = .{},
    audio: Audio = .{},
    saves: Saves = .{},
    controls: Controls = .{},
    last: Last = .{},
};

pub fn deinit(allocator: std.mem.Allocator, cfg: Config) void {
    std.zon.parse.free(allocator, cfg);
}

pub fn loadOrCreate(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !Config {
    const source = std.Io.Dir.cwd().readFileAllocOptions(
        io,
        path,
        allocator,
        .limited(64 * 1024),
        .of(u8),
        0,
    ) catch |err| switch (err) {
        error.FileNotFound => {
            try writeDefault(io, path);
            return parseSource(allocator, default_source);
        },
        else => |e| return e,
    };
    defer allocator.free(source);

    return parseSource(allocator, source);
}

pub fn save(io: std.Io, allocator: std.mem.Allocator, path: []const u8, cfg: Config) !void {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();

    try std.zon.stringify.serialize(cfg, .{ .whitespace = true }, &out.writer);
    try out.writer.writeByte('\n');
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = out.written(),
    });
}

pub fn withLastRom(allocator: std.mem.Allocator, cfg: *Config, kind: emulator.EmulatorKind, rom_path: []const u8) !void {
    if (cfg.last.rom_path) |path| allocator.free(path);
    cfg.last.rom_path = try allocator.dupe(u8, rom_path);
    cfg.last.system = kind;
}

pub fn bootRomPath(cfg: Config, kind: emulator.EmulatorKind, model: emulator.Model) ?[]const u8 {
    if (kind != .gameboy) return null;
    return switch (model) {
        .cgb => cfg.boot_roms.cgb orelse cfg.boot_roms.dmg,
        .auto, .dmg => cfg.boot_roms.dmg,
    };
}

pub fn parseSource(allocator: std.mem.Allocator, source: [:0]const u8) !Config {
    var diagnostics: std.zon.parse.Diagnostics = .{};
    defer diagnostics.deinit(allocator);

    return std.zon.parse.fromSliceAlloc(
        Config,
        allocator,
        source,
        &diagnostics,
        .{ .ignore_unknown_fields = false },
    ) catch |err| switch (err) {
        error.ParseZon => {
            return error.InvalidConfig;
        },
        else => |e| return e,
    };
}

fn writeDefault(io: std.Io, path: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = default_source ++ "\n",
    });
}

test "config parses defaults from ZON" {
    const cfg = try parseSource(std.testing.allocator, default_source);
    defer deinit(std.testing.allocator, cfg);

    try std.testing.expectEqualStrings("roms", cfg.roms_path);
    try std.testing.expectEqual(emulator.EmulatorKind.nes, cfg.default_system);
    try std.testing.expectEqual(emulator.Model.auto, cfg.gameboy_model);
    try std.testing.expectEqualStrings("roms/gb/boot.rom.gb", cfg.boot_roms.dmg.?);
    try std.testing.expect(cfg.boot_roms.cgb == null);
}

test "config rejects unknown fields" {
    const source =
        \\.{
        \\    .roms_path = "roms",
        \\    .unknown = true,
        \\}
    ;

    try std.testing.expectError(error.InvalidConfig, parseSource(std.testing.allocator, source));
}
