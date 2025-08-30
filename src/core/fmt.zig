const std = @import("std");
const core = @import("../core.zig");
const mem = @import("./mem.zig");
const math = @import("./math.zig");
const meta = @import("./meta.zig");
const io = @import("./io.zig");
const debug = @import("./debug.zig");
const path = @import("./path.zig");
const format_float = @import("./fmt/format_float.zig");

const expect = @import("../test/expect.zig").expect;

const DebugInfo = @import("../debug_info/debug_info.zig");

pub const ByteCodeFormatter = struct {
    at: usize,
    bytes: []const u8,

    pub fn format(self: ByteCodeFormatter, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Byte code:\n", .{});
        for (0..@divFloor(self.bytes.len, 4)) |i| {
            // Arm is in little endian but we want to print in big endian
            var instr: [4]u8 = self.bytes[i * 4 ..][0..4].*;
            std.mem.reverse(u8, &instr);
            if (self.at == i) {
                try writer.writeAll(">");
            } else {
                try writer.writeAll(" ");
            }
            try writer.print("{}\n", .{std.fmt.fmtSliceHexUpper(&instr)});
        }
    }
};

pub const SourceFilepathFmt = struct {
    ctx: *core.Context,
    source_file: DebugInfo.SourceFile,

    pub fn format(self: SourceFilepathFmt, sink: *io.Sink) !void {
        try sink.writeAll(path.relativeToCwd(self.ctx.cwd, self.source_file.path));
    }
};

pub const FormatIntMode = enum {
    binary,
    octal,
    decimal,
    hex,
    ascii,
};

pub fn Int(T: type, comptime mode: FormatIntMode) type {
    return struct {
        const Self = @This();
        value: T,

        pub fn format(self: Self, sink: *io.Sink) io.Sink.WriteError!void {
            try formatInt(sink, self.value, mode);
        }
    };
}

pub fn int(value: anytype, comptime mode: FormatIntMode) Int(@TypeOf(value), mode) {
    return Int(@TypeOf(value), mode){ .value = value };
}

fn formatInt(sink: *io.Sink, value: anytype, comptime mode: FormatIntMode) io.Sink.WriteError!void {
    const sign = value < 0;
    const IntType = int_type: {
        comptime var info = @typeInfo(@TypeOf(value));

        if (info == meta.Type.comptime_int) {
            info = @typeInfo(meta.getIntType(value));
        }

        break :int_type @Type(meta.Type{
            .int = meta.Type.Int{
                .bits = info.int.bits,
                .signedness = std.builtin.Signedness.unsigned,
            },
        });
    };
    const int_value: IntType = @abs(value);
    switch (mode) {
        .binary => try writeInt(sink, int_value, sign, 2),
        .octal => try writeInt(sink, int_value, sign, 8),
        .decimal => try writeInt(sink, int_value, sign, 10),
        .hex => try writeInt(sink, int_value, sign, 16),
        .ascii => {
            if (@typeInfo(IntType).int.bits > 8) {
                @compileError("cannot print integer that is larger than 8 bits as an ASCII character");
            }
            if (sign == true) {
                @compileError("cannot print negative integer as an ASCII character");
            }
            try sink.writeByte(int_value);
        },
    }
}

pub const FormatFloatMode = enum {
    decimal,
    scientific,
};

pub fn Float(T: type) type {
    return struct {
        const Self = @This();
        value: T,
        mode: format_float.Format,
        precision: ?usize,

        pub fn format(self: Self, sink: *io.Sink) io.Sink.WriteError!void {
            try format_float.formatFloat(sink, self.value, .{ .mode = self.mode, .precision = self.precision });
        }
    };
}

pub fn floatDecimal(value: anytype, precision: ?usize) Float(@TypeOf(value)) {
    return Float(@TypeOf(value)){ .value = value, .mode = .decimal, .precision = precision };
}

pub fn floatScientific(value: anytype) Float(@TypeOf(value)) {
    return Float(@TypeOf(value)){ .value = value, .mode = .scientific, .precision = null };
}

pub fn Addr(comptime T: type) type {
    return struct {
        const Self = @This();
        value: T,

        pub fn format(self: Self, sink: *io.Sink) io.Sink.WriteError!void {
            try sink.print("0x{}", .{int(@intFromPtr(self.value), FormatIntMode.hex)});
        }
    };
}

pub fn addr(value: anytype) Addr(@TypeOf(value)) {
    const info = @typeInfo(@TypeOf(value));
    if (info != meta.Type.pointer) @compileError("address only works on pointers");
    return Addr(@TypeOf(value)){ .value = value };
}

pub fn formatFunction(sink: *io.Sink, fn_info: meta.Type.Fn) io.Sink.WriteError!void {
    try sink.writeAll("*const fn(");
    inline for (fn_info.params, 0..) |param, i| {
        if (i > 0) try sink.writeAll(", ");
        try sink.writeAll(@typeName(param));
    }
    try sink.writeAll(")");
    try sink.writeAll(@typeName(fn_info.return_type orelse void));
}

