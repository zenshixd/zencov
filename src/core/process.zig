const std = @import("std");
const mem = @import("./mem.zig");

pub fn getCwdAlloc(allocator: mem.Allocator) error{OutOfMemory}![]const u8 {
    return std.process.getCwdAlloc(allocator);
}

pub fn argsAlloc(allocator: mem.Allocator) error{OutOfMemory}![]const []const u8 {
    return std.process.argsAlloc(allocator);
}

pub fn argsFree(allocator: mem.Allocator, args: []const []const u8) void {
    return std.process.argsFree(allocator, args);
}
