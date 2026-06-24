pub const InputState = struct {
    a: bool = false,
    b: bool = false,
    select: bool = false,
    start: bool = false,
    up: bool = false,
    down: bool = false,
    left: bool = false,
    right: bool = false,
};

pub const StepResult = struct {
    audio: []const f32 = &.{},
};

pub const Metadata = struct {
    width: c_int,
    height: c_int,
    scale: f32,
    frame_rate: u16,
    audio_sample_rate: u32,
    max_rom_size: usize,
};
