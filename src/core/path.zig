const std = @import("std");
const heap = @import("./heap.zig");

pub const sep_str = std.fs.path.sep_str;
pub fn basename(path: []const u8) []const u8 {
    return std.fs.path.basename(path);
}

pub fn dirname(path: []const u8) ?[]const u8 {
    return std.fs.path.dirname(path);
}

pub fn relative(from: []const u8, to: []const u8) []const u8 {
    return std.fs.path.relative(from, to);
}

pub fn join(allocator: heap.Allocator, path: []const []const u8) ![]const u8 {
    return std.fs.path.join(allocator.stdAllocator(), path);
}

pub fn isAbsolute(path: []const u8) bool {
    return std.fs.path.isAbsolute(path);
}

pub fn componentIterator(path: []const u8) std.fs.path.ComponentIterator {
    return std.fs.path.componentIterator(path);
}

pub fn relativeToCwd(cwd: []const u8, path: []const u8) []const u8 {
    if (std.mem.startsWith(u8, path, cwd)) {
        return path[cwd.len..];
    }

    return path;
}
