const std = @import("std");

pub const Error = error{
    InvalidState,
    StateKindMismatch,
    UnsupportedStateVersion,
} || std.mem.Allocator.Error || std.Io.Writer.Error || std.Io.Reader.Error;

pub fn hashBytes(seed: u64, bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(seed, bytes);
}

pub fn writeValue(writer: *std.Io.Writer, value: anytype) Error!void {
    try Codec.write(writer, @TypeOf(value), value);
}

pub fn readValue(reader: *std.Io.Reader, comptime T: type) Error!T {
    return Codec.read(reader, T);
}

pub fn readBytes(reader: *std.Io.Reader, len: usize) Error![]const u8 {
    return reader.take(len) catch return Error.InvalidState;
}

pub fn expectBytes(reader: *std.Io.Reader, expected: []const u8) Error!void {
    const actual = try readBytes(reader, expected.len);
    if (!std.mem.eql(u8, actual, expected)) return Error.InvalidState;
}

pub fn done(reader: *const std.Io.Reader) Error!void {
    if (reader.bufferedLen() != 0) return Error.InvalidState;
}

const Codec = struct {
    pub fn write(writer: *std.Io.Writer, comptime T: type, value: T) Error!void {
        switch (@typeInfo(T)) {
            .bool => try writer.writeByte(@intFromBool(value)),

            .int => try writeInteger(writer, T, value),

            .float => try writeFloat(writer, T, value),

            .@"enum" => |info| {
                try write(writer, info.tag_type, @intFromEnum(value));
            },

            .array => |info| {
                for (value) |item| {
                    try write(writer, info.child, item);
                }
            },

            .@"struct" => |info| {
                inline for (info.fields) |field| {
                    try write(writer, field.type, @field(value, field.name));
                }
            },

            .optional => |info| {
                try writeOptional(writer, info.child, value);
            },

            .pointer => @compileError("pointers are not valid state fields"),

            else => @compileError("unsupported state field: " ++ @typeName(T)),
        }
    }

    pub fn read(reader: *std.Io.Reader, comptime T: type) Error!T {
        return switch (@typeInfo(T)) {
            .bool => try readBool(reader),

            .int => try readInteger(reader, T),

            .float => try readFloat(reader, T),

            .@"enum" => try readEnum(reader, T),

            .array => |info| blk: {
                var result: T = undefined;
                for (&result) |*item| {
                    item.* = try read(reader, info.child);
                }
                break :blk result;
            },

            .@"struct" => |info| blk: {
                var result: T = undefined;
                inline for (info.fields) |field| {
                    @field(result, field.name) = try read(reader, field.type);
                }
                break :blk result;
            },

            .optional => |info| try readOptional(reader, T, info.child),

            .pointer => @compileError("pointers are not valid state fields"),

            else => @compileError("unsupported state field: " ++ @typeName(T)),
        };
    }
};

fn writeInteger(writer: *std.Io.Writer, comptime T: type, value: T) Error!void {
    const Storage = IntegerStorage(T);
    try writeIntAs(writer, Storage, @intCast(value));
}

fn readInteger(reader: *std.Io.Reader, comptime T: type) Error!T {
    const Storage = IntegerStorage(T);
    const raw = try readIntAs(reader, Storage);
    return std.math.cast(T, raw) orelse Error.InvalidState;
}

fn writeFloat(writer: *std.Io.Writer, comptime T: type, value: T) Error!void {
    const Bits = FloatStorage(T);
    try writeIntAs(writer, Bits, @bitCast(value));
}

fn readFloat(reader: *std.Io.Reader, comptime T: type) Error!T {
    const Bits = FloatStorage(T);
    return @bitCast(try readIntAs(reader, Bits));
}

fn readBool(reader: *std.Io.Reader) Error!bool {
    const byte = reader.takeByte() catch return Error.InvalidState;
    if (byte > 1) return Error.InvalidState;
    return byte != 0;
}

fn readEnum(reader: *std.Io.Reader, comptime T: type) Error!T {
    const info = switch (@typeInfo(T)) {
        .@"enum" => |info| info,
        else => @compileError("expected enum type"),
    };

    const tag = try Codec.read(reader, info.tag_type);

    inline for (info.fields) |field| {
        if (tag == field.value) {
            return @as(T, @enumFromInt(tag));
        }
    }

    return Error.InvalidState;
}

fn writeOptional(
    writer: *std.Io.Writer,
    comptime Child: type,
    value: anytype,
) Error!void {
    if (isPointer(Child)) {
        if (value != null) return Error.InvalidState;
        return Codec.write(writer, bool, false);
    }

    if (value) |child| {
        try Codec.write(writer, bool, true);
        try Codec.write(writer, Child, child);
    } else {
        try Codec.write(writer, bool, false);
    }
}

fn readOptional(
    reader: *std.Io.Reader,
    comptime T: type,
    comptime Child: type,
) Error!T {
    const present = try Codec.read(reader, bool);

    if (isPointer(Child)) {
        if (present) return Error.InvalidState;
        return null;
    }

    if (!present) return null;
    return try Codec.read(reader, Child);
}

fn isPointer(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => true,
        else => false,
    };
}

fn writeIntAs(writer: *std.Io.Writer, comptime T: type, value: T) Error!void {
    var buf: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &buf, value, .little);
    try writer.writeAll(&buf);
}

fn readIntAs(reader: *std.Io.Reader, comptime T: type) Error!T {
    const bytes = try readBytes(reader, @sizeOf(T));
    return std.mem.readInt(T, bytes[0..@sizeOf(T)], .little);
}

fn IntegerStorage(comptime T: type) type {
    const info = switch (@typeInfo(T)) {
        .int => |info| info,
        else => @compileError("expected integer type"),
    };

    const signed = info.signedness == .signed;

    if (info.bits <= 8) return if (signed) i8 else u8;
    if (info.bits <= 16) return if (signed) i16 else u16;
    if (info.bits <= 32) return if (signed) i32 else u32;
    if (info.bits <= 64) return if (signed) i64 else u64;

    @compileError("unsupported integer size: " ++ @typeName(T));
}

fn FloatStorage(comptime T: type) type {
    const info = switch (@typeInfo(T)) {
        .float => |info| info,
        else => @compileError("expected float type"),
    };

    return switch (info.bits) {
        32 => u32,
        64 => u64,
        else => @compileError("unsupported float size: " ++ @typeName(T)),
    };
}
