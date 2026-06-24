const std = @import("std");

const App = @import("app");
const emulator = @import("emulator");
const rl = @import("raylib").rl;

extern fn emscripten_set_main_loop(*const fn () callconv(.c) void, c_int, c_int) void;
extern fn emscripten_cancel_main_loop() void;

pub const panic = std.debug.FullPanic(std.debug.defaultPanic);

const default_rom_path = "/roms/nes/ravens_gate_mmc1.nes";

var app: ?App = null;
const allocator = std.heap.c_allocator;

export fn main(argc: c_int, argv: [*]?[*:0]u8) c_int {
    _ = argc;
    _ = argv;

    start() catch |err| {
        std.log.err("failed to start web emulator: {s}", .{@errorName(err)});
        return 1;
    };
    return 0;
}

fn start() !void {
    var selected_emulator = emulator.Emulator.init(.nes, allocator);
    errdefer selected_emulator.deinit();

    app = try App.init(undefined, allocator, selected_emulator);
    errdefer {
        if (app) |*running| running.deinit();
        app = null;
    }

    var data_size: c_int = 0;
    const rom_ptr = rl.LoadFileData(default_rom_path, &data_size);
    if (rom_ptr == null or data_size <= 0) return error.DefaultRomLoadFailed;
    defer rl.UnloadFileData(rom_ptr);

    const rom_data = rom_ptr[0..@as(usize, @intCast(data_size))];
    try app.?.loadRom(rom_data, .auto);

    emscripten_set_main_loop(updateFrame, 0, 0);
}

fn updateFrame() callconv(.c) void {
    if (app) |*running| {
        running.runFrame() catch |err| {
            std.log.err("web emulator frame failed: {s}", .{@errorName(err)});
            emscripten_cancel_main_loop();
        };
    }
}
