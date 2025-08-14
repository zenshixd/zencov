const std = @import("std");

pub fn eql(T: type, a: []const T, b: []const T) bool {
    return std.mem.eql(T, a, b);
}
