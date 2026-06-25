const std = @import("std");
const emulator = @import("emulator");

const Options = struct {
    frames: usize = 180,
    boot_rom_path: ?[]const u8 = null,
    smb3_first_gameplay: bool = false,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;
    const arena = init.arena;
    var args = try init.minimal.args.iterateAllocator(arena.allocator());
    _ = args.next();

    const system = args.next() orelse {
        printUsage();
        return error.MissingSystem;
    };
    const rom_path = args.next() orelse {
        printUsage();
        return error.MissingPath;
    };
    const output_path = args.next() orelse {
        printUsage();
        return error.MissingOutputPath;
    };

    var options: Options = .{};
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--frames")) {
            const value = args.next() orelse return error.MissingFrameCount;
            options.frames = try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.eql(u8, arg, "--boot-rom")) {
            options.boot_rom_path = args.next() orelse return error.MissingBootRomPath;
        } else if (std.mem.eql(u8, arg, "--smb3-first-gameplay")) {
            options.smb3_first_gameplay = true;
            if (options.frames < 760) options.frames = 760;
        } else {
            return error.UnexpectedArgument;
        }
    }

    const kind = emulator.EmulatorKind.from(system) orelse return error.UnsupportedSystem;
    if (kind == .nes and options.boot_rom_path != null) return error.BootRomNotSupported;

    var emu = emulator.Emulator.init(kind, allocator);
    defer emu.deinit();

    const rom = try std.Io.Dir.cwd().readFileAlloc(io, rom_path, allocator, .limited(emu.metadata().max_rom_size));
    defer allocator.free(rom);
    try emu.load(rom);

    if (options.boot_rom_path) |path| {
        const boot_rom = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024 + 1));
        defer allocator.free(boot_rom);
        try emu.loadBootRom(boot_rom);
    } else if (emu.requiresBootRom()) {
        return error.MissingBootRomPath;
    }

    try emu.reset();
    var frame: usize = 0;
    while (frame < options.frames) : (frame += 1) {
        emu.setInput(if (options.smb3_first_gameplay) smb3Input(frame) else .{});
        _ = try emu.stepFrame();
    }

    const ppm = try framebufferToPpm(allocator, emu.metadata(), emu.framebuffer());
    defer allocator.free(ppm);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = output_path,
        .data = ppm,
    });
}

fn smb3Input(frame: usize) emulator.InputState {
    return .{
        .start = (frame >= 90 and frame < 105) or (frame >= 300 and frame < 325),
        .a = (frame >= 430 and frame < 450) or (frame >= 520 and frame < 540) or (frame >= 610 and frame < 630),
    };
}

fn framebufferToPpm(allocator: std.mem.Allocator, metadata: emulator.Metadata, framebuffer: []const u32) ![]u8 {
    const width: usize = @intCast(metadata.width);
    const height: usize = @intCast(metadata.height);
    if (framebuffer.len != width * height) return error.InvalidFramebufferSize;

    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    try out.writer.print("P6\n{d} {d}\n255\n", .{ width, height });
    for (framebuffer) |pixel| {
        try out.writer.writeByte(@as(u8, @truncate(pixel >> 16)));
        try out.writer.writeByte(@as(u8, @truncate(pixel >> 8)));
        try out.writer.writeByte(@as(u8, @truncate(pixel)));
    }
    return out.toOwnedSlice();
}

fn printUsage() void {
    std.debug.print("Usage: capture <system> <rom_path> <output.ppm> [--frames count] [--boot-rom path] [--smb3-first-gameplay]\n", .{});
}

test "SMB3 scripted input presses start then A" {
    try std.testing.expect(!smb3Input(89).start);
    try std.testing.expect(smb3Input(90).start);
    try std.testing.expect(!smb3Input(105).start);
    try std.testing.expect(smb3Input(300).start);
    try std.testing.expect(!smb3Input(325).start);
    try std.testing.expect(smb3Input(430).a);
    try std.testing.expect(!smb3Input(450).a);
    try std.testing.expect(smb3Input(520).a);
    try std.testing.expect(smb3Input(610).a);
    try std.testing.expect(!smb3Input(630).a);
}

test "PPM conversion writes binary RGB data" {
    const pixels = [_]u32{ 0x112233, 0xaabbcc };
    const data = try framebufferToPpm(std.testing.allocator, .{
        .width = 2,
        .height = 1,
        .scale = 1,
        .frame_rate = 60,
        .audio_sample_rate = 44100,
        .max_rom_size = 1,
    }, &pixels);
    defer std.testing.allocator.free(data);

    try std.testing.expect(std.mem.startsWith(u8, data, "P6\n2 1\n255\n"));
    try std.testing.expectEqual(@as(u8, 0x11), data[data.len - 6]);
    try std.testing.expectEqual(@as(u8, 0xcc), data[data.len - 1]);
}
