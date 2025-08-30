const std = @import("std");
const builtin = @import("builtin");
const mem = @import("mem.zig");
const heap = @import("./heap.zig");
const posix = @import("./platform/posix.zig");

const MAX_PATH_LEN = 1024;
var cwd_buf: [MAX_PATH_LEN]u8 = undefined;

/// Returns the current working directory.
/// Uses stack buffer, so its possible path will not fit in the buffer
pub fn getCwd() error{ AccessDenied, CurrentWorkingDirectoryUnlinked, NameTooLong }![]const u8 {
    return getCwdBuf(&cwd_buf);
}

pub fn getCwdBuf(buf: []u8) error{ AccessDenied, CurrentWorkingDirectoryUnlinked, NameTooLong }![]const u8 {
    return posix.getcwd(buf) catch |err| switch (err) {
        error.BufferIsZero => unreachable,
        error.OutOfMemory => unreachable,
        error.AccessDenied => error.AccessDenied,
        error.CurrentWorkingDirectoryUnlinked => error.CurrentWorkingDirectoryUnlinked,
        error.NameTooLong => error.NameTooLong,
    };
}

/// Returns the current working directory.
/// Uses stack when possible, when path gets too long it will allocate memory
pub fn getCwdAlloc(allocator: heap.Allocator) ![]const u8 {
    const cwd = getCwd() catch |err| switch (err) {
        error.AccessDenied => return error.AccessDenied,
        error.CurrentWorkingDirectoryUnlinked => return error.CurrentWorkingDirectoryUnlinked,
        error.NameTooLong => cwd: {
            var new_cwd: []const u8 = undefined;
            var new_len: usize = MAX_PATH_LEN * 2;
            while (true) {
                const new_buf = try allocator.alloc(u8, new_len);
                errdefer allocator.free(new_buf);
                new_cwd = getCwdBuf(new_buf) catch |err2| switch (err2) {
                    error.AccessDenied => return error.AccessDenied,
                    error.CurrentWorkingDirectoryUnlinked => return error.CurrentWorkingDirectoryUnlinked,
                    error.NameTooLong => {
                        new_len *= 2;
                        continue;
                    },
                };
                break;
            }

            break :cwd new_cwd;
        },
    };
    return cwd;
}

pub const Argv = struct {
    allocator: heap.Allocator,

    pub fn init(allocator: heap.Allocator) Argv {
        return Argv{
            .allocator = allocator,
        };
    }

    /// Returns an argument at given index
    /// May do heap allocation on Windows/WASI
    pub fn get(self: Argv, index: usize) ?[]const u8 {
        _ = self;
        if (builtin.os.tag == .windows or builtin.os.tag == .wasi) {
            @compileError("process.Argv.get is not supported on Windows/WASI");
        }

        const argv = std.os.argv;
        if (index >= argv.len) {
            return null;
        }

        return mem.sliceTo(argv[index], 0);
    }
};
