const std = @import("std");
const mem = @import("./mem.zig");

pub fn ArrayList(comptime T: type) type {
    return struct {
        arr: std.ArrayListUnmanaged(T),
        allocator: mem.Allocator,

        pub fn init(allocator: mem.Allocator) ArrayList(T) {
            return .{
                .arr = std.ArrayListUnmanaged(T).empty,
                .allocator = allocator,
            };
        }
    };
}
