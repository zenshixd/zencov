const std = @import("std");
const meta = @import("../meta.zig");
const fmt = @import("../fmt.zig");
const math = @import("../math.zig");

const Sink = @This();
pub const WriteError = error{ NoSpaceLeft, WriteFailed };

buf: []u8,
pos: usize,

drainFn: *const fn (sink: *Sink, bytes: []const u8) WriteError!usize,

pub fn fixed(buf: []u8) Sink {
    return .{
        .buf = buf,
        .pos = 0,
        .drainFn = fixedDrain,
    };
}

pub fn discarding(buf: []u8) Sink {
    return .{
        .buf = buf,
        .pos = 0,
        .drainFn = discardingDrain,
    };
}

fn fixedDrain(self: *Sink, bytes: []const u8) WriteError!usize {
    _ = self;
    _ = bytes;
    return WriteError.NoSpaceLeft;
}

fn discardingDrain(self: *Sink, bytes: []const u8) WriteError!usize {
    _ = bytes;
    const len = self.pos;
    self.pos = 0;
    return len;
}

const FormatState = enum {
    text,
    placeholder,
};
pub fn print(sink: *Sink, comptime format: []const u8, args: anytype) Sink.WriteError!void {
    comptime var state: FormatState = FormatState.text;
    comptime var next_arg_idx = 0;
    comptime var cur_arg_idx = null;
    comptime var idx = 0;
    comptime var placeholder_start = 0;
    inline while (idx < format.len) : (idx += 1) {
        const c = format[idx];
        switch (c) {
            '{' => {
                if (idx + 1 < format.len and format[idx + 1] == '{') {
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
                    if (idx + 1 < format.len and format[idx + 1] == '}') {
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
                try formatValue(sink, format[placeholder_start..idx], args[arg_idx]);
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

fn formatValue(sink: *Sink, comptime format: []const u8, value: anytype) Sink.WriteError!void {
    const info = @typeInfo(@TypeOf(value));
    if (format.len == 1 and format[0] == '*') {
        if (info != meta.Type.pointer) {
            @compileError("You can only format pointers with '*' specifier");
        }
        return fmt.formatAddress(sink, format, value);
    }
    if (info == meta.Type.@"union" or info == meta.Type.@"struct" or info == meta.Type.@"enum") {
        if (@hasDecl(@TypeOf(value), "format")) {
            return try value.format(sink);
        }
    }
    switch (info) {
        meta.Type.int, meta.Type.comptime_int => try fmt.int(value, fmt.FormatIntMode.decimal).format(sink),
        meta.Type.float, meta.Type.comptime_float => try fmt.floatDecimal(value, null).format(sink),
        meta.Type.bool => try sink.writeAll(if (value) "true" else "false"),
        meta.Type.void => try sink.writeAll("void"),
        meta.Type.@"fn" => |fn_info| try fmt.formatFunction(sink, fn_info, value),
        meta.Type.@"struct" => |struct_info| try fmt.formatStruct(sink, struct_info, value),
        meta.Type.@"union" => |union_info| try fmt.formatUnion(sink, union_info, value),
        meta.Type.pointer => |ptr_info| try fmt.formatPointer(sink, ptr_info, value),
        meta.Type.array => |arr_info| try fmt.formatArray(sink, arr_info, value),
        meta.Type.optional => {
            if (value) |v| {
                try sink.print("{}", .{v});
            } else {
                try sink.writeAll("null");
            }
        },
        else => @compileError("Unsupported type: " ++ @typeName(@TypeOf(value))),
    }
}
pub fn buffered(self: *Sink) []const u8 {
    return self.buf[0..self.pos];
}

pub fn writeAll(self: *Sink, bytes: []const u8) WriteError!void {
    _ = try self.write(bytes);
}

pub fn writeBytesNTimes(self: *Sink, bytes: []const u8, n: usize) WriteError!void {
    for (0..n) |_| {
        _ = try self.write(bytes);
    }
}
pub fn writeByteNTimes(self: *Sink, byte: u8, n: usize) WriteError!void {
    for (0..n) |_| {
        _ = try self.writeByte(byte);
    }
}

pub fn write(self: *Sink, bytes: []const u8) WriteError!usize {
    var len: usize = 0;
    for (bytes) |byte| {
        _ = try self.writeByte(byte);
        len += 1;
    }

    return len;
}

pub fn writeByte(self: *Sink, byte: u8) WriteError!void {
    if (self.pos >= self.buf.len) {
        try self.flush();
    }

    self.buf[self.pos] = byte;
    self.pos += 1;
}

pub fn flush(self: *Sink) WriteError!void {
    if (self.pos > 0) {
        _ = try self.drainFn(self, self.buf[0..self.pos]);
        self.pos = 0;
    }
}
