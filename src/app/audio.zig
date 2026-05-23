const std = @import("std");

const rl = @import("raylib.zig").rl;

const SampleRate = 48_000;
const BufferFrames = 512;
const QueueFrames = 16_384;
const StartupPrefillFrames = BufferFrames * 4;
const MaxQueueDepth = QueueFrames - BufferFrames;

const Audio = @This();

stream: rl.AudioStream,
queue: AudioQueue = .{},
out: [BufferFrames]f32 = [_]f32{0} ** BufferFrames,
underruns: u64 = 0,
overflows: u64 = 0,

pub fn init() !Audio {
    rl.InitAudioDevice();
    errdefer rl.CloseAudioDevice();
    if (!rl.IsAudioDeviceReady()) return error.AudioDeviceInitFailed;

    rl.SetAudioStreamBufferSizeDefault(BufferFrames);
    const stream = rl.LoadAudioStream(SampleRate, 32, 1);
    if (!rl.IsAudioStreamValid(stream)) return error.AudioStreamInitFailed;
    errdefer rl.UnloadAudioStream(stream);

    var audio = Audio{ .stream = stream };
    audio.queue.prefillSilence(StartupPrefillFrames);
    rl.PlayAudioStream(stream);
    return audio;
}

pub fn deinit(self: *Audio) void {
    self.flush();
    rl.UnloadAudioStream(self.stream);
    rl.CloseAudioDevice();
}

pub fn pushSamples(self: *Audio, samples: []const f32) void {
    self.overflows += self.queue.pushSlice(samples);
    self.overflows += self.queue.trimOldestTo(MaxQueueDepth);
    self.flush();
}

pub fn flush(self: *Audio) void {
    while (rl.IsAudioStreamProcessed(self.stream)) {
        const missing = self.queue.popChunk(&self.out);
        if (missing != 0) self.underruns += 1;
        rl.UpdateAudioStream(self.stream, &self.out, BufferFrames);
    }
}

pub fn queuedFrames(self: *const Audio) usize {
    return self.queue.len;
}

const AudioQueue = struct {
    data: [QueueFrames]f32 = [_]f32{0} ** QueueFrames,
    read: usize = 0,
    write: usize = 0,
    len: usize = 0,

    fn pushSlice(self: *AudioQueue, samples: []const f32) usize {
        var trimmed: usize = 0;
        for (samples) |sample| {
            if (self.len == self.data.len) {
                self.dropOldest(1);
                trimmed += 1;
            }
            self.data[self.write] = sample;
            self.write = (self.write + 1) % self.data.len;
            self.len += 1;
        }
        return trimmed;
    }

    fn popChunk(self: *AudioQueue, out: []f32) usize {
        var missing: usize = 0;
        for (out) |*sample| {
            if (self.len == 0) {
                sample.* = 0;
                missing += 1;
            } else {
                sample.* = self.data[self.read];
                self.read = (self.read + 1) % self.data.len;
                self.len -= 1;
            }
        }
        return missing;
    }

    fn prefillSilence(self: *AudioQueue, count: usize) void {
        var i: usize = 0;
        while (i < count and self.len < self.data.len) : (i += 1) {
            self.data[self.write] = 0;
            self.write = (self.write + 1) % self.data.len;
            self.len += 1;
        }
    }

    fn trimOldestTo(self: *AudioQueue, target: usize) usize {
        if (self.len <= target) return 0;
        const count = self.len - target;
        self.dropOldest(count);
        return count;
    }

    fn dropOldest(self: *AudioQueue, count: usize) void {
        const n = @min(count, self.len);
        self.read = (self.read + n) % self.data.len;
        self.len -= n;
    }
};

test "AudioQueue drops oldest samples when full" {
    var queue = AudioQueue{};
    const samples = [_]f32{1} ** (QueueFrames + 3);

    const dropped = queue.pushSlice(&samples);

    try std.testing.expectEqual(@as(usize, 3), dropped);
    try std.testing.expectEqual(@as(usize, QueueFrames), queue.len);
}

test "AudioQueue reports missing samples as silence" {
    var queue = AudioQueue{};
    var out: [4]f32 = undefined;

    const missing = queue.popChunk(&out);

    try std.testing.expectEqual(@as(usize, out.len), missing);
    try std.testing.expectEqualSlices(f32, &[_]f32{ 0, 0, 0, 0 }, &out);
}
