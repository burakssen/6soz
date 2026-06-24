const std = @import("std");
const builtin = @import("builtin");

const rl = @import("raylib").rl;

const Emulator = @import("emulator").Emulator;
const Model = @import("emulator").Model;
const config = @import("config");
const Session = @import("session");
const Video = @import("video.zig");
const Audio = @import("audio.zig");
const Input = @import("input.zig");

const App = @This();

session: Session,
video: Video,
audio: ?Audio,
controls: Input.KeyBindings,
load_options: Session.LoadOptions,
owns_window: bool,

pub const Options = struct {
    video_scale: ?f32 = null,
    audio_enabled: bool = true,
    controls: Input.KeyBindings = .{},
    load_options: Session.LoadOptions = .{},
};

pub fn optionsFromConfig(cfg: config.Config) !Options {
    return .{
        .video_scale = cfg.video.scale,
        .audio_enabled = cfg.audio.enabled,
        .controls = try Input.bindingsFromConfig(cfg.controls),
        .load_options = .{
            .save_dir = cfg.saves.save_dir,
            .state_dir = cfg.saves.state_dir,
        },
    };
}

pub fn init(io: std.Io, allocator: std.mem.Allocator, emulator: Emulator) !App {
    return initWithOptions(io, allocator, emulator, .{});
}

pub fn initWithOptions(io: std.Io, allocator: std.mem.Allocator, emulator: Emulator, options: Options) !App {
    return initInternal(io, allocator, emulator, options, true);
}

pub fn initInOpenWindow(io: std.Io, allocator: std.mem.Allocator, emulator: Emulator, options: Options) !App {
    return initInternal(io, allocator, emulator, options, false);
}

fn initInternal(io: std.Io, allocator: std.mem.Allocator, emulator: Emulator, options: Options, owns_window: bool) !App {
    var session = Session.init(io, allocator, emulator);
    errdefer session.deinit();

    const metadata = session.metadata();
    const scale = options.video_scale orelse metadata.scale;
    const window_width = metadata.width * @as(c_int, @intFromFloat(scale));
    const window_height = metadata.height * @as(c_int, @intFromFloat(scale));
    if (owns_window) {
        rl.InitWindow(window_width, window_height, "6soz Emulator");
        errdefer rl.CloseWindow();
    } else {
        rl.SetWindowSize(window_width, window_height);
    }
    if (!rl.IsWindowReady()) return error.WindowInitFailed;

    setTargetFps(metadata.frame_rate);
    var video = try Video.init(allocator, metadata.width, metadata.height, scale);
    errdefer video.deinit();
    const audio = if (options.audio_enabled) try Audio.init(metadata.audio_sample_rate) else null;
    errdefer if (audio) |*stream| stream.deinit();

    return .{
        .session = session,
        .video = video,
        .audio = audio,
        .controls = options.controls,
        .load_options = options.load_options,
        .owns_window = owns_window,
    };
}

pub fn deinit(self: *App) void {
    self.session.persistSaveRam();
    self.session.deinit();
    if (self.audio) |*audio| audio.deinit();
    self.video.deinit();
    if (self.owns_window) rl.CloseWindow();
}

pub fn run(self: *App, rom_path: []const u8, boot_rom_path: ?[]const u8, model: Model) !void {
    try self.session.loadRomPathWithOptions(rom_path, boot_rom_path, model, self.load_options);
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
                if (self.audio) |*audio| audio.resetSilence();
                try self.update(self.session.framebuffer());
            }
        }

        try self.runFrame();
    }
}

pub fn loadRom(self: *App, rom_data: []const u8, model: Model) !void {
    try self.loadRomWithBoot(rom_data, null, model);
}

pub fn loadRomWithBoot(self: *App, rom_data: []const u8, boot_rom_data: ?[]const u8, model: Model) !void {
    try self.session.loadRomBytesWithBoot(rom_data, boot_rom_data, model);
    try self.afterRomLoaded();
}

fn afterRomLoaded(self: *App) !void {
    setTargetFps(self.session.metadata().frame_rate);
    if (self.audio) |*audio| audio.resetSilence();
    try self.update(self.session.framebuffer());
}

pub fn runFrame(self: *App) !void {
    self.session.setInput(Input.read(self.controls));

    const result = try self.session.stepFrame();
    if (self.audio) |*audio| audio.pushSamples(result.audio);

    try self.update(self.session.framebuffer());
    self.render();
}

fn update(self: *App, frame: []const u32) !void {
    if (self.audio) |*audio| audio.flush();
    try self.video.updateFrame(frame);
    self.video.updateTexture();
}

fn render(self: *App) void {
    rl.BeginDrawing();
    defer rl.EndDrawing();
    rl.ClearBackground(rl.BLACK);
    self.video.draw();
}

fn setTargetFps(frame_rate: c_int) void {
    if (builtin.os.tag != .emscripten) {
        rl.SetTargetFPS(frame_rate);
    }
}
