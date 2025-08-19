const std = @import("std");
const debug = @import("debug.zig");
const meta = @import("meta.zig");
const math = @import("math.zig");
const expect = @import("../test/expect.zig").expect;

/// Number of bits in a byte
pub const BYTE_SIZE = 8;

/// Compares two slices of bytes for equality.
pub fn eql(T: type, a: []const T, b: []const T) bool {
    return std.mem.eql(T, a, b);
}

/// Returns most significant bit in integer
pub fn mbs(comptime T: type, a: T) math.Log2Int(T) {
    const info = @typeInfo(T);
    if (info == meta.Type.int) {
        debug.assert(a != 0);
        return @intCast(info.int.bits - @clz(a) - 1);
    }

    @compileError("mbs only works on integers, found: ");
}

fn AsBytes(comptime T: type) type {
    const info = @typeInfo(T);
    return @Type(meta.Type{
        .pointer = meta.Type.Pointer{
            .child = u8,
            .size = meta.Type.Pointer.Size.slice,
            .address_space = info.pointer.address_space,
            .is_allowzero = info.pointer.is_allowzero,
            .is_const = info.pointer.is_const,
            .is_volatile = info.pointer.is_volatile,
            .alignment = 1,
            .sentinel_ptr = null,
        },
    });
}

pub fn asBytes(a: anytype) AsBytes(@TypeOf(a)) {
    const info = @typeInfo(@TypeOf(a));
    if (info != meta.Type.pointer) @compileError("asBytes only works on pointers");
    return @as([*]u8, @constCast(@ptrCast(a)))[0..@sizeOf(info.pointer.child)];
}

/// Aligns `addr` to `alignment`, rounding down
/// `alignment` is a power of two
pub fn alignBackward(addr: usize, alignment: usize) usize {
    return addr & ~(alignment - 1);
}

/// Aligns `addr` to `alignment`, rounding up
/// `alignment` is a power of two
pub fn alignForward(addr: usize, alignment: usize) usize {
    return alignBackward(addr + alignment, alignment);
}

/// Checks if `addr` is aligned to `alignment`
/// `alignment` is a power of two
pub fn isAligned(addr: usize, alignment: usize) bool {
    return alignBackward(addr, alignment) == addr;
}

test "eql" {
    const a = [_]u8{ 1, 2, 3 };
    const b = [_]u8{ 1, 2, 3 };
    const c = [_]u8{ 1, 2, 4 };
    try expect(eql(u8, &a, &b)).toEqual(true);
    try expect(eql(u8, &a, &c)).toEqual(false);

    // const S = struct { a: u32, b: u32 };
    // const s1 = S{ .a = 1, .b = 2 };
    // const s2 = S{ .a = 1, .b = 2 };
    // const s3 = S{ .a = 1, .b = 3 };
    // try std.testing.expect(eql(S, &[_]S{s1}, &[_]S{s2}));
    // try std.testing.expect(!eql(S, &[_]S{s1}, &[_]S{s3}));
}

test "mbs" {
    const a = 1 << 10 | 1 << 8 | 1 << 4;
    const result = mbs(u32, a);

    try expect(result).toEqual(10);
}

test "alignForward" {
    try expect(alignForward(0, 1)).toEqual(1);
    try expect(alignForward(1, 2)).toEqual(2);
    try expect(alignForward(1, 4)).toEqual(4);
    try expect(alignForward(1, 8)).toEqual(8);
    try expect(alignForward(2, 8)).toEqual(8);
    try expect(alignForward(8, 8)).toEqual(16);
}

test "alignBackward" {
    try expect(alignBackward(1, 1)).toEqual(1);
    try expect(alignBackward(3, 2)).toEqual(2);
    try expect(alignBackward(5, 4)).toEqual(4);
    try expect(alignBackward(10, 8)).toEqual(8);
    try expect(alignBackward(15, 8)).toEqual(8);
    try expect(alignBackward(16, 8)).toEqual(16);
    try expect(alignBackward(17, 8)).toEqual(16);
}

test "asBytes" {
    const a: u32 = 5;
    const b: u64 = 11;
    const c: struct { a: u32, b: u64 } = .{ .a = 2, .b = 3 };
    try expect(asBytes(&a)).toEqual(&.{ 5, 0, 0, 0 });
    try expect(asBytes(&b)).toEqual(&.{ 11, 0, 0, 0, 0, 0, 0, 0 });
    try expect(asBytes(&c)).toEqual(&.{ 3, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0 });
}

test "isAligned" {
    try expect(isAligned(0, 1)).toEqual(true);
    try expect(isAligned(1, 1)).toEqual(true);
    try expect(isAligned(2, 2)).toEqual(true);
    try expect(isAligned(3, 2)).toEqual(false);
    try expect(isAligned(4, 4)).toEqual(true);
    try expect(isAligned(5, 4)).toEqual(false);
    try expect(isAligned(8, 4)).toEqual(true);
    try expect(isAligned(8, 8)).toEqual(true);
    try expect(isAligned(9, 8)).toEqual(false);
}
