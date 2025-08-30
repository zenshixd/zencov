const std = @import("std");
const builtin = @import("builtin");
const core = @import("../core.zig");
const heap = @import("./heap.zig");
const fmt = @import("./fmt.zig");
const io = @import("./io.zig");

pub fn assert(cond: bool) void {
    if (!cond) {
        @branchHint(.cold);
        panic("reached an unreachable", .{});
    }
}

pub fn panic(comptime format: []const u8, args: anytype) noreturn {
    @branchHint(.cold);

    const size = 0x1000;
    const trunc_msg = "(msg truncated)";
    var buf: [size + trunc_msg.len]u8 = undefined;
    // a minor annoyance with this is that it will result in the NoSpaceLeft
    // error being part of the @panic stack trace (but that error should
    // only happen rarely)
    const msg = std.fmt.bufPrint(buf[0..size], format, args) catch |err| switch (err) {
        error.NoSpaceLeft => blk: {
            @memcpy(buf[size..], trunc_msg);
            break :blk &buf;
        },
    };
    std.debug.defaultPanic(msg, @returnAddress());
}

pub fn print(comptime format: []const u8, args: anytype) void {
    var stderr = io.getStderr();
    stderr.print(format, args) catch return;
    stderr.flush() catch return;
}

pub const Stacktrace = struct {
    frame_addr: usize,
    instruction_addresses: []usize,
};

pub const StackFrame = extern struct {
    next_frame_addr: ?*StackFrame,
    return_addr: usize,
};

pub fn getStacktrace(frame_addr: usize) error{OutOfMemory}!Stacktrace {
    var addresses = try core.ArrayList(usize).initWithCapacity(heap.page_allocator, 32);
    var maybe_fa: ?*StackFrame = @ptrFromInt(frame_addr);
    while (maybe_fa) |fa| {
        try addresses.append(fa.return_addr);
        maybe_fa = fa.next_frame_addr;
    }

    return Stacktrace{
        .frame_addr = frame_addr,
        .instruction_addresses = addresses.toOwnedSlice(),
    };
}

test {
    const stacktrace = try getStacktrace(@frameAddress());
    _ = stacktrace;
}
