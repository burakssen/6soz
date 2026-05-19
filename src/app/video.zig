const rl = @import("raylib.zig").rl;
const std = @import("std");

const Video = @This();

allocator: std.mem.Allocator,
texture: rl.Texture2D,
pixels: []u32,
scale: f32,

pub fn init(allocator: std.mem.Allocator, width: c_int, height: c_int, scale: f32) !Video {
    const pixels = try allocator.alloc(u32, @as(usize, @intCast(width * height)));
    @memset(pixels, 0);

    const image = rl.GenImageColor(width, height, rl.BLACK);
    const texture = rl.LoadTextureFromImage(image);
    rl.UnloadImage(image);

    return .{
        .allocator = allocator,
        .texture = texture,
        .pixels = pixels,
        .scale = scale,
    };
}

pub fn deinit(self: *Video) void {
    rl.UnloadTexture(self.texture);
    self.allocator.free(self.pixels);
}

pub fn updateFrame(self: *Video, frame: []const u32) void {
    const count = @min(frame.len, self.pixels.len);
    for (frame[0..count], 0..) |color, i| {
        const r = (color >> 16) & 0xFF;
        const g = (color >> 8) & 0xFF;
        const b = color & 0xFF;
        self.pixels[i] = 0xFF000000 | (b << 16) | (g << 8) | r;
    }
}

pub fn updateTexture(self: *Video) void {
    rl.UpdateTexture(self.texture, self.pixels.ptr);
}

pub fn draw(self: *const Video) void {
    rl.DrawTextureEx(self.texture, .{ .x = 0, .y = 0 }, 0, self.scale, rl.WHITE);
}
