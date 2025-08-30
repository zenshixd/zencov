const std = @import("std");
const debug = @import("debug.zig");

pub const Sink = @import("io/sink.zig");
pub const Source = @import("io/source.zig");

pub const StdIo = struct {
    var buf: [4096]u8 = undefined;
    interface: Sink = Sink{
        .buf = &buf,
        .pos = 0,
        .drainFn = sinkDrain,
    },
    handle: std.fs.File,

    pub fn writeAll(self: *StdIo, bytes: []const u8) Sink.WriteError!void {
        return self.interface.writeAll(bytes);
    }

    pub fn print(self: *StdIo, comptime fmt: []const u8, args: anytype) Sink.WriteError!void {
        return self.interface.print(fmt, args);
    }

    pub fn flush(self: *StdIo) Sink.WriteError!void {
        return self.interface.flush();
    }

    pub fn sinkDrain(s: *Sink, bytes: []const u8) Sink.WriteError!usize {
        const self: *StdIo = @fieldParentPtr("interface", s);
        return self.handle.write(bytes) catch |err| switch (err) {
            error.NoSpaceLeft => return error.NoSpaceLeft,
            else => |e| debug.panic("Cannot write to stdio: {}", .{e}),
        };
    }

    pub fn sink(self: *StdIo) *Sink {
        return &self.interface;
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

test {
    _ = @import("io/source.zig");
    _ = @import("io/sink.zig");
}
