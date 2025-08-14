const std = @import("std");

const math = @import("../math.zig");

const Sink = @This();
pub const WriteError = error{NoSpaceLeft};
pub const Error = WriteError;

buf: [4096]u8,
pos: usize,

ctx: *anyopaque,
writeFn: *const fn (ctx: *anyopaque, bytes: []const u8) WriteError!usize,

pub fn init(ctx: *anyopaque, writeFn: *const fn (ctx: *anyopaque, bytes: []const u8) WriteError!usize) Sink {
    return .{
        .buf = undefined,
        .pos = 0,
        .ctx = ctx,
        .writeFn = writeFn,
    };
}

pub fn print(self: *const Sink, comptime format: []const u8, args: anytype) WriteError!void {
    try std.fmt.format(self.*, format, args);
    try @constCast(self).flush();
}

pub fn writeAll(self: *const Sink, bytes: []const u8) WriteError!void {
    _ = try @constCast(self).write(bytes);
    try @constCast(self).flush();
}

pub fn writeBytesNTimes(self: *const Sink, bytes: []const u8, n: usize) WriteError!void {
    for (0..n) |_| {
        _ = try @constCast(self).write(bytes);
    }
    try @constCast(self).flush();
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
        _ = try self.writeFn(self.ctx, self.buf[0..self.pos]);
        self.pos = 0;
    }

    self.buf[self.pos] = byte;
    self.pos += 1;
}

pub fn flush(self: *Sink) WriteError!void {
    if (self.pos > 0) {
        _ = try self.writeFn(self.ctx, self.buf[0..self.pos]);
        self.pos = 0;
    }
}