pub fn formatStruct(sink: *io.Sink, struct_info: meta.Type.Struct, value: anytype) io.Sink.WriteError!void {
    try sink.writeAll(@typeName(@TypeOf(value)));
    try sink.writeAll("{");
    inline for (struct_info.fields, 0..) |field, i| {
        if (i > 0) try sink.writeAll(", ");
        try sink.print(".{} = {}", .{ field.name, @field(value, field.name) });
    }
    try sink.writeAll("}");
}

pub fn formatUnion(sink: *io.Sink, union_info: meta.Type.Union, value: anytype) io.Sink.WriteError!void {
    try sink.writeAll(@typeName(@TypeOf(value)));
    try sink.writeAll("{ ");
    inline for (union_info.fields) |field| {
        if (mem.eql(u8, @tagName(value), field.name)) {
            try sink.print(".{} = {}", .{ @tagName(value), @field(value, field.name) });
        }
    }
    try sink.writeAll(" }");
}

pub fn digits2(digit: u8) [2]u8 {
    return switch (digit) {
        0...9 => [2]u8{ '0', '0' + digit },
        10...19 => [2]u8{ '1', '0' + digit - 10 },
        20...29 => [2]u8{ '2', '0' + digit - 20 },
        30...39 => [2]u8{ '3', '0' + digit - 30 },
        40...49 => [2]u8{ '4', '0' + digit - 40 },
        50...59 => [2]u8{ '5', '0' + digit - 50 },
        60...69 => [2]u8{ '6', '0' + digit - 60 },
        70...79 => [2]u8{ '7', '0' + digit - 70 },
        80...89 => [2]u8{ '8', '0' + digit - 80 },
        90...99 => [2]u8{ '9', '0' + digit - 90 },
        else => unreachable,
    };
}

pub fn formatPointer(sink: *io.Sink, ptr_info: meta.Type.Pointer, value: anytype) io.Sink.WriteError!void {
    switch (ptr_info.size) {
        meta.Type.Pointer.Size.slice => {
            if (ptr_info.child == u8) {
                try sink.writeAll(value);
            } else {
                try sink.writeAll("{ ");
                for (value, 0..) |elem, i| {
                    if (i > 0) {
                        try sink.writeAll(", ");
                    }
                    try sink.print("{}", .{elem});
                }
                try sink.writeAll(" }");
            }
        },
        meta.Type.Pointer.Size.one => {
            const child_info = @typeInfo(ptr_info.child);
            switch (child_info) {
                meta.Type.array => |arr_info| try formatArray(sink, arr_info, value),
                else => try sink.print("{}", .{value.*}),
            }
        },
        meta.Type.Pointer.Size.many => try formatAddress(sink, value),
        meta.Type.Pointer.Size.c => try formatAddress(sink, value),
    }
}

pub fn formatArray(sink: *io.Sink, arr_info: meta.Type.Array, value: anytype) io.Sink.WriteError!void {
    if (arr_info.child == u8) {
        try sink.writeAll(value[0..]);
        return;
    }

    try sink.writeAll(@typeName(@TypeOf(value)));
    try sink.writeAll("{ ");
    for (value, 0..) |elem, i| {
        if (i > 0) {
            try sink.writeAll(", ");
        }
        try sink.print("{}", .{elem});
    }
    try sink.writeAll(" }");
}

pub fn formatAddress(sink: *io.Sink, value: anytype) io.Sink.WriteError!void {
    try sink.writeAll(@typeName(@TypeOf(value)));
    try sink.writeAll("@");
    try sink.print("0x{x}", .{@intFromPtr(value)});
}

/// Writes an integer to the sink in the specified base
fn writeInt(sink: *io.Sink, value: anytype, sign: bool, comptime base: u8) io.Sink.WriteError!void {
    if (sign) {
        try sink.writeByte('-');
    }
    var digits_count = count: {
        if (value == 0) {
            break :count @as(u8, 1);
        }

        break :count math.log(@TypeOf(value), base, value) + 1;
    };

    while (digits_count > 0) : (digits_count -= 1) {
        // Get remainder, 123 -> 23
        const remainder = value % math.pow(u128, base, digits_count);
        // Get the digit, 23 -> 2
        const digit = remainder / math.pow(u128, base, digits_count - 1);
        const digit_str = digit_str: {
            if (digit < 10) {
                break :digit_str '0' + digit;
            }

            if (digit < 16) {
                break :digit_str 'a' + digit - 10;
            }

            // what to do about bases bigger than 16? do i just continue the alphabet ?
            unreachable;
        };
        try sink.writeByte(@truncate(digit_str));
    }
}

test {
    _ = @import("./fmt/format_float.zig");
}

