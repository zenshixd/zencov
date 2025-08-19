const std = @import("std");
const io = @import("./io.zig");

pub fn assert(cond: bool) void {
    if (!cond) {
        @branchHint(.cold);
        panic("reached an unreachable", .{});
    }
}

pub fn panic(comptime fmt: []const u8, args: anytype) noreturn {
    @branchHint(.cold);

    const size = 0x1000;
    const trunc_msg = "(msg truncated)";
    var buf: [size + trunc_msg.len]u8 = undefined;
    // a minor annoyance with this is that it will result in the NoSpaceLeft
    // error being part of the @panic stack trace (but that error should
    // only happen rarely)
    const msg = std.fmt.bufPrint(buf[0..size], fmt, args) catch |err| switch (err) {
        error.NoSpaceLeft => blk: {
            @memcpy(buf[size..], trunc_msg);
            break :blk &buf;
        },
    };
    std.debug.defaultPanic(msg, @returnAddress());
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    var stderr = io.getStderr();
    stderr.print(fmt, args) catch return;
    stderr.flush() catch return;
}
