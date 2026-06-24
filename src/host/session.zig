const std = @import("std");

const EmulatorHost = @import("emulator");
const save_paths = @import("save_paths.zig");

const Session = @This();

io: std.Io,
allocator: std.mem.Allocator,
emulator: EmulatorHost.Emulator,
save_path: ?[]u8 = null,
state_path: ?[]u8 = null,

pub const LoadOptions = struct {
    save_dir: ?[]const u8 = null,
    state_dir: ?[]const u8 = null,
};

pub fn init(io: std.Io, allocator: std.mem.Allocator, selected_emulator: EmulatorHost.Emulator) Session {
    return .{
        .io = io,
        .allocator = allocator,
        .emulator = selected_emulator,
    };
}

pub fn deinit(self: *Session) void {
    self.emulator.deinit();
    if (self.save_path) |path| self.allocator.free(path);
    if (self.state_path) |path| self.allocator.free(path);
}

pub fn metadata(self: *const Session) EmulatorHost.Metadata {
    return self.emulator.metadata();
}

pub fn loadRomPath(
    self: *Session,
    rom_path: []const u8,
    boot_rom_path: ?[]const u8,
    model: EmulatorHost.Model,
) !void {
    try self.loadRomPathWithOptions(rom_path, boot_rom_path, model, .{});
}

pub fn loadRomPathWithOptions(
    self: *Session,
    rom_path: []const u8,
    boot_rom_path: ?[]const u8,
    model: EmulatorHost.Model,
    options: LoadOptions,
) !void {
    self.clearPaths();

    if (rom_path.len == 0) {
        try self.emulator.load(&.{});
    } else {
        const rom_data = try std.Io.Dir.cwd().readFileAlloc(self.io, rom_path, self.allocator, .limited(self.emulator.metadata().max_rom_size));
        defer self.allocator.free(rom_data);
        try self.emulator.load(rom_data);
        try self.emulator.setModel(model);

        if (boot_rom_path) |path| {
            const boot_rom = try std.Io.Dir.cwd().readFileAlloc(self.io, path, self.allocator, .limited(1024 * 1024 + 1));
            defer self.allocator.free(boot_rom);
            try self.emulator.loadBootRom(boot_rom);
        } else if (self.emulator.requiresBootRom()) {
            return error.BootRomRequired;
        }

        self.save_path = if (options.save_dir) |dir|
            try save_paths.saveRamPathInDir(self.allocator, dir, rom_path)
        else
            try save_paths.saveRamPath(self.allocator, rom_path);
        errdefer {
            self.allocator.free(self.save_path.?);
            self.save_path = null;
        }
        self.state_path = if (options.state_dir) |dir|
            try save_paths.statePathInDir(self.allocator, dir, rom_path)
        else
            try save_paths.statePath(self.allocator, rom_path);
        errdefer {
            self.allocator.free(self.state_path.?);
            self.state_path = null;
        }
        try self.loadSaveRam();
    }

    try self.emulator.reset();
}

pub fn loadRomBytes(self: *Session, rom_data: []const u8, model: EmulatorHost.Model) !void {
    try self.loadRomBytesWithBoot(rom_data, null, model);
}

pub fn loadRomBytesWithBoot(
    self: *Session,
    rom_data: []const u8,
    boot_rom_data: ?[]const u8,
    model: EmulatorHost.Model,
) !void {
    self.clearPaths();
    try self.emulator.load(rom_data);
    try self.emulator.setModel(model);
    if (boot_rom_data) |boot_rom| {
        try self.emulator.loadBootRom(boot_rom);
    } else if (self.emulator.requiresBootRom()) {
        return error.BootRomRequired;
    }
    try self.emulator.reset();
}

pub fn persistSaveRam(self: *Session) void {
    self.writeSaveRam() catch |err| {
        std.debug.print("Warning: failed to write save RAM: {s}\n", .{@errorName(err)});
    };
}

pub fn setInput(self: *Session, input: EmulatorHost.InputState) void {
    self.emulator.setInput(input);
}

pub fn stepFrame(self: *Session) !EmulatorHost.StepResult {
    return self.emulator.stepFrame();
}

pub fn framebuffer(self: *const Session) []const u32 {
    return self.emulator.framebuffer();
}

pub fn hasStatePath(self: *const Session) bool {
    return self.state_path != null;
}

pub fn writeState(self: *Session) !void {
    const state_path = self.state_path orelse return error.StatePathUnavailable;
    const state_data = try self.emulator.saveState(self.allocator);
    defer self.allocator.free(state_data);
    try std.Io.Dir.cwd().writeFile(self.io, .{
        .sub_path = state_path,
        .data = state_data,
    });
}

pub fn loadState(self: *Session) !void {
    const state_path = self.state_path orelse return error.StatePathUnavailable;
    const state_data = std.Io.Dir.cwd().readFileAlloc(self.io, state_path, self.allocator, .limited(64 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return error.StateNotFound,
        else => |e| return e,
    };
    defer self.allocator.free(state_data);

    try self.emulator.loadState(state_data);
}

fn loadSaveRam(self: *Session) !void {
    const save_path = self.save_path orelse return;
    const save_data = std.Io.Dir.cwd().readFileAlloc(self.io, save_path, self.allocator, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return,
        else => |e| return e,
    };
    defer self.allocator.free(save_data);

    self.emulator.loadSaveRam(save_data) catch |err| switch (err) {
        error.NoSaveRam, error.InvalidSaveRamSize, error.InvalidSave => {
            std.debug.print("Warning: ignoring save RAM from {s}: {s}\n", .{ save_path, @errorName(err) });
        },
        else => |e| return e,
    };
}

fn writeSaveRam(self: *Session) !void {
    const save_path = self.save_path orelse return;
    const save_data = self.emulator.saveRam() orelse return;
    try std.Io.Dir.cwd().writeFile(self.io, .{
        .sub_path = save_path,
        .data = save_data,
    });
}

fn clearPaths(self: *Session) void {
    if (self.save_path) |path| {
        self.allocator.free(path);
        self.save_path = null;
    }
    if (self.state_path) |path| {
        self.allocator.free(path);
        self.state_path = null;
    }
}
