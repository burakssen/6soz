const std = @import("std");
const emulator = @import("emulator");
const config = @import("config");

pub const Entry = struct {
    name: []const u8,
    path: []const u8,

    pub fn deinit(self: Entry, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.path);
    }
};

pub fn freeEntries(allocator: std.mem.Allocator, entries: []Entry) void {
    for (entries) |entry| entry.deinit(allocator);
    allocator.free(entries);
}

pub fn discover(
    io: std.Io,
    allocator: std.mem.Allocator,
    roms_root: []const u8,
    kind: emulator.EmulatorKind,
    cfg: config.Config,
) ![]Entry {
    const system_dir = systemDirName(kind);
    const directory_path = try std.fs.path.join(allocator, &.{ roms_root, system_dir });
    defer allocator.free(directory_path);

    var dir = std.Io.Dir.cwd().openDir(io, directory_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return try allocator.alloc(Entry, 0),
        else => |e| return e,
    };
    defer dir.close(io);

    var entries: std.ArrayList(Entry) = .empty;
    errdefer {
        for (entries.items) |entry| entry.deinit(allocator);
        entries.deinit(allocator);
    }

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!hasRomExtension(kind, entry.name)) continue;

        const full_path = try std.fs.path.join(allocator, &.{ directory_path, entry.name });
        errdefer allocator.free(full_path);
        if (isExcludedBootRom(cfg, full_path)) {
            allocator.free(full_path);
            continue;
        }

        const display_name = try allocator.dupe(u8, entry.name);
        errdefer allocator.free(display_name);
        try entries.append(allocator, .{
            .name = display_name,
            .path = full_path,
        });
    }

    std.mem.sort(Entry, entries.items, {}, lessThan);
    return try entries.toOwnedSlice(allocator);
}

pub fn systemDirName(kind: emulator.EmulatorKind) []const u8 {
    return switch (kind) {
        .nes => "nes",
        .gameboy => "gb",
    };
}

pub fn displayName(kind: emulator.EmulatorKind) []const u8 {
    return switch (kind) {
        .nes => "NES",
        .gameboy => "Game Boy",
    };
}

pub fn hasRomExtension(kind: emulator.EmulatorKind, name: []const u8) bool {
    return switch (kind) {
        .nes => hasAnyExtension(name, &.{".nes"}),
        .gameboy => hasAnyExtension(name, &.{ ".gb", ".gbc" }),
    };
}

fn hasAnyExtension(name: []const u8, extensions: []const []const u8) bool {
    for (extensions) |extension| {
        if (name.len >= extension.len and std.ascii.eqlIgnoreCase(name[name.len - extension.len ..], extension)) {
            return true;
        }
    }
    return false;
}

fn isExcludedBootRom(cfg: config.Config, path: []const u8) bool {
    if (cfg.boot_roms.dmg) |boot_path| {
        if (std.mem.eql(u8, boot_path, path)) return true;
    }
    if (cfg.boot_roms.cgb) |boot_path| {
        if (std.mem.eql(u8, boot_path, path)) return true;
    }
    return false;
}

fn lessThan(_: void, lhs: Entry, rhs: Entry) bool {
    return std.ascii.lessThanIgnoreCase(lhs.name, rhs.name);
}

test "ROM extension filters are system specific and case insensitive" {
    try std.testing.expect(hasRomExtension(.nes, "game.nes"));
    try std.testing.expect(hasRomExtension(.nes, "GAME.NES"));
    try std.testing.expect(!hasRomExtension(.nes, "game.gb"));

    try std.testing.expect(hasRomExtension(.gameboy, "game.gb"));
    try std.testing.expect(hasRomExtension(.gameboy, "game.GBC"));
    try std.testing.expect(!hasRomExtension(.gameboy, "game.sav"));
}
