const std = @import("std");

const emulator = @import("emulator");
const rl = @import("raylib").rl;

pub const width = 720;
pub const height = 480;
pub const visible_rows = 12;
pub const systems = [_]emulator.EmulatorKind{ .nes, .gameboy };

pub fn displayName(kind: emulator.EmulatorKind) []const u8 {
    return switch (kind) {
        .nes => "NES",
        .gameboy => "Game Boy",
    };
}

pub fn drawSystemMenu(selected: usize, footer: [:0]const u8) void {
    begin();
    drawText("6soz", 32, 26, 34, rl.RAYWHITE);
    drawText("Choose a system", 34, 78, 20, rl.LIGHTGRAY);

    for (systems, 0..) |kind, i| {
        const y: c_int = 132 + @as(c_int, @intCast(i)) * 44;
        drawFmt("{s}{s}", .{ if (i == selected) "> " else "  ", displayName(kind) }, 54, y, 24, selectedColor(i == selected));
    }

    drawText(footer, 34, 430, 18, rl.GRAY);
    rl.EndDrawing();
}

pub fn begin() void {
    rl.BeginDrawing();
    rl.ClearBackground(rl.BLACK);
}

pub fn selectedColor(selected: bool) rl.Color {
    return if (selected) rl.YELLOW else rl.RAYWHITE;
}

pub fn drawText(text: [:0]const u8, x: c_int, y: c_int, size: c_int, color: rl.Color) void {
    rl.DrawText(text.ptr, x, y, size, color);
}

pub fn drawFmt(comptime fmt: []const u8, args: anytype, x: c_int, y: c_int, size: c_int, color: rl.Color) void {
    var buffer: [512:0]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buffer, fmt, args) catch "text too long";
    rl.DrawText(text.ptr, x, y, size, color);
}

pub fn indexOfSystem(kind: emulator.EmulatorKind) usize {
    for (systems, 0..) |candidate, index| {
        if (candidate == kind) return index;
    }
    return 0;
}

pub fn previousIndex(index: usize, len: usize) usize {
    if (len == 0) return 0;
    return if (index == 0) len - 1 else index - 1;
}

pub fn nextIndex(index: usize, len: usize) usize {
    if (len == 0) return 0;
    return if (index + 1 == len) 0 else index + 1;
}

pub fn adjustScroll(scroll: *usize, selected: usize) void {
    if (selected < scroll.*) {
        scroll.* = selected;
    } else if (selected >= scroll.* + visible_rows) {
        scroll.* = selected + 1 - visible_rows;
    }
}
