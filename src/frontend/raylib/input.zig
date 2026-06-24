const rl = @import("raylib").rl;
const emulator = @import("emulator");
const config = @import("config");
const std = @import("std");

pub const KeyBindings = struct {
    a: c_int = rl.KEY_Z,
    b: c_int = rl.KEY_X,
    select: c_int = rl.KEY_RIGHT_SHIFT,
    start: c_int = rl.KEY_ENTER,
    up: c_int = rl.KEY_UP,
    down: c_int = rl.KEY_DOWN,
    left: c_int = rl.KEY_LEFT,
    right: c_int = rl.KEY_RIGHT,
};

pub fn bindingsFromConfig(controls: config.Controls) !KeyBindings {
    return .{
        .a = try keyFromName(controls.a),
        .b = try keyFromName(controls.b),
        .select = try keyFromName(controls.select),
        .start = try keyFromName(controls.start),
        .up = try keyFromName(controls.up),
        .down = try keyFromName(controls.down),
        .left = try keyFromName(controls.left),
        .right = try keyFromName(controls.right),
    };
}

pub fn read(bindings: KeyBindings) emulator.InputState {
    return .{
        .a = rl.IsKeyDown(bindings.a),
        .b = rl.IsKeyDown(bindings.b),
        .select = rl.IsKeyDown(bindings.select),
        .start = rl.IsKeyDown(bindings.start),
        .up = rl.IsKeyDown(bindings.up),
        .down = rl.IsKeyDown(bindings.down),
        .left = rl.IsKeyDown(bindings.left),
        .right = rl.IsKeyDown(bindings.right),
    };
}

pub fn keyFromName(name: []const u8) !c_int {
    for (key_names) |entry| {
        if (std.ascii.eqlIgnoreCase(name, entry.name)) return entry.key;
    }
    return error.UnknownKeyName;
}

const key_names = [_]struct { name: []const u8, key: c_int }{
    .{ .name = "A", .key = rl.KEY_A },
    .{ .name = "B", .key = rl.KEY_B },
    .{ .name = "C", .key = rl.KEY_C },
    .{ .name = "D", .key = rl.KEY_D },
    .{ .name = "E", .key = rl.KEY_E },
    .{ .name = "F", .key = rl.KEY_F },
    .{ .name = "G", .key = rl.KEY_G },
    .{ .name = "H", .key = rl.KEY_H },
    .{ .name = "I", .key = rl.KEY_I },
    .{ .name = "J", .key = rl.KEY_J },
    .{ .name = "K", .key = rl.KEY_K },
    .{ .name = "L", .key = rl.KEY_L },
    .{ .name = "M", .key = rl.KEY_M },
    .{ .name = "N", .key = rl.KEY_N },
    .{ .name = "O", .key = rl.KEY_O },
    .{ .name = "P", .key = rl.KEY_P },
    .{ .name = "Q", .key = rl.KEY_Q },
    .{ .name = "R", .key = rl.KEY_R },
    .{ .name = "S", .key = rl.KEY_S },
    .{ .name = "T", .key = rl.KEY_T },
    .{ .name = "U", .key = rl.KEY_U },
    .{ .name = "V", .key = rl.KEY_V },
    .{ .name = "W", .key = rl.KEY_W },
    .{ .name = "X", .key = rl.KEY_X },
    .{ .name = "Y", .key = rl.KEY_Y },
    .{ .name = "Z", .key = rl.KEY_Z },
    .{ .name = "Enter", .key = rl.KEY_ENTER },
    .{ .name = "RightShift", .key = rl.KEY_RIGHT_SHIFT },
    .{ .name = "LeftShift", .key = rl.KEY_LEFT_SHIFT },
    .{ .name = "Space", .key = rl.KEY_SPACE },
    .{ .name = "Up", .key = rl.KEY_UP },
    .{ .name = "Down", .key = rl.KEY_DOWN },
    .{ .name = "Left", .key = rl.KEY_LEFT },
    .{ .name = "Right", .key = rl.KEY_RIGHT },
    .{ .name = "Tab", .key = rl.KEY_TAB },
    .{ .name = "Backspace", .key = rl.KEY_BACKSPACE },
};

test "key names parse case insensitively" {
    try std.testing.expectEqual(@as(c_int, rl.KEY_Z), try keyFromName("z"));
    try std.testing.expectEqual(@as(c_int, rl.KEY_ENTER), try keyFromName("Enter"));
}
