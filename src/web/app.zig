const std = @import("std");

const EmulatorHost = @import("emulator");
const rl = @import("raylib").rl;
const Audio = @import("audio");
const Video = @import("video");

const WebApp = @This();

allocator: std.mem.Allocator,
emulator: EmulatorHost.Emulator,
video: Video,
audio: ?Audio,

pub fn initInOpenWindow(allocator: std.mem.Allocator, emulator: EmulatorHost.Emulator) !WebApp {
    const metadata = emulator.metadata();
    const scale = metadata.scale;
    const window_width = metadata.width * @as(c_int, @intFromFloat(scale));
    const window_height = metadata.height * @as(c_int, @intFromFloat(scale));

    rl.SetWindowSize(window_width, window_height);
    if (!rl.IsWindowReady()) return error.WindowInitFailed;

    var selected_emulator = emulator;
    errdefer selected_emulator.deinit();

    var video = try Video.init(allocator, metadata.width, metadata.height, scale);
    errdefer video.deinit();
    const audio = if (metadata.audio_sample_rate != 0) try Audio.init(metadata.audio_sample_rate) else null;
    errdefer if (audio) |*stream| stream.deinit();

    return .{
        .allocator = allocator,
        .emulator = selected_emulator,
        .video = video,
        .audio = audio,
    };
}

pub fn deinit(self: *WebApp) void {
    self.emulator.deinit();
    if (self.audio) |*audio| audio.deinit();
    self.video.deinit();
}

pub fn loadRomWithBoot(
    self: *WebApp,
    rom_data: []const u8,
    boot_rom_data: ?[]const u8,
    model: EmulatorHost.Model,
) !void {
    try self.emulator.load(rom_data);
    try self.emulator.setModel(model);
    if (boot_rom_data) |boot_rom| {
        try self.emulator.loadBootRom(boot_rom);
    } else if (self.emulator.requiresBootRom()) {
        return error.BootRomRequired;
    }
    try self.emulator.reset();
    try self.afterRomLoaded();
}

pub fn runFrame(self: *WebApp) !void {
    self.emulator.setInput(readInput());

    const result = try self.emulator.stepFrame();
    if (self.audio) |*audio| audio.pushSamples(result.audio);

    try self.update(self.emulator.framebuffer());
    self.render();
}

fn afterRomLoaded(self: *WebApp) !void {
    if (self.audio) |*audio| audio.resetSilence();
    try self.update(self.emulator.framebuffer());
}

fn update(self: *WebApp, frame: []const u32) !void {
    if (self.audio) |*audio| audio.flush();
    try self.video.updateFrame(frame);
    self.video.updateTexture();
}

fn render(self: *WebApp) void {
    rl.BeginDrawing();
    defer rl.EndDrawing();
    rl.ClearBackground(rl.BLACK);
    self.video.draw();
}

fn readInput() EmulatorHost.InputState {
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
