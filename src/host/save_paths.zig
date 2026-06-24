const std = @import("std");

pub fn saveRamPath(allocator: std.mem.Allocator, rom_path: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}.sav", .{rom_path});
}

pub fn statePath(allocator: std.mem.Allocator, rom_path: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}.state", .{rom_path});
}
