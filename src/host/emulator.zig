const std = @import("std");

const common = @import("common");
const Nes = @import("nes");
const GameBoy = @import("gameboy");
const State = common.StateCodec;

pub const InputState = common.InputState;
pub const StepResult = common.StepResult;
pub const Metadata = common.Metadata;

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
    const state_magic = "6SOZST01";
    const state_version: u8 = 1;

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

    pub fn saveState(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        const kind: EmulatorKind = self.*;
        const payload = switch (self.*) {
            .nes => |*nes| try nes.saveState(allocator),
            .gameboy => |*gameboy| try gameboy.saveState(allocator),
        };
        defer allocator.free(payload);

        var state = std.Io.Writer.Allocating.init(allocator);
        errdefer state.deinit();
        const writer = &state.writer;
        try writer.writeAll(state_magic);
        try State.writeValue(writer, state_version);
        try State.writeValue(writer, kind);
        try State.writeValue(writer, @as(u32, @intCast(payload.len)));
        try writer.writeAll(payload);
        return state.toOwnedSlice();
    }

    pub fn loadState(self: *Self, data: []const u8) !void {
        var state = std.Io.Reader.fixed(data);
        const reader = &state;
        try State.expectBytes(reader, state_magic);
        if ((try State.readValue(reader, u8)) != state_version) return State.Error.UnsupportedStateVersion;
        const kind = try State.readValue(reader, EmulatorKind);
        const payload_len = try State.readValue(reader, u32);
        const payload = try State.readBytes(reader, payload_len);
        try State.done(reader);

        switch (self.*) {
            .nes => |*nes| {
                if (kind != .nes) return State.Error.StateKindMismatch;
                try nes.loadState(payload);
            },
            .gameboy => |*gameboy| {
                if (kind != .gameboy) return State.Error.StateKindMismatch;
                try gameboy.loadState(payload);
            },
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

test "NES state round trips through emulator facade" {
    const allocator = std.testing.allocator;
    const rom = try makeNesTestRom(allocator);
    defer allocator.free(rom);

    var emu = Emulator.init(.nes, allocator);
    defer emu.deinit();
    try emu.load(rom);
    try emu.reset();

    emu.nes.cpu.a = 0x44;
    emu.nes.bus.ram[7] = 0x99;
    const state = try emu.saveState(allocator);
    defer allocator.free(state);

    emu.nes.cpu.a = 0;
    emu.nes.bus.ram[7] = 0;
    try emu.loadState(state);

    try std.testing.expectEqual(@as(u8, 0x44), emu.nes.cpu.a);
    try std.testing.expectEqual(@as(u8, 0x99), emu.nes.bus.ram[7]);
}

test "Game Boy state round trips through emulator facade" {
    const allocator = std.testing.allocator;
    const rom = try makeGameBoyTestRom(allocator);
    defer allocator.free(rom);
    var boot = [_]u8{0} ** 0x100;

    var emu = Emulator.init(.gameboy, allocator);
    defer emu.deinit();
    try emu.load(rom);
    try emu.loadBootRom(&boot);
    try emu.reset();

    emu.gameboy.cpu.a = 0x12;
    emu.gameboy.wram[0][3] = 0x34;
    const state = try emu.saveState(allocator);
    defer allocator.free(state);

    emu.gameboy.cpu.a = 0;
    emu.gameboy.wram[0][3] = 0;
    try emu.loadState(state);

    try std.testing.expectEqual(@as(u8, 0x12), emu.gameboy.cpu.a);
    try std.testing.expectEqual(@as(u8, 0x34), emu.gameboy.wram[0][3]);
}

test "state loading rejects invalid top-level header" {
    var emu = Emulator.init(.nes, std.testing.allocator);
    defer emu.deinit();

    try std.testing.expectError(State.Error.InvalidState, emu.loadState("not a state"));
}

test "state loading rejects unsupported top-level version" {
    const allocator = std.testing.allocator;
    const rom = try makeNesTestRom(allocator);
    defer allocator.free(rom);

    var emu = Emulator.init(.nes, allocator);
    defer emu.deinit();
    try emu.load(rom);
    try emu.reset();

    const state = try emu.saveState(allocator);
    defer allocator.free(state);

    const version_offset = Emulator.state_magic.len;
    state[version_offset] = Emulator.state_version + 1;

    try std.testing.expectError(State.Error.UnsupportedStateVersion, emu.loadState(state));
}

test "state loading rejects trailing top-level bytes" {
    const allocator = std.testing.allocator;
    const rom = try makeNesTestRom(allocator);
    defer allocator.free(rom);

    var emu = Emulator.init(.nes, allocator);
    defer emu.deinit();
    try emu.load(rom);
    try emu.reset();

    const state = try emu.saveState(allocator);
    defer allocator.free(state);
    const with_trailing = try allocator.alloc(u8, state.len + 1);
    defer allocator.free(with_trailing);
    @memcpy(with_trailing[0..state.len], state);
    with_trailing[state.len] = 0;

    try std.testing.expectError(State.Error.InvalidState, emu.loadState(with_trailing));
}

test "state loading rejects cross-system state" {
    const allocator = std.testing.allocator;
    const nes_rom = try makeNesTestRom(allocator);
    defer allocator.free(nes_rom);
    const gb_rom = try makeGameBoyTestRom(allocator);
    defer allocator.free(gb_rom);
    var boot = [_]u8{0} ** 0x100;

    var nes_emu = Emulator.init(.nes, allocator);
    defer nes_emu.deinit();
    try nes_emu.load(nes_rom);
    try nes_emu.reset();
    const state = try nes_emu.saveState(allocator);
    defer allocator.free(state);

    var gb_emu = Emulator.init(.gameboy, allocator);
    defer gb_emu.deinit();
    try gb_emu.load(gb_rom);
    try gb_emu.loadBootRom(&boot);
    try gb_emu.reset();

    try std.testing.expectError(State.Error.StateKindMismatch, gb_emu.loadState(state));
}

fn makeNesTestRom(allocator: std.mem.Allocator) ![]u8 {
    const prg_size = 16 * 1024;
    const chr_size = 8 * 1024;
    const data = try allocator.alloc(u8, 16 + prg_size + chr_size);
    @memset(data, 0);
    @memcpy(data[0..4], "NES\x1a");
    data[4] = 1;
    data[5] = 1;
    data[16 + 0x3ffc] = 0x00;
    data[16 + 0x3ffd] = 0x80;
    return data;
}

fn makeGameBoyTestRom(allocator: std.mem.Allocator) ![]u8 {
    const data = try allocator.alloc(u8, 32 * 1024);
    @memset(data, 0);
    data[0x147] = 0;
    data[0x148] = 0;
    data[0x149] = 0;
    return data;
}
