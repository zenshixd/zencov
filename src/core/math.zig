const std = @import("std");
const debug = @import("debug.zig");
const meta = @import("meta.zig");
const mem = @import("mem.zig");
const expect = @import("../test/expect.zig").expect;

pub fn min(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return if (a < b) a else b;
}

pub fn max(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return if (a > b) a else b;
}

/// Returns an unsigned int type that can hold the number of bits in T - 1.
/// Suitable for 0-based bit indices of T.
pub fn Log2Int(comptime T: type) type {
    // comptime ceil log2
    if (T == comptime_int) return comptime_int;
    const bits: u16 = @typeInfo(T).int.bits;
    const log2_bits = 16 - @clz(bits - 1);
    return @Type(meta.Type{
        .int = meta.Type.Int{
            .signedness = .unsigned,
            .bits = log2_bits,
        },
    });
}

pub fn log2(x: anytype) Log2Int(@TypeOf(x)) {
    const info = @typeInfo(@TypeOf(x));
    switch (info) {
        .comptime_float, .float => return @log2(x),
        else => {
            switch (info) {
                .int => |int_info| switch (int_info.signedness) {
                    .signed => @compileError("log2 not implemented for signed integers"),
                    .unsigned => return mem.mbs(@TypeOf(x), x),
                },
                else => @compileError("log2 not implemented for " ++ @typeName(@TypeOf(x))),
            }
        },
    }
}

pub fn log10(x: anytype) @TypeOf(x) {
    return std.math.log10(x);
}

pub fn log(T: type, x: T, base: T) T {
    return std.math.log(T, x, base);
}

pub fn isPowerOfTwo(x: anytype) bool {
    debug.assert(x != 0);
    return x & (x - 1) == 0;
}

pub fn pow(T: type, base: T, exp: T) T {
    var result: T = 1;
    var i: T = 0;
    while (i < exp) : (i += 1) {
        result *= base;
    }
    return result;
}

pub fn maxInt(comptime T: type) T {
    const bits = @typeInfo(T).int.bits;
    var result: T = 0;
    inline for (0..bits) |i| {
        result |= @as(T, 1) << i;
    }
    return result;
}

pub fn floatExponentBits(comptime T: type) comptime_int {
    return switch (T) {
        f16 => 5,
        f32 => 8,
        f64 => 11,
        f80 => 15,
        f128 => 15,
        else => @compileError("unsupported float type"),
    };
}

pub fn floatFractionalBits(comptime T: type) comptime_int {
    return switch (T) {
        f16 => 10,
        f32 => 23,
        f64 => 52,
        f80 => 63,
        f128 => 112,
        else => @compileError("unsupported float type"),
    };
}

pub fn floatMantissaBits(comptime T: type) comptime_int {
    return switch (T) {
        f16 => 10,
        f32 => 23,
        f64 => 52,
        f80 => 64,
        f128 => 112,
        else => @compileError("unsupported float type"),
    };
}

/// Creates a raw "1.0" mantissa for floating point type T. Used to dedupe f80 logic.
inline fn mantissaOne(comptime T: type) comptime_int {
    return if (@typeInfo(T).float.bits == 80) 1 << floatFractionalBits(T) else 0;
}

/// Returns the minimum exponent that can represent
/// a normalised value in floating point type T.
pub inline fn floatExponentMin(comptime T: type) comptime_int {
    return -floatExponentMax(T) + 1;
}

/// Returns the maximum exponent that can represent
/// a normalised value in floating point type T.
pub inline fn floatExponentMax(comptime T: type) comptime_int {
    return (1 << (floatExponentBits(T) - 1)) - 1;
}

/// Creates floating point type T from an unbiased exponent and raw mantissa.
inline fn reconstructFloat(comptime T: type, comptime exponent: comptime_int, comptime mantissa: comptime_int) T {
    const TBits = @Type(.{ .int = .{ .signedness = .unsigned, .bits = @bitSizeOf(T) } });
    const biased_exponent = @as(TBits, exponent + floatExponentMax(T));
    return @as(T, @bitCast((biased_exponent << floatMantissaBits(T)) | @as(TBits, mantissa)));
}

/// Returns canonical infinity representation for floating point type T.
pub fn inf(comptime T: type) T {
    return reconstructFloat(T, floatExponentMax(T) + 1, mantissaOne(T));
}

/// Returns the canonical quiet NaN representation for floating point type T.
pub inline fn nan(comptime T: type) T {
    return reconstructFloat(
        T,
        floatExponentMax(T) + 1,
        mantissaOne(T) | 1 << (floatFractionalBits(T) - 1),
    );
}

pub fn isNan(x: anytype) bool {
    return x != x;
}

pub fn isInf(x: anytype) bool {
    const T = @TypeOf(x);
    const TBits = std.meta.Int(.unsigned, @typeInfo(T).float.bits);
    const remove_sign = ~@as(TBits, 0) >> 1;
    return @as(TBits, @bitCast(x)) & remove_sign == @as(TBits, @bitCast(inf(T)));
}

test "maxInt" {
    try expect(maxInt(u8)).toEqual(255);
    try expect(maxInt(u16)).toEqual(65535);
    try expect(maxInt(u32)).toEqual(4294967295);
    try expect(maxInt(u64)).toEqual(18446744073709551615);
}
