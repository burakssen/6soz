const std = @import("std");

const rl = @import("raylib.zig").rl;

const Emulator = @import("emulator").Emulator;
const Model = @import("emulator").Model;
const Video = @import("video.zig");
const Audio = @import("audio.zig");
const Input = @import("input.zig");

const App = @This();

io: std.Io,
allocator: std.mem.Allocator,
emulator: Emulator,
video: Video,
audio: Audio,

pub fn init(io: std.Io, allocator: std.mem.Allocator, emulator: Emulator) !App {
    var owned_emulator = emulator;
    errdefer owned_emulator.deinit();

    const metadata = owned_emulator.metadata();
    rl.InitWindow(metadata.width * @as(c_int, @intFromFloat(metadata.scale)), metadata.height * @as(c_int, @intFromFloat(metadata.scale)), "6soz Emulator");
    errdefer rl.CloseWindow();
    if (!rl.IsWindowReady()) return error.WindowInitFailed;

    rl.SetTargetFPS(metadata.frame_rate);
    var video = try Video.init(allocator, metadata.width, metadata.height, metadata.scale);
    errdefer video.deinit();
    const audio = try Audio.init(metadata.audio_sample_rate);

    return .{
        .io = io,
        .allocator = allocator,
        .emulator = owned_emulator,
        .video = video,
        .audio = audio,
    };
}

pub fn deinit(self: *App) void {
    self.emulator.deinit();
    self.audio.deinit();
    self.video.deinit();
    rl.CloseWindow();
}

pub fn run(self: *App, rom_path: []const u8, boot_rom_path: ?[]const u8, model: Model) !void {
    var save_path: ?[]u8 = null;
    defer if (save_path) |path| self.allocator.free(path);
    defer if (save_path) |path| {
        self.writeSaveRam(path) catch |err| {
            std.debug.print("Warning: failed to write save RAM to {s}: {s}\n", .{ path, @errorName(err) });
        };
    };

    if (rom_path.len == 0) {
        try self.emulator.load(&.{});
    } else {
        const rom_data = try std.Io.Dir.cwd().readFileAlloc(self.io, rom_path, self.allocator, .limited(self.emulator.metadata().max_rom_size));
        defer self.allocator.free(rom_data);
        try self.emulator.load(rom_data);
        try self.emulator.setModel(model);

        if (boot_rom_path) |path| {
            const boot_rom = try std.Io.Dir.cwd().readFileAlloc(self.io, path, self.allocator, .limited(1024 * 1024 + 1));
            defer self.allocator.free(boot_rom);
            try self.emulator.loadBootRom(boot_rom);
        } else if (self.emulator.requiresBootRom()) {
            return error.BootRomRequired;
        }

        save_path = try std.fmt.allocPrint(self.allocator, "{s}.sav", .{rom_path});
        try self.loadSaveRam(save_path.?);
    }
    rl.SetTargetFPS(self.emulator.metadata().frame_rate);
    try self.emulator.reset();

    while (!rl.WindowShouldClose()) {
        self.emulator.setInput(Input.read());

        const result = try self.emulator.stepFrame();
        self.audio.pushSamples(result.audio);

        try self.update(self.emulator.framebuffer());
        self.render();
    }
}

fn loadSaveRam(self: *App, save_path: []const u8) !void {
    const save_data = std.Io.Dir.cwd().readFileAlloc(self.io, save_path, self.allocator, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return,
        else => |e| return e,
    };
    defer self.allocator.free(save_data);

    self.emulator.loadSaveRam(save_data) catch |err| switch (err) {
        error.NoSaveRam, error.InvalidSaveRamSize, error.InvalidSave => {
            std.debug.print("Warning: ignoring save RAM from {s}: {s}\n", .{ save_path, @errorName(err) });
        },
        else => |e| return e,
    };
}

fn writeSaveRam(self: *App, save_path: []const u8) !void {
    const save_data = self.emulator.saveRam() orelse return;
    try std.Io.Dir.cwd().writeFile(self.io, .{
        .sub_path = save_path,
        .data = save_data,
    });
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
