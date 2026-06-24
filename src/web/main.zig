const std = @import("std");

const App = @import("app");
const emulator = @import("emulator");
const manifest = @import("web_rom_manifest");
const rl = @import("raylib").rl;
const ui = @import("menu_ui");

extern fn emscripten_set_main_loop(*const fn () callconv(.c) void, c_int, c_int) void;
extern fn emscripten_cancel_main_loop() void;

pub const panic = std.debug.FullPanic(std.debug.defaultPanic);

const allocator = std.heap.c_allocator;

const Screen = enum {
    systems,
    roms,
    game,
};

var screen: Screen = .systems;
var system_index: usize = 0;
var rom_index: usize = 0;
var scroll: usize = 0;
var app: ?App = null;
var error_message: ?[]const u8 = null;

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
    rl.InitWindow(ui.width, ui.height, "6soz");
    if (!rl.IsWindowReady()) return error.WindowInitFailed;
    rl.SetExitKey(0);

    emscripten_set_main_loop(updateFrame, 0, 0);
}

fn updateFrame() callconv(.c) void {
    updateFrameInner() catch |err| {
        std.log.err("web emulator frame failed: {s}", .{@errorName(err)});
        emscripten_cancel_main_loop();
    };
}

fn updateFrameInner() !void {
    if (rl.WindowShouldClose()) {
        emscripten_cancel_main_loop();
        return;
    }

    switch (screen) {
        .systems => updateSystems(),
        .roms => try updateRoms(),
        .game => try updateGame(),
    }
}

fn updateSystems() void {
    updateIndex(&system_index, ui.systems.len);
    if (rl.IsKeyPressed(rl.KEY_ENTER)) {
        screen = .roms;
        rom_index = 0;
        scroll = 0;
        error_message = null;
    }

    ui.drawSystemMenu(system_index, "Enter select");
}

fn updateRoms() !void {
    const kind = ui.systems[system_index];
    const count = playableCount(kind);

    if (rl.IsKeyPressed(rl.KEY_ESCAPE)) {
        screen = .systems;
        error_message = null;
        ui.drawSystemMenu(system_index, "Enter select");
        return;
    }

    updateRomSelection(count);

    if (rl.IsKeyPressed(rl.KEY_ENTER) and count != 0) {
        const entry = playableEntryAt(kind, rom_index).?;
        startGame(entry) catch |err| {
            error_message = @errorName(err);
        };
    }

    renderRoms(kind, count);
}

fn updateGame() !void {
    if (rl.IsKeyPressed(rl.KEY_ESCAPE)) {
        returnToMenu();
        renderRoms(ui.systems[system_index], playableCount(ui.systems[system_index]));
        return;
    }

    if (app) |*running| {
        try running.runFrame();
    }
}

fn startGame(entry: manifest.RomEntry) !void {
    if (app) |*running| {
        running.deinit();
        app = null;
    }

    var selected_emulator = emulator.Emulator.init(entry.kind, allocator);
    errdefer selected_emulator.deinit();

    app = try App.initInOpenWindow(undefined, allocator, selected_emulator, .{});
    errdefer {
        if (app) |*running| running.deinit();
        app = null;
    }

    var rom_size: c_int = 0;
    const rom_ptr = rl.LoadFileData(entry.path.ptr, &rom_size);
    if (rom_ptr == null or rom_size <= 0) return error.RomLoadFailed;
    defer rl.UnloadFileData(rom_ptr);

    var boot_size: c_int = 0;
    var boot_ptr: ?[*]u8 = null;
    defer if (boot_ptr) |ptr| rl.UnloadFileData(ptr);

    if (entry.kind == .gameboy) {
        const boot_path = manifest.dmg_boot_rom_path orelse return error.BootRomRequired;
        boot_ptr = rl.LoadFileData(boot_path.ptr, &boot_size);
        if (boot_ptr == null or boot_size <= 0) return error.BootRomLoadFailed;
    }

    const rom_data = rom_ptr[0..@as(usize, @intCast(rom_size))];
    const boot_data = if (boot_ptr) |ptr| ptr[0..@as(usize, @intCast(boot_size))] else null;
    try app.?.loadRomWithBoot(rom_data, boot_data, .auto);

    screen = .game;
    error_message = null;
}

fn returnToMenu() void {
    if (app) |*running| {
        running.deinit();
        app = null;
    }
    rl.SetWindowSize(ui.width, ui.height);
    screen = .roms;
    error_message = null;
}

fn renderRoms(kind: emulator.EmulatorKind, count: usize) void {
    ui.beginFrame("Select ROM", "Preloaded files from roms/", "preload");
    defer rl.EndDrawing();

    ui.drawFmt("{s} ROMs", .{ui.displayName(kind)}, 588, 48, 14, rl.GRAY);
    ui.drawListPanel();

    if (count == 0) {
        ui.drawEmpty("No compatible ROMs were preloaded.");
        ui.drawFooter("Escape back");
        return;
    }

    var index = scroll;
    while (index < @min(count, scroll + ui.visible_rows)) : (index += 1) {
        ui.drawListRow(index - scroll, index == rom_index, playableEntryAt(kind, index).?.name);
    }

    if (error_message) |message| {
        ui.drawError(message);
    }
    ui.drawFooter("Enter launch  Escape back");
}

fn playableCount(kind: emulator.EmulatorKind) usize {
    var count: usize = 0;
    for (manifest.entries) |entry| {
        if (entry.kind == kind and !entry.boot) count += 1;
    }
    return count;
}

fn playableEntryAt(kind: emulator.EmulatorKind, index: usize) ?manifest.RomEntry {
    var current: usize = 0;
    for (manifest.entries) |entry| {
        if (entry.kind != kind or entry.boot) continue;
        if (current == index) return entry;
        current += 1;
    }
    return null;
}

fn updateIndex(index: *usize, len: usize) void {
    if (rl.IsKeyPressed(rl.KEY_UP)) index.* = ui.previousIndex(index.*, len);
    if (rl.IsKeyPressed(rl.KEY_DOWN)) index.* = ui.nextIndex(index.*, len);
}

fn updateRomSelection(count: usize) void {
    if (count == 0) return;
    updateIndex(&rom_index, count);
    ui.adjustScroll(&scroll, rom_index);
}
