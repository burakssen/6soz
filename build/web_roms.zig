const std = @import("std");
const zemscripten = @import("zemscripten");

const Kind = enum { nes, gameboy };

const Asset = struct {
    kind: Kind,
    name: []const u8,
    src_path: []const u8,
    virtual_path: []const u8,
    boot: bool,
};

pub fn collect(b: *std.Build) []Asset {
    var assets: std.ArrayList(Asset) = .empty;
    collectInDir(b, &assets, "roms") catch |err| {
        std.debug.panic("failed to collect web ROM assets: {s}", .{@errorName(err)});
    };
    std.mem.sort(Asset, assets.items, {}, lessThan);
    return assets.toOwnedSlice(b.allocator) catch @panic("OOM");
}

pub fn preloadPaths(b: *std.Build, assets: []const Asset) []const zemscripten.EmccFilePath {
    var paths: std.ArrayList(zemscripten.EmccFilePath) = .empty;
    for (assets) |asset| {
        paths.append(b.allocator, .{
            .src_path = asset.src_path,
            .virtual_path = asset.virtual_path,
        }) catch @panic("OOM");
    }
    return paths.items;
}

pub fn manifestSource(b: *std.Build, assets: []const Asset) []const u8 {
    var out = std.Io.Writer.Allocating.init(b.allocator);
    const writer = &out.writer;
    writer.writeAll(
        \\const emulator = @import("emulator");
        \\
        \\pub const RomEntry = struct {
        \\    kind: emulator.EmulatorKind,
        \\    name: []const u8,
        \\    path: [:0]const u8,
        \\    boot: bool,
        \\};
        \\
        \\pub const entries = [_]RomEntry{
        \\
    ) catch @panic("OOM");

    var dmg_boot_rom_path: ?[]const u8 = null;
    for (assets) |asset| {
        if (asset.boot and asset.kind == .gameboy and dmg_boot_rom_path == null) {
            dmg_boot_rom_path = asset.virtual_path;
        }
        writer.print("    .{{ .kind = .{s}, .name = ", .{@tagName(asset.kind)}) catch @panic("OOM");
        writeZigString(writer, asset.name) catch @panic("OOM");
        writer.writeAll(", .path = ") catch @panic("OOM");
        writeZigString(writer, asset.virtual_path) catch @panic("OOM");
        writer.print(", .boot = {} }},\n", .{asset.boot}) catch @panic("OOM");
    }

    writer.writeAll("};\n\npub const dmg_boot_rom_path: ?[:0]const u8 = ") catch @panic("OOM");
    if (dmg_boot_rom_path) |path| {
        writeZigString(writer, path) catch @panic("OOM");
    } else {
        writer.writeAll("null") catch @panic("OOM");
    }
    writer.writeAll(";\n") catch @panic("OOM");
    return out.written();
}

fn collectInDir(b: *std.Build, assets: *std.ArrayList(Asset), dir_path: []const u8) !void {
    const io = b.graph.io;
    var dir = try std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true });
    defer dir.close(io);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        const child_path = b.pathJoin(&.{ dir_path, entry.name });
        switch (entry.kind) {
            .directory => try collectInDir(b, assets, child_path),
            .file => {
                const kind = kindForPath(child_path) orelse continue;
                assets.append(b.allocator, .{
                    .kind = kind,
                    .name = b.dupe(entry.name),
                    .src_path = b.dupePath(child_path),
                    .virtual_path = std.fmt.allocPrint(b.allocator, "/{s}", .{child_path}) catch @panic("OOM"),
                    .boot = std.mem.eql(u8, child_path, "roms/gb/boot.rom.gb"),
                }) catch @panic("OOM");
            },
            else => {},
        }
    }
}

fn kindForPath(path: []const u8) ?Kind {
    if (std.mem.startsWith(u8, path, "roms/nes/") and hasExtension(path, &.{".nes"})) return .nes;
    if (std.mem.startsWith(u8, path, "roms/gb/") and hasExtension(path, &.{ ".gb", ".gbc" })) return .gameboy;
    return null;
}

fn hasExtension(path: []const u8, extensions: []const []const u8) bool {
    for (extensions) |extension| {
        if (path.len >= extension.len and std.ascii.eqlIgnoreCase(path[path.len - extension.len ..], extension)) return true;
    }
    return false;
}

fn lessThan(_: void, lhs: Asset, rhs: Asset) bool {
    return std.ascii.lessThanIgnoreCase(lhs.src_path, rhs.src_path);
}

fn writeZigString(writer: *std.Io.Writer, value: []const u8) !void {
    const hex = "0123456789abcdef";
    try writer.writeByte('"');
    for (value) |byte| {
        switch (byte) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0x20...0x21, 0x23...0x5b, 0x5d...0x7e => try writer.writeByte(byte),
            else => {
                try writer.writeAll("\\x");
                try writer.writeByte(hex[byte >> 4]);
                try writer.writeByte(hex[byte & 0x0f]);
            },
        }
    }
    try writer.writeByte('"');
}
