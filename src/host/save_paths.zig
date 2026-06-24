const std = @import("std");

pub fn saveRamPath(allocator: std.mem.Allocator, rom_path: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}.sav", .{rom_path});
}

pub fn statePath(allocator: std.mem.Allocator, rom_path: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}.state", .{rom_path});
}

pub fn saveRamPathInDir(allocator: std.mem.Allocator, save_dir: []const u8, rom_path: []const u8) ![]u8 {
    const name = std.fs.path.basename(rom_path);
    const file_name = try std.fmt.allocPrint(allocator, "{s}.sav", .{name});
    defer allocator.free(file_name);
    return std.fs.path.join(allocator, &.{ save_dir, file_name });
}

pub fn statePathInDir(allocator: std.mem.Allocator, state_dir: []const u8, rom_path: []const u8) ![]u8 {
    const name = std.fs.path.basename(rom_path);
    const file_name = try std.fmt.allocPrint(allocator, "{s}.state", .{name});
    defer allocator.free(file_name);
    return std.fs.path.join(allocator, &.{ state_dir, file_name });
}

test "save and state paths can be redirected to configured directories" {
    const save_path = try saveRamPathInDir(std.testing.allocator, "saves", "roms/nes/game.nes");
    defer std.testing.allocator.free(save_path);
    try std.testing.expectEqualStrings("saves/game.nes.sav", save_path);

    const state_path = try statePathInDir(std.testing.allocator, "states", "roms/nes/game.nes");
    defer std.testing.allocator.free(state_path);
    try std.testing.expectEqualStrings("states/game.nes.state", state_path);
}
