const std = @import("std");
const debug = @import("debug.zig");

const Sink = @import("io/sink.zig");
const Source = @import("io/source.zig");

pub const StdIo = struct {
    const WriteError = error{
        NoSpaceLeft,
        DiskQuota,
        FileTooBig,
        InputOutput,
        DeviceBusy,
        InvalidArgument,
        AccessDenied,
        BrokenPipe,
        SystemResources,
        OperationAborted,
        NotOpenForWriting,
        LockViolation,
        WouldBlock,
        ConnectionResetByPeer,
        ProcessNotFound,
        NoDevice,
        Unexpected,
    };
    handle: std.fs.File,

    pub fn write(self: StdIo, bytes: []const u8) WriteError!usize {
        return self.handle.write(bytes);
    }

    pub fn sinkWrite(ctx: *anyopaque, bytes: []const u8) Sink.WriteError!usize {
        const self: *StdIo = @ptrCast(@alignCast(ctx));
        return self.write(bytes) catch |err| switch (err) {
            error.NoSpaceLeft => return error.NoSpaceLeft,
            else => |e| debug.panic("Cannot write to stdout: {}", .{e}),
        };
    }

    pub fn sink(self: *StdIo) Sink {
        return Sink.init(@ptrCast(self), StdIo.sinkWrite);
    }
};

pub fn getStdin() StdIo {
    return StdIo{ .handle = std.io.getStdIn() };
}

pub fn getStdout() StdIo {
    return StdIo{ .handle = std.io.getStdOut() };
}

pub fn getStderr() StdIo {
    return StdIo{ .handle = std.io.getStdErr() };
}
