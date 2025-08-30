const debug = @import("debug.zig");
const meta = @import("meta.zig");
const math = @import("math.zig");
const heap = @import("heap.zig");
const expect = @import("../test/expect.zig").expect;

/// Number of bits in a byte
pub const BYTE_SIZE = 8;

/// Compares two values for equality.
pub fn compare(T: type, a: T, b: T) bool {
    switch (@typeInfo(T)) {
        meta.Type.void,
        meta.Type.null,
        => return true,

        meta.Type.bool,
        meta.Type.int,
        meta.Type.comptime_int,
        meta.Type.float,
        meta.Type.comptime_float,
        meta.Type.@"enum",
        => return a == b,

        meta.Type.pointer => |ptr_info| {
            switch (ptr_info.size) {
                .one, .many, .c => return a == b,
                .slice => return eql(ptr_info.child, a, b),
            }
        },

        meta.Type.array => return eql(T, a, b),
        meta.Type.@"struct" => |struct_info| {
            inline for (struct_info.fields) |field| {
                if (!compare(field.type, @field(a, field.name), @field(b, field.name))) {
                    return false;
                }
            }
            return true;
        },
        meta.Type.@"union" => |union_info| {
            inline for (union_info.fields) |field| {
                if (eql(u8, field.name, @tagName(a)) and eql(u8, field.name, @tagName(b))) {
                    return compare(field.type, @field(a, field.name), @field(b, field.name));
                }
            }

            return false;
        },
        meta.Type.optional => |optional_info| {
            if (a == null and b == null) return true;
            if (a == null or b == null) return false;
            return compare(optional_info.child, a.?, b.?);
        },
        else => @compileError("compare not implemented for type " ++ @typeName(T)),
    }
}

/// Compares two slices for equality.
/// Simple types are compared directly,
/// structs and unions are compared by field
/// arrays and slices are compared by element
/// pointers are compared by address
pub fn eql(T: type, a: []const T, b: []const T) bool {
    if (a.len != b.len) return false;

    // FIXME: use SIMD here for simple types ?
    for (a, 0..) |a_elem, i| {
        if (!compare(T, a_elem, b[i])) {
            return false;
        }
    }

    return true;
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

pub fn bytesAsValue(comptime T: type, bytes: []const u8) *const T {
    return @ptrCast(@alignCast(bytes));
}

pub fn bytesToValue(comptime T: type, bytes: []const u8) T {
    return bytesAsValue(T, bytes).*;
}

pub fn concat(allocator: heap.Allocator, T: type, slices: []const []const T) error{OutOfMemory}![]T {
    var total_len: usize = 0;
    for (slices) |slice| {
        total_len += slice.len;
    }

    var buf = try allocator.alloc(T, total_len);
    var partial_len: usize = 0;
    for (slices) |slice| {
        @memcpy(buf[partial_len..][0..slice.len], slice);
        partial_len += slice.len;
    }

    return buf;
}

pub fn sliceTo(slice: anytype, comptime sentinel: meta.Elem(@TypeOf(slice))) meta.SliceTo(@TypeOf(slice), sentinel) {
    var len: usize = 0;
    // FIXME: use SIMD here ???
    while (true) : (len += 1) {
        if (slice[len] == sentinel) {
            break;
        }
    }

    const Result = meta.SliceTo(@TypeOf(slice), sentinel);
    const result_info = @typeInfo(Result);
    if (result_info.pointer.sentinel()) |s| {
        return slice[0..len :s];
    }

    return slice[0..len];
}

pub fn indexOf(T: type, slice: []const T, needle: T) ?usize {
    // FIXME: use SIMD here ???
    for (slice, 0..) |item, i| {
        if (compare(T, item, needle)) {
            return i;
        }
    }

    return null;
}

pub fn startsWith(T: type, slice: []const T, prefix: []const T) bool {
    if (slice.len < prefix.len) {
        return false;
    }

    return eql(T, slice[0..prefix.len], prefix);
}

test "bytesToValue" {
    const a = bytesToValue(u32, &.{ 1, 2, 3, 4 });
    try expect(a).toEqual(0x04030201);

    const TestStruct = struct { a: u32, b: u32 };
    const b = bytesToValue(TestStruct, &.{ 1, 2, 3, 4 });
    try expect(b).toEqual(TestStruct{ .a = 0x04030201, .b = 0 });
}

test "eql" {
    const a = [_]u8{ 1, 2, 3 };
    const b = [_]u8{ 1, 2, 3 };
    const c = [_]u8{ 1, 2, 4 };

    const result1 = eql(u8, &a, &b);
    try expect(result1).toEqual(true);

    const result2 = eql(u8, &a, &c);
    try expect(result2).toEqual(false);

    const S = struct { a: u32, b: u32 };
    const s1 = S{ .a = 1, .b = 2 };
    const s2 = S{ .a = 1, .b = 2 };
    const s3 = S{ .a = 1, .b = 3 };

    const result3 = eql(S, &[_]S{s1}, &[_]S{s2});
    try expect(result3).toEqual(true);

    const result4 = eql(S, &[_]S{s1}, &[_]S{s3});
    try expect(result4).toEqual(false);
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

test "concat" {
    const a = "abc";
    const b = "def";

    const result = try concat(heap.page_allocator, u8, &[_][]const u8{ a, b });
    defer heap.page_allocator.free(result);

    try expect(result).toEqualBytes("abcdef");
}

test "sliceTo" {
    const a = [_]u8{ 1, 2, 3, 0, 4, 5, 6, 7 };
    const result1 = sliceTo(&a, 0);

    try expect(result1).toEqual(&[_]u8{ 1, 2, 3, 0 });

    const result2 = sliceTo(&a, 9);
    try expect(result2).toEqual(&a);
}

test "indexOf" {
    const a = "abcde";
    try expect(indexOf(u8, a, 'x')).toEqual(null);
    try expect(indexOf(u8, a, 'a')).toEqual(0);
    try expect(indexOf(u8, a, 'd')).toEqual(3);
}

test "startsWith" {
    const a = "abcde";
    try expect(startsWith(u8, a, "ab")).toEqual(true);
    try expect(startsWith(u8, a, "bc")).toEqual(false);
}
