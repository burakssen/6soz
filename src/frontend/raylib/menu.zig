const std = @import("std");

const config = @import("config");
const emulator = @import("emulator");
const roms = @import("roms");
const rl = @import("raylib").rl;
const ui = @import("menu_ui");

pub const Selection = struct {
    kind: emulator.EmulatorKind,
    rom_path: []const u8,
    model: emulator.Model,
    boot_rom_path: ?[]const u8,

    pub fn deinit(self: Selection, allocator: std.mem.Allocator) void {
        allocator.free(self.rom_path);
    }
};

pub fn run(io: std.Io, allocator: std.mem.Allocator, cfg: config.Config) !?Selection {
    rl.InitWindow(ui.width, ui.height, "6soz");
    defer rl.CloseWindow();
    if (!rl.IsWindowReady()) return error.WindowInitFailed;
    rl.SetTargetFPS(60);

    var screen: enum { systems, roms } = .systems;
    var system_index = ui.indexOfSystem(cfg.last.system orelse cfg.default_system);
    var rom_index: usize = 0;
    var scroll: usize = 0;
    var discovered = try allocator.alloc(roms.Entry, 0);
    defer roms.freeEntries(allocator, discovered);

    var error_message: ?[]const u8 = null;
    while (!rl.WindowShouldClose()) {
        if (rl.IsKeyPressed(rl.KEY_ESCAPE)) switch (screen) {
            .systems => return null,
            .roms => {
                screen = .systems;
                error_message = null;
            },
        };

        switch (screen) {
            .systems => {
                updateIndex(&system_index, ui.systems.len);
                if (rl.IsKeyPressed(rl.KEY_ENTER)) {
                    roms.freeEntries(allocator, discovered);
                    discovered = try roms.discover(io, allocator, cfg.roms_path, ui.systems[system_index], cfg);
                    rom_index = 0;
                    scroll = 0;
                    error_message = null;
                    screen = .roms;
                }
                ui.drawSystemMenu(system_index, "Enter select  Escape quit");
            },
            .roms => {
                updateRomSelection(&rom_index, &scroll, discovered.len);
                if (rl.IsKeyPressed(rl.KEY_ENTER) and discovered.len != 0) {
                    const kind = ui.systems[system_index];
                    const model = if (kind == .gameboy) cfg.gameboy_model else .auto;
                    const boot_rom_path = config.bootRomPath(cfg, kind, model);
                    if (kind == .gameboy and boot_rom_path == null) {
                        error_message = "Game Boy boot ROM path is missing in config.zon";
                    } else return .{
                        .kind = kind,
                        .rom_path = try allocator.dupe(u8, discovered[rom_index].path),
                        .model = model,
                        .boot_rom_path = boot_rom_path,
                    };
                }
                renderRoms(ui.systems[system_index], discovered, rom_index, scroll, error_message);
            },
        }
    }
    return null;
}

fn updateIndex(index: *usize, len: usize) void {
    if (rl.IsKeyPressed(rl.KEY_UP)) index.* = ui.previousIndex(index.*, len);
    if (rl.IsKeyPressed(rl.KEY_DOWN)) index.* = ui.nextIndex(index.*, len);
}

fn updateRomSelection(index: *usize, scroll: *usize, len: usize) void {
    if (len == 0) return;
    updateIndex(index, len);
    ui.adjustScroll(scroll, index.*);
}

fn renderRoms(
    kind: emulator.EmulatorKind,
    entries: []const roms.Entry,
    selected: usize,
    scroll: usize,
    error_message: ?[]const u8,
) void {
    ui.begin();
    defer rl.EndDrawing();

    ui.drawFmt("{s} ROMs", .{ui.displayName(kind)}, 32, 26, 30, rl.RAYWHITE);
    if (entries.len == 0) {
        ui.drawText("No compatible ROMs found.", 34, 110, 22, rl.YELLOW);
        ui.drawText("Escape back", 34, 430, 18, rl.GRAY);
        return;
    }

    for (entries[scroll..@min(entries.len, scroll + ui.visible_rows)], scroll..) |entry, index| {
        const y: c_int = 86 + @as(c_int, @intCast(index - scroll)) * 28;
        ui.drawFmt("{s}{s}", .{ if (index == selected) "> " else "  ", entry.name }, 42, y, 20, ui.selectedColor(index == selected));
    }

    if (error_message) |message| ui.drawFmt("{s}", .{message}, 34, 386, 18, rl.RED);
    ui.drawText("Enter launch  Escape back", 34, 430, 18, rl.GRAY);
}
