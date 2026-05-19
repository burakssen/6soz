const std = @import("std");

const Nes = @import("nes");

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
    cycles: u32,
    audio: []const f32 = &.{},
};

pub const BackendType = enum {
    nes,

    pub fn from(s: []const u8) ?BackendType {
        if (std.mem.eql(u8, s, "nes")) {
            return .nes;
        }
        return null;
    }
};

pub const Backend = union(BackendType) {
    nes: Nes,

    const Self = @This();

    pub fn init(backend_type: ?BackendType, allocator: std.mem.Allocator) !Self {
        const bt = backend_type orelse return error.UnsupportedPlatform;
        switch (bt) {
            .nes => return .{ .nes = Nes.init(allocator) },
        }
    }

    pub fn deinit(self: *Self) void {
        switch (self.*) {
            .nes => |*nes| nes.deinit(),
        }
    }

    pub fn load(self: *Self, data: []const u8) !void {
        switch (self.*) {
            .nes => |*nes| try nes.load(data),
        }
    }

    pub fn reset(self: *Self) void {
        switch (self.*) {
            .nes => |*nes| nes.reset(),
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
        }
    }

    pub fn step(self: *Self) !StepResult {
        return switch (self.*) {
            .nes => |*nes| blk: {
                const result = try nes.stepFrame();
                break :blk .{
                    .cycles = result.cycles,
                    .audio = result.audio,
                };
            },
        };
    }

    pub fn saveRam(self: *const Self) ?[]const u8 {
        return switch (self.*) {
            .nes => |*nes| nes.saveRam(),
        };
    }

    pub fn loadSaveRam(self: *Self, data: []const u8) !void {
        switch (self.*) {
            .nes => |*nes| try nes.loadSaveRam(data),
        }
    }

    pub fn framebuffer(self: *const Self) []const u32 {
        return switch (self.*) {
            .nes => |*nes| nes.framebuffer(),
        };
    }

    pub fn width(self: *const Self) c_int {
        return switch (self.*) {
            .nes => Nes.Ppu.Video.width,
        };
    }

    pub fn height(self: *const Self) c_int {
        return switch (self.*) {
            .nes => Nes.Ppu.Video.height,
        };
    }

    pub fn scale(self: *const Self) f32 {
        return switch (self.*) {
            .nes => 3,
        };
    }

    pub fn maxRomSize(self: *const Self) usize {
        return switch (self.*) {
            .nes => 1024 * 1024,
        };
    }
};
