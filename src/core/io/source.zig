const core = @import("../../core.zig");
const debug = @import("../debug.zig");
const heap = @import("../heap.zig");
const expect = @import("../../test/expect.zig").expect;

pub const ReadError = error{ EndOfStream, ReadFailed };

const Source = @This();

pub const VTable = struct {
    read: *const fn (source: *Source, bytes: []const u8) ReadError!usize,
};

vtable: *const VTable,

buffer: []u8,
pos: usize,
end: usize,

pub fn fixed(buffer: []const u8) Source {
    return Source{
        .vtable = &.{
            .read = endingRead,
        },
        // @constCast is fine because all vtable methods return EndOfStream
        .buffer = @constCast(buffer),
        .pos = 0,
        .end = buffer.len,
    };
}

fn endingRead(source: *Source, bytes: []const u8) ReadError!usize {
    _ = source;
    _ = bytes;
    return error.EndOfStream;
}

pub fn buffered(self: *Source) []const u8 {
    return self.buffer[self.pos..self.end];
}

pub fn read(self: *Source, output: []u8) ReadError!usize {
    const copy_len = @min(output.len, self.buffer.len - self.pos);
    @memcpy(output[0..copy_len], self.buffer[self.pos..][0..copy_len]);
    self.pos += copy_len;
    if (copy_len == output.len) {
        // Output is full
        return copy_len;
    }

    const read_len = self.vtable.read(self, output[copy_len..]) catch |err| switch (err) {
        error.EndOfStream => {
            if (copy_len == 0) {
                return error.EndOfStream;
            }

            return copy_len;
        },
        error.ReadFailed => return error.ReadFailed,
    };

    return copy_len + read_len;
}

pub fn readAlloc(source: *Source, allocator: heap.Allocator, len: usize) (error{OutOfMemory} || ReadError)![]u8 {
    const buf = try allocator.alloc(u8, len);
    errdefer allocator.free(buf);

    const read_len = try source.read(buf);
    if (read_len != len) {
        return error.EndOfStream;
    }

    return buf;
}

test "source.fixed" {
    var source = Source.fixed("Hello, World!");
    var buf: [10]u8 = undefined;

    _ = try source.read(&buf);
    try expect(buf).toEqualBytes("Hello, Wor");

    source.pos = 0;
    try expect(source.buffered()).toEqualBytes("Hello, World!");

    const buf2 = try source.readAlloc(heap.page_allocator, 10);
    defer heap.page_allocator.free(buf2);
    try expect(buf2).toEqualBytes("Hello, Wor");
}
