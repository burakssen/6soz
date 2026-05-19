const rl = @import("raylib.zig").rl;
const Backend = @import("backend");

pub fn read() Backend.InputState {
    return .{
        .a = rl.IsKeyDown(rl.KEY_Z),
        .b = rl.IsKeyDown(rl.KEY_X),
        .select = rl.IsKeyDown(rl.KEY_RIGHT_SHIFT),
        .start = rl.IsKeyDown(rl.KEY_ENTER),
        .up = rl.IsKeyDown(rl.KEY_UP),
        .down = rl.IsKeyDown(rl.KEY_DOWN),
        .left = rl.IsKeyDown(rl.KEY_LEFT),
        .right = rl.IsKeyDown(rl.KEY_RIGHT),
    };
}
