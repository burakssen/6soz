const std = @import("std");

const rl = @import("raylib").rl;

const Emulator = @import("emulator").Emulator;
const Model = @import("emulator").Model;
const Session = @import("session");
const Video = @import("video.zig");
const Audio = @import("audio.zig");
const Input = @import("input.zig");

const App = @This();

session: Session,
video: Video,
audio: Audio,

pub fn init(io: std.Io, allocator: std.mem.Allocator, emulator: Emulator) !App {
    var session = Session.init(io, allocator, emulator);
    errdefer session.deinit();

    const metadata = session.metadata();
    rl.InitWindow(metadata.width * @as(c_int, @intFromFloat(metadata.scale)), metadata.height * @as(c_int, @intFromFloat(metadata.scale)), "6soz Emulator");
    errdefer rl.CloseWindow();
    if (!rl.IsWindowReady()) return error.WindowInitFailed;

    rl.SetTargetFPS(metadata.frame_rate);
    var video = try Video.init(allocator, metadata.width, metadata.height, metadata.scale);
    errdefer video.deinit();
    const audio = try Audio.init(metadata.audio_sample_rate);

    return .{
        .session = session,
        .video = video,
        .audio = audio,
    };
}

pub fn deinit(self: *App) void {
    self.session.persistSaveRam();
    self.session.deinit();
    self.audio.deinit();
    self.video.deinit();
    rl.CloseWindow();
}

pub fn run(self: *App, rom_path: []const u8, boot_rom_path: ?[]const u8, model: Model) !void {
    try self.session.loadRomPath(rom_path, boot_rom_path, model);
    try self.afterRomLoaded();

    while (!rl.WindowShouldClose()) {
        if (self.session.hasStatePath()) {
            if (rl.IsKeyPressed(rl.KEY_F5)) {
                self.session.writeState() catch |err| {
                    std.debug.print("Warning: failed to write state: {s}\n", .{@errorName(err)});
                };
            }
            if (rl.IsKeyPressed(rl.KEY_F8)) {
                self.session.loadState() catch |err| {
                    std.debug.print("Warning: failed to load state: {s}\n", .{@errorName(err)});
                };
                self.audio.resetSilence();
                try self.update(self.session.framebuffer());
            }
        }

        try self.runFrame();
    }
}

pub fn loadRom(self: *App, rom_data: []const u8, model: Model) !void {
    try self.session.loadRomBytes(rom_data, model);
    try self.afterRomLoaded();
}

fn afterRomLoaded(self: *App) !void {
    rl.SetTargetFPS(self.session.metadata().frame_rate);
    self.audio.resetSilence();
    try self.update(self.session.framebuffer());
}

pub fn runFrame(self: *App) !void {
    self.session.setInput(Input.read());

    const result = try self.session.stepFrame();
    self.audio.pushSamples(result.audio);

    try self.update(self.session.framebuffer());
    self.render();
}

fn update(self: *App, frame: []const u32) !void {
    self.audio.flush();
    try self.video.updateFrame(frame);
    self.video.updateTexture();
}

fn render(self: *App) void {
    rl.BeginDrawing();
    defer rl.EndDrawing();
    rl.ClearBackground(rl.BLACK);
    self.video.draw();
}
