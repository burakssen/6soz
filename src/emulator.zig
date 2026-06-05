const std = @import("std");

const Nes = @import("nes");
const GameBoy = @import("gameboy");

pub const InputState = struct {
    a: bool = false,
    b: bool = false,
    select: bool = false,
    start: bool = false,
    up: bool = false,
    down: bool = false,
    left: bool = false,
    right: bool = false,
};

pub const StepResult = struct {
    audio: []const f32 = &.{},
};

pub const Metadata = struct {
    width: c_int,
    height: c_int,
    scale: f32,
    frame_rate: u16,
    audio_sample_rate: u32,
    max_rom_size: usize,
};

pub const EmulatorKind = enum {
    nes,
    gameboy,

    pub fn from(s: []const u8) ?EmulatorKind {
        if (std.mem.eql(u8, s, "nes")) {
            return .nes;
        }
        if (std.mem.eql(u8, s, "gameboy") or std.mem.eql(u8, s, "gb")) {
            return .gameboy;
        }
        return null;
    }
};

pub const Model = enum {
    auto,
    dmg,
    cgb,

    pub fn from(value: []const u8) ?Model {
        if (std.mem.eql(u8, value, "auto")) return .auto;
        if (std.mem.eql(u8, value, "dmg")) return .dmg;
        if (std.mem.eql(u8, value, "cgb")) return .cgb;
        return null;
    }
};

pub const Emulator = union(EmulatorKind) {
    nes: Nes,
    gameboy: GameBoy,

    const Self = @This();

    pub fn init(kind: EmulatorKind, allocator: std.mem.Allocator) Self {
        switch (kind) {
            .nes => return .{ .nes = Nes.init(allocator) },
            .gameboy => return .{ .gameboy = GameBoy.init(allocator) },
        }
    }

    pub fn deinit(self: *Self) void {
        switch (self.*) {
            .nes => |*nes| nes.deinit(),
            .gameboy => |*gameboy| gameboy.deinit(),
        }
    }

    pub fn load(self: *Self, data: []const u8) !void {
        switch (self.*) {
            .nes => |*nes| try nes.load(data),
            .gameboy => |*gameboy| try gameboy.load(data),
        }
    }

    pub fn loadBootRom(self: *Self, data: []const u8) !void {
        switch (self.*) {
            .nes => return error.BootRomNotSupported,
            .gameboy => |*gameboy| try gameboy.loadBootRom(data),
        }
    }

    pub fn setModel(self: *Self, model: Model) !void {
        switch (self.*) {
            .nes => if (model != .auto) return error.ModelNotSupported,
            .gameboy => |*gameboy| {
                const selected: GameBoy.Model = switch (model) {
                    .auto => .auto,
                    .dmg => .dmg,
                    .cgb => .cgb,
                };
                try gameboy.setModel(selected);
            },
        }
    }

    pub fn requiresBootRom(self: *const Self) bool {
        return switch (self.*) {
            .nes => false,
            .gameboy => true,
        };
    }

    pub fn reset(self: *Self) !void {
        switch (self.*) {
            .nes => |*nes| nes.reset(),
            .gameboy => |*gameboy| try gameboy.reset(),
        }
    }

    pub fn setInput(self: *Self, input: InputState) void {
        switch (self.*) {
            .nes => |*nes| nes.setInput(.{
                .a = input.a,
                .b = input.b,
                .select = input.select,
                .start = input.start,
                .up = input.up,
                .down = input.down,
                .left = input.left,
                .right = input.right,
            }),
            .gameboy => |*gameboy| gameboy.setInput(.{
                .a = input.a,
                .b = input.b,
                .select = input.select,
                .start = input.start,
                .up = input.up,
                .down = input.down,
                .left = input.left,
                .right = input.right,
            }),
        }
    }

    pub fn stepFrame(self: *Self) !StepResult {
        return switch (self.*) {
            .nes => |*nes| blk: {
                const result = try nes.stepFrame();
                break :blk .{
                    .audio = result.audio,
                };
            },
            .gameboy => |*gameboy| blk: {
                const result = try gameboy.stepFrame();
                break :blk .{ .audio = result.audio };
            },
        };
    }

    pub fn saveRam(self: *Self) ?[]const u8 {
        return switch (self.*) {
            .nes => |*nes| nes.saveRam(),
            .gameboy => |*gameboy| gameboy.saveRam(),
        };
    }

    pub fn loadSaveRam(self: *Self, data: []const u8) !void {
        switch (self.*) {
            .nes => |*nes| try nes.loadSaveRam(data),
            .gameboy => |*gameboy| try gameboy.loadSaveRam(data),
        }
    }

    pub fn framebuffer(self: *const Self) []const u32 {
        return switch (self.*) {
            .nes => |*nes| nes.framebuffer(),
            .gameboy => |*gameboy| gameboy.framebuffer(),
        };
    }

    pub fn metadata(self: *const Self) Metadata {
        return switch (self.*) {
            .nes => |*nes| .{
                .width = Nes.Ppu.Video.width,
                .height = Nes.Ppu.Video.height,
                .scale = 3,
                .frame_rate = nes.frameRate(),
                .audio_sample_rate = nes.audioSampleRate(),
                .max_rom_size = 1024 * 1024,
            },
            .gameboy => .{
                .width = GameBoy.width,
                .height = GameBoy.height,
                .scale = 4,
                .frame_rate = 60,
                .audio_sample_rate = GameBoy.sample_rate,
                .max_rom_size = GameBoy.max_rom_size,
            },
        };
    }
};

test "emulator kind parses supported system names" {
    try std.testing.expectEqual(EmulatorKind.nes, EmulatorKind.from("nes").?);
    try std.testing.expectEqual(EmulatorKind.gameboy, EmulatorKind.from("gb").?);
    try std.testing.expectEqual(EmulatorKind.gameboy, EmulatorKind.from("gameboy").?);
}

test "model parses supported names" {
    try std.testing.expectEqual(Model.auto, Model.from("auto").?);
    try std.testing.expectEqual(Model.dmg, Model.from("dmg").?);
    try std.testing.expectEqual(Model.cgb, Model.from("cgb").?);
    try std.testing.expectEqual(@as(?Model, null), Model.from("invalid"));
}