test "format int" {
    var buf: [1024]u8 = undefined;
    var sink = io.Sink.discarding(&buf);

    const value_runtime: u8 = 42;
    const value_comptime = 58;

    try sink.print("Hello {} {}!", .{ int(value_runtime, FormatIntMode.ascii), int(value_comptime, FormatIntMode.ascii) });
    try expect(sink.buffered()).toEqual("Hello * :!");
    try sink.flush();

    try sink.print("Hello {} {}!", .{ int(value_runtime, FormatIntMode.binary), int(value_comptime, FormatIntMode.binary) });
    try expect(sink.buffered()).toEqual("Hello 101010 111010!");
    try sink.flush();

    try sink.print("Hello {} {}!", .{ value_runtime, value_comptime });
    try expect(sink.buffered()).toEqual("Hello 42 58!");
    try sink.flush();

    try sink.print("Hello {} {}!", .{ int(value_runtime, FormatIntMode.decimal), int(value_comptime, FormatIntMode.decimal) });
    try expect(sink.buffered()).toEqual("Hello 42 58!");
    try sink.flush();

    try sink.print("Hello {} {}!", .{ int(value_runtime, FormatIntMode.hex), int(value_comptime, FormatIntMode.hex) });
    try expect(sink.buffered()).toEqual("Hello 2a 3a!");
    try sink.flush();

    // Negative numbers
    const negative_value_runtime: i8 = -42;
    const negative_value_comptime = -58;

    try sink.print("Hello {} {}!", .{ int(negative_value_runtime, FormatIntMode.binary), int(negative_value_comptime, FormatIntMode.binary) });
    try expect(sink.buffered()).toEqual("Hello -101010 -111010!");
    try sink.flush();

    try sink.print("Hello {} {}!", .{ negative_value_runtime, negative_value_comptime });
    try expect(sink.buffered()).toEqual("Hello -42 -58!");
    try sink.flush();

    try sink.print("Hello {} {}!", .{ int(negative_value_runtime, FormatIntMode.decimal), int(negative_value_comptime, FormatIntMode.decimal) });
    try expect(sink.buffered()).toEqual("Hello -42 -58!");
    try sink.flush();

    try sink.print("Hello {} {}!", .{ int(negative_value_runtime, FormatIntMode.hex), int(negative_value_comptime, FormatIntMode.hex) });
    try expect(sink.buffered()).toEqual("Hello -2a -3a!");
    try sink.flush();
}

test "format address" {
    var buf: [1024]u8 = undefined;
    var sink = io.Sink.discarding(&buf);

    const value_runtime: u8 = 42;

    try sink.print("Hello {}", .{addr(&value_runtime)});
    try expect(sink.buffered()).startsWith("Hello 0x1");
    try sink.flush();
}

test "format struct" {
    var buf: [1024]u8 = undefined;
    const SimpleStruct = struct {
        a: u8,
        b: u16,
        c: u32,
        d: u64,
        e: u128,
        f: f32,
        g: f64,
        h: bool,
        i: void,
    };

    var sink = io.Sink.discarding(&buf);

    try sink.print("{}", .{SimpleStruct{
        .a = 1,
        .b = 2,
        .c = 3,
        .d = 4,
        .e = 5,
        .f = 6,
        .g = 7,
        .h = true,
        .i = undefined,
    }});
    try expect(sink.buffered()).toEqual("core.fmt.test.format struct.SimpleStruct{.a = 1, .b = 2, .c = 3, .d = 4, .e = 5, .f = 6, .g = 7, .h = true, .i = void}");
    try sink.flush();
}

test "format union" {
    var buf: [1024]u8 = undefined;
    var sink = io.Sink.discarding(&buf);

    const TestUnion = union(enum) {
        int: u8,
        ptr: *const [5:0]u8,
    };

    const value = TestUnion{
        .int = 123,
    };

    try sink.print("{}", .{value});
    try expect(sink.buffered()).toEqual("core.fmt.test.format union.TestUnion{ .int = 123 }");
    try sink.flush();
}

test "format pointer" {
    var buf: [1024]u8 = undefined;
    var sink = io.Sink.discarding(&buf);

    const str = "Hello";
    try sink.print("Hello {}", .{str});
    try expect(sink.buffered()).toEqual("Hello Hello");
    try sink.flush();

    const slice: []const u8 = str;
    try sink.print("Hello {}", .{slice});
    try expect(sink.buffered()).toEqual("Hello Hello");
    try sink.flush();

    try sink.print("Hello {}", .{&str});
    try expect(sink.buffered()).toEqual("Hello Hello");
    try sink.flush();

    var simple1: u64 = 123;
    try sink.print("Hello {}", .{&simple1});
    try expect(sink.buffered()).toEqual("Hello 123");
    try sink.flush();

    var struct1: struct { a: u64, b: u64 } = .{ .a = 123, .b = 456 };
    try sink.print("Hello {}", .{&struct1});
    try expect(sink.buffered()).toEqual("Hello core.fmt.test.format pointer__struct_28956{.a = 123, .b = 456}");
    try sink.flush();
}

test "format using format function" {
    var buf: [1024]u8 = undefined;
    var sink = io.Sink.discarding(&buf);

    const TestStruct = struct {
        value: u8,

        pub fn format(self: @This(), s: *io.Sink) io.Sink.WriteError!void {
            try s.print("Value: {}", .{self.value});
        }
    };
    const value = TestStruct{ .value = 0 };

    try sink.print("{}", .{value});
    try expect(sink.buffered()).toEqual("Value: 0");
    try sink.flush();
}
