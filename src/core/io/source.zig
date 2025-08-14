pub const ReadError = error{EndOfStream};

const Source = @This();
buf: [4096]u8,
pos: usize,

ctx: *anyopaque,
readFn: *const fn (ctx: *anyopaque, bytes: []u8) ReadError!usize,

pub fn init(ctx: *anyopaque, readFn: *const fn (ctx: *anyopaque, bytes: []u8) ReadError!usize) Source {
    return .{
        .buf = undefined,
        .pos = 0,
        .ctx = ctx,
        .readFn = readFn,
    };
}
