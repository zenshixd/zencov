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

    pub fn format(self: SourceFilepathFmt, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.writeAll(path.relativeToCwd(self.ctx.cwd, self.source_file.path));
    }
};

const FormatState = enum {
    text,
    placeholder,
};

const FormatSpecifier = enum {
    none,
    number,
    character,
    pointer,
    hex,
};

pub fn format(sink: *io.Sink, comptime fmt: []const u8, args: anytype) io.Sink.WriteError!void {
    comptime var state: FormatState = FormatState.text;
    comptime var next_arg_idx = 0;
    comptime var cur_arg_idx = null;
    comptime var idx = 0;
    comptime var placeholder_start = 0;
    inline while (idx < fmt.len) : (idx += 1) {
        const c = fmt[idx];
        switch (c) {
            '{' => {
                if (idx + 1 < fmt.len and fmt[idx + 1] == '{') {
                    try sink.writeByte('{');
                    idx += 1;
                    continue;
                }

                if (state != FormatState.text) {
                    @compileError("Nested '{' in format string");
                }

                state = FormatState.placeholder;
                placeholder_start = idx + 1;
            },
            '}' => {
                if (state == FormatState.text) {
                    if (idx + 1 < fmt.len and fmt[idx + 1] == '}') {
                        try sink.writeByte('}');
                        idx += 1;
                        continue;
                    }

                    @compileError("Encountered '}' without opening bracket");
                }

                const arg_idx = cur_arg_idx orelse next_arg_idx;
                next_arg_idx += 1;
                if (args.len <= arg_idx) {
                    @compileError("Encountered unused placeholder");
                }
                try formatValue(sink, fmt[placeholder_start..idx], args[arg_idx]);
                state = FormatState.text;
                cur_arg_idx = null;
            },
            '0'...'9' => {
                if (state == FormatState.placeholder) {
                    if (placeholder_start == idx) {
                        cur_arg_idx = c - '0';
                        placeholder_start += 1;
                    }
                } else {
                    try sink.writeByte(c);
                }
            },
            else => {
                if (state == FormatState.text) {
                    try sink.writeByte(c);
                }
            },
        }
    }

    if (state != FormatState.text) {
        @compileError("Missing '}' in format string");
    }
}

fn formatValue(sink: *io.Sink, comptime fmt: []const u8, value: anytype) io.Sink.WriteError!void {
    const info = @typeInfo(@TypeOf(value));
    if (fmt.len == 1 and fmt[0] == '*') {
        if (info != meta.Type.pointer) {
            @compileError("You can only format pointers with '*' specifier");
        }
        return formatAddress(sink, fmt, value);
    }
    if (info == meta.Type.@"union" or info == meta.Type.@"struct" or info == meta.Type.@"enum") {
        if (@hasDecl(@TypeOf(value), "format")) {
            return try value.format(sink);
        }
    }
    switch (info) {
        meta.Type.int, meta.Type.comptime_int => try formatInt(sink, fmt, value),
        meta.Type.float, meta.Type.comptime_float => try formatFloat(sink, fmt, value),
        meta.Type.bool => try sink.writeAll(if (value) "true" else "false"),
        meta.Type.void => try sink.writeAll("void"),
        meta.Type.@"fn" => |fn_info| try formatFunction(sink, fmt, fn_info, value),
        meta.Type.@"struct" => |struct_info| try formatStruct(sink, fmt, struct_info, value),
        meta.Type.@"union" => |union_info| try formatUnion(sink, fmt, union_info, value),
        meta.Type.pointer => |ptr_info| try formatPointer(sink, fmt, ptr_info, value),
        meta.Type.array => |arr_info| try formatArray(sink, fmt, arr_info, value),
        else => @compileError("Unsupported type: " ++ @typeName(@TypeOf(value))),
    }
}

fn formatInt(sink: *io.Sink, comptime fmt: []const u8, value: anytype) io.Sink.WriteError!void {
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
    if (comptime fmt.len == 0 or mem.eql(u8, fmt, "d")) {
        try writeInt(sink, int_value, sign, 10);
    } else if (comptime mem.eql(u8, fmt, "b")) {
        try writeInt(sink, int_value, sign, 2);
    } else if (comptime mem.eql(u8, fmt, "x")) {
        try writeInt(sink, int_value, sign, 16);
    } else if (comptime mem.eql(u8, fmt, "c")) {
        if (@typeInfo(IntType).int.bits > 8) {
            @compileError("cannot print integer that is larger than 8 bits as an ASCII character");
        }
        if (sign == true) {
            @compileError("cannot print negative integer as an ASCII character");
        }
        try sink.writeByte(int_value);
    } else {
        invalidFmtError(fmt, value);
    }
}

fn formatFloat(sink: *io.Sink, comptime fmt: []const u8, value: anytype) io.Sink.WriteError!void {
    _ = fmt;
    try format_float.formatFloat(sink, value, .{ .mode = .decimal, .precision = null });
}

fn formatFunction(sink: *io.Sink, comptime fmt: []const u8, fn_info: meta.Type.Fn, value: anytype) io.Sink.WriteError!void {
    if (fmt.len > 0) invalidFmtError(fmt, value);

    try sink.writeAll("*const fn(");
    inline for (fn_info.params, 0..) |param, i| {
        if (i > 0) try sink.writeAll(", ");
        try sink.writeAll(@typeName(param));
    }
    try sink.writeAll(")");
    try sink.writeAll(@typeName(fn_info.return_type orelse void));
}

