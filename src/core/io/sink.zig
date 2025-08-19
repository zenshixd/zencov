const std = @import("std");
const fmt = @import("../fmt.zig");
const math = @import("../math.zig");

const Sink = @This();
pub const WriteError = error{NoSpaceLeft};

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

pub fn print(self: *Sink, comptime format: []const u8, args: anytype) WriteError!void {
    try fmt.format(self, format, args);
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
