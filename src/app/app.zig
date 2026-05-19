const std = @import("std");

const rl = @import("raylib.zig").rl;

const Backend = @import("backend").Backend;
const Video = @import("video.zig");
const Audio = @import("audio.zig");
const Input = @import("input.zig");

const App = @This();

io: std.Io,
allocator: std.mem.Allocator,
backend: Backend,
video: Video,
audio: Audio,
cycle_remainder: f64 = 0,

pub fn init(io: std.Io, allocator: std.mem.Allocator, backend: Backend) !App {
    var owned_backend = backend;
    errdefer owned_backend.deinit();

    const scale = owned_backend.scale();
    rl.InitWindow(owned_backend.width() * @as(c_int, @intFromFloat(scale)), owned_backend.height() * @as(c_int, @intFromFloat(scale)), "6soz Emulator");
    errdefer rl.CloseWindow();

    rl.SetTargetFPS(60);
    const video = try Video.init(allocator, owned_backend.width(), owned_backend.height(), scale);

    return .{
        .io = io,
        .allocator = allocator,
        .backend = owned_backend,
        .video = video,
        .audio = Audio.init(),
    };
}

pub fn deinit(self: *App) void {
    self.backend.deinit();
    self.audio.deinit();
    self.video.deinit();
    rl.CloseWindow();
}

pub fn run(self: *App, rom_path: []const u8) !void {
    if (rom_path.len == 0) {
        try self.backend.load(&.{});
    } else {
        const rom_data = try std.Io.Dir.cwd().readFileAlloc(self.io, rom_path, self.allocator, .limited(self.backend.maxRomSize()));
        defer self.allocator.free(rom_data);
        try self.backend.load(rom_data);
    }
    self.backend.reset();

    while (!rl.WindowShouldClose()) {
        self.backend.setInput(Input.read());

        var cycles: u32 = 0;
        const cycle_budget_float = self.backend.frameCpuCycles() + self.cycle_remainder;
        const cycle_budget = @as(u32, @intFromFloat(@floor(cycle_budget_float)));
        self.cycle_remainder = cycle_budget_float - @as(f64, @floatFromInt(cycle_budget));
        while (cycles < cycle_budget) {
            const result = try self.backend.step();
            cycles += result.cycles;
            self.audio.pushSamples(result.audio);
        }

        try self.update(self.backend.framebuffer());
        try self.render();
    }
}

fn update(self: *App, frame: []const u32) !void {
    self.audio.flush();
    self.video.updateFrame(frame);
    self.video.updateTexture();
}

fn render(self: *App) !void {
    rl.BeginDrawing();
    defer rl.EndDrawing();
    rl.ClearBackground(rl.BLACK);
    self.video.draw();
}
