const std = @import("std");

const emulator = @import("emulator");
const rl = @import("raylib").rl;

pub const width = 720;
pub const height = 480;
pub const visible_rows = 12;
pub const systems = [_]emulator.EmulatorKind{ .nes, .gameboy };

const list_x: c_int = 32;
const list_y: c_int = 110;
const list_width: c_int = 656;
const list_height: c_int = 306;
const row_x: c_int = list_x + 12;
const row_y: c_int = list_y + 12;
const row_width: c_int = list_width - 24;
const row_height: c_int = 22;
const row_gap: c_int = 3;

const colors = struct {
    const background = rgb(9, 13, 20);
    const header = rgb(17, 24, 36);
    const panel = rgb(18, 24, 34);
    const panel_line = rgb(49, 62, 83);
    const grid = rgba(46, 63, 88, 42);
    const scanline = rgba(255, 255, 255, 12);
    const text = rgb(236, 241, 247);
    const muted = rgb(139, 153, 174);
    const dim = rgb(83, 97, 119);
    const accent = rgb(90, 214, 198);
    const accent_hot = rgb(255, 205, 95);
    const selected_bg = rgb(31, 45, 62);
    const danger = rgb(255, 108, 116);
};

pub fn displayName(kind: emulator.EmulatorKind) []const u8 {
    return switch (kind) {
        .nes => "NES",
        .gameboy => "Game Boy",
    };
}

pub fn drawSystemMenu(selected: usize, footer: [:0]const u8) void {
    beginFrame("Choose system", "Select the emulator core", "systems");
    drawListPanel();

    for (systems, 0..) |kind, i| {
        drawListRow(i, i == selected, displayName(kind));
    }

    drawFooter(footer);
    rl.EndDrawing();
}

pub fn begin() void {
    rl.BeginDrawing();
    drawBackground();
}

pub fn selectedColor(selected: bool) rl.Color {
    return if (selected) colors.accent_hot else colors.text;
}

pub fn beginFrame(title: [:0]const u8, subtitle: [:0]const u8, badge: [:0]const u8) void {
    begin();
    drawHeader(title, subtitle, badge);
}

pub fn drawListPanel() void {
    rl.DrawRectangle(list_x, list_y, list_width, list_height, colors.panel);
    rl.DrawRectangleLines(list_x, list_y, list_width, list_height, colors.panel_line);
    rl.DrawLine(list_x, list_y, list_x + list_width, list_y, colors.accent);
}

pub fn drawListRow(index: usize, selected: bool, label: []const u8) void {
    const y = rowTop(index);
    if (selected) {
        rl.DrawRectangle(row_x, y, row_width, row_height, colors.selected_bg);
        rl.DrawRectangle(row_x, y, 5, row_height, colors.accent_hot);
    } else if (index % 2 == 1) {
        rl.DrawRectangle(row_x, y, row_width, row_height, rgba(255, 255, 255, 10));
    }

    drawFmt("{s}", .{label}, row_x + 16, y + 3, 17, selectedColor(selected));
}

pub fn drawEmpty(message: [:0]const u8) void {
    rl.DrawRectangle(row_x, row_y, row_width, 52, rgba(255, 205, 95, 18));
    rl.DrawRectangle(row_x, row_y, 5, 52, colors.accent_hot);
    drawText(message, row_x + 18, row_y + 16, 18, colors.accent_hot);
}

pub fn drawError(message: []const u8) void {
    rl.DrawRectangle(32, 382, 656, 30, rgba(255, 108, 116, 24));
    rl.DrawRectangle(32, 382, 5, 30, colors.danger);
    drawFmt("{s}", .{message}, 48, 389, 16, colors.danger);
}

pub fn drawFooter(text: [:0]const u8) void {
    rl.DrawRectangle(0, 430, width, 50, rgba(6, 9, 14, 218));
    rl.DrawLine(0, 430, width, 430, colors.panel_line);
    drawText(text, 34, 448, 16, colors.muted);
}

pub fn drawText(text: [:0]const u8, x: c_int, y: c_int, size: c_int, color: rl.Color) void {
    rl.DrawText(text.ptr, x, y, size, color);
}

pub fn drawFmt(comptime fmt: []const u8, args: anytype, x: c_int, y: c_int, size: c_int, color: rl.Color) void {
    var buffer: [512:0]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buffer, fmt, args) catch "text too long";
    rl.DrawText(text.ptr, x, y, size, color);
}

fn drawBackground() void {
    rl.ClearBackground(colors.background);
    var x: c_int = 0;
    while (x <= width) : (x += 36) rl.DrawLine(x, 0, x, height, colors.grid);

    var y: c_int = 0;
    while (y <= height) : (y += 36) rl.DrawLine(0, y, width, y, colors.grid);

    y = 5;
    while (y <= height) : (y += 10) rl.DrawLine(0, y, width, y, colors.scanline);
}

fn drawHeader(title: [:0]const u8, subtitle: [:0]const u8, badge: [:0]const u8) void {
    rl.DrawRectangle(0, 0, width, 92, colors.header);
    rl.DrawLine(0, 91, width, 91, colors.panel_line);
    rl.DrawRectangle(0, 91, width, 2, colors.accent);
    rl.DrawText("6soz", 32, 18, 34, colors.text);
    drawText(title, 34, 58, 19, colors.accent_hot);
    drawText(subtitle, 214, 61, 14, colors.muted);
    drawText(badge, 588, 24, 14, colors.dim);
}

fn rowTop(index: usize) c_int {
    return row_y + @as(c_int, @intCast(index)) * (row_height + row_gap);
}

fn rgb(r: u8, g: u8, b: u8) rl.Color {
    return rgba(r, g, b, 255);
}

fn rgba(r: u8, g: u8, b: u8, a: u8) rl.Color {
    return .{ .r = r, .g = g, .b = b, .a = a };
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