fn formatStruct(sink: *io.Sink, comptime fmt: []const u8, struct_info: meta.Type.Struct, value: anytype) io.Sink.WriteError!void {
    if (fmt.len > 0) invalidFmtError(fmt, value);

    try sink.writeAll(@typeName(@TypeOf(value)));
    try sink.writeAll("{");
    inline for (struct_info.fields, 0..) |field, i| {
        if (i > 0) try sink.writeAll(", ");
        try sink.writeAll(".");
        try sink.writeAll(field.name);
        try sink.writeAll(" = ");
        try formatValue(sink, "", @field(value, field.name));
    }
    try sink.writeAll("}");
}

fn formatUnion(sink: *io.Sink, comptime fmt: []const u8, union_info: meta.Type.Union, value: anytype) io.Sink.WriteError!void {
    _ = fmt;
    try sink.writeAll(@typeName(@TypeOf(value)));
    try sink.writeAll("{ ");
    inline for (union_info.fields) |field| {
        if (mem.eql(u8, @tagName(value), field.name)) {
            try sink.writeByte('.');
            try sink.writeAll(@tagName(value));
            try sink.writeAll(" = ");
            try formatValue(sink, "", @field(value, field.name));
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

fn formatPointer(sink: *io.Sink, comptime fmt: []const u8, ptr_info: meta.Type.Pointer, value: anytype) io.Sink.WriteError!void {
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
                    try formatValue(sink, "", elem);
                }
                try sink.writeAll(" }");
            }
        },
        meta.Type.Pointer.Size.one => try formatValue(sink, fmt, value.*),
        meta.Type.Pointer.Size.many => try formatAddress(sink, fmt, value),
        meta.Type.Pointer.Size.c => try formatAddress(sink, fmt, value),
    }
}

fn formatArray(sink: *io.Sink, comptime fmt: []const u8, arr_info: meta.Type.Array, value: anytype) io.Sink.WriteError!void {
    _ = fmt;
    if (arr_info.child == u8) {
        try sink.writeAll(&value);
        return;
    }

    try sink.writeAll(@typeName(@TypeOf(value)));
    try sink.writeAll("{ ");
    for (value, 0..) |elem, i| {
        if (i > 0) {
            try sink.writeAll(", ");
        }
        try formatValue(sink, "", elem);
    }
    try sink.writeAll(" }");
}

fn formatAddress(sink: *io.Sink, comptime fmt: []const u8, value: anytype) io.Sink.WriteError!void {
    _ = fmt;
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

fn invalidFmtError(comptime fmt: []const u8, value: anytype) void {
    @compileError("invalid format string '" ++ fmt ++ "' for type '" ++ @typeName(@TypeOf(value)) ++ "'");
}

test {
    _ = @import("./fmt/format_float.zig");
}

test "format int" {
    var buf: [1024]u8 = undefined;
    var sink = io.Sink.discarding(&buf);

    const value_runtime: u8 = 42;
    const value_comptime = 58;

    try format(&sink, "Hello {c} {c}!", .{ value_runtime, value_comptime });
    try expect(sink.buffered()).toEqual("Hello * :!");
    try sink.flush();

    try format(&sink, "Hello {b} {b}!", .{ value_runtime, value_comptime });
    try expect(sink.buffered()).toEqual("Hello 101010 111010!");
    try sink.flush();

    try format(&sink, "Hello {} {}!", .{ value_runtime, value_comptime });
    try expect(sink.buffered()).toEqual("Hello 42 58!");
    try sink.flush();

    try format(&sink, "Hello {d} {d}!", .{ value_runtime, value_comptime });
    try expect(sink.buffered()).toEqual("Hello 42 58!");
    try sink.flush();

    try format(&sink, "Hello {x} {x}!", .{ value_runtime, value_comptime });
    try expect(sink.buffered()).toEqual("Hello 2a 3a!");
    try sink.flush();

    // Negative numbers
    const negative_value_runtime: i8 = -42;
    const negative_value_comptime = -58;

    try format(&sink, "Hello {b} {b}!", .{ negative_value_runtime, negative_value_comptime });
    try expect(sink.buffered()).toEqual("Hello -101010 -111010!");
    try sink.flush();

    try format(&sink, "Hello {} {}!", .{ negative_value_runtime, negative_value_comptime });
    try expect(sink.buffered()).toEqual("Hello -42 -58!");
    try sink.flush();

    try format(&sink, "Hello {d} {d}!", .{ negative_value_runtime, negative_value_comptime });
    try expect(sink.buffered()).toEqual("Hello -42 -58!");
    try sink.flush();

    try format(&sink, "Hello {x} {x}!", .{ negative_value_runtime, negative_value_comptime });
    try expect(sink.buffered()).toEqual("Hello -2a -3a!");
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

    try format(&sink, "{}", .{SimpleStruct{
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

    try format(&sink, "{}", .{value});
    try expect(sink.buffered()).toEqual("core.fmt.test.format union.TestUnion{ .int = 123 }");
    try sink.flush();
}

test "format pointer" {
    var buf: [1024]u8 = undefined;
    var sink = io.Sink.discarding(&buf);

    const str = "Hello";
    try format(&sink, "Hello {}", .{str});
    try expect(sink.buffered()).toEqual("Hello Hello");
    try sink.flush();

    const slice: []const u8 = str;
    try format(&sink, "Hello {}", .{slice});
    try expect(sink.buffered()).toEqual("Hello Hello");
    try sink.flush();

    try format(&sink, "Hello {}", .{&str});
    try expect(sink.buffered()).toEqual("Hello Hello");
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

    try format(&sink, "{}", .{value});
    try expect(sink.buffered()).toEqual("Value: 0");
    try sink.flush();
}
