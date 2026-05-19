const std = @import("std");
const backend = @import("backend");
const App = @import("app");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;
    const arena = init.arena;
    var args = try init.minimal.args.iterateAllocator(arena.allocator());
    _ = args.next(); // Skip the executable name

    const platform = args.next() orelse {
        printUsage();
        std.process.exit(2);
    };

    const rom_path = args.next() orelse {
        printUsage();
        std.process.exit(2);
    };

    const b = backend.Backend.init(.from(platform), allocator) catch {
        std.debug.print("Unsupported platform: {s}\n\n", .{platform});
        printUsage();
        std.process.exit(2);
    };

    var app = try App.init(io, allocator, b);
    defer app.deinit();

    try app.run(rom_path);
}

fn printUsage() void {
    std.debug.print("Usage: 6soz <platform> <rom_path>\n", .{});
    std.debug.print("Supported platforms: nes\n", .{});
}
