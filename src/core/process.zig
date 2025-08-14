const std = @import("std");
const heap = @import("./heap.zig");

pub fn getCwdAlloc(allocator: heap.Allocator) error{ OutOfMemory, Unexpected, CurrentWorkingDirectoryUnlinked }![]const u8 {
    return std.process.getCwdAlloc(allocator);
}

pub fn argsAlloc(allocator: heap.Allocator) error{ OutOfMemory, Overflow }![]const []const u8 {
    return std.process.argsAlloc(allocator);
}

pub fn argsFree(allocator: heap.Allocator, args: []const []const u8) void {
    return std.process.argsFree(allocator, args);
}
