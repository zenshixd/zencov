const std = @import("std");
const heap = @import("./heap.zig");

pub fn ArrayList(comptime T: type) type {
    return struct {
        allocator: heap.Allocator,
        items: []T,
        capacity: usize,

        pub fn init(allocator: heap.Allocator) ArrayList(T) {
            return .{
                .allocator = allocator,
                .items = &[_]T{},
                .capacity = 0,
            };
        }

        pub fn initWithCapacity(allocator: heap.Allocator, capacity: usize) error{OutOfMemory}!ArrayList(T) {
            var arr = ArrayList(T).init(allocator);
            try arr.ensureUnusedCapacity(capacity);
            return arr;
        }

        pub fn deinit(self: *ArrayList(T)) void {
            self.allocator.free(self.items);
        }

        pub fn append(self: *ArrayList(T), item: T) error{OutOfMemory}!void {
            try self.ensureUnusedCapacity(1);
            self.items.len += 1;
            self.items[self.items.len - 1] = item;
        }

        pub fn appendSlice(self: *ArrayList(T), items: []const T) error{OutOfMemory}!void {
            try self.ensureUnusedCapacity(items.len);
            @memcpy(self.items[self.items.len..], items);
            self.items.len += items.len;
        }

        pub fn ensureUnusedCapacity(self: *ArrayList(T), additional: usize) error{OutOfMemory}!void {
            if (self.items.len + additional > self.capacity) {
                const new_capacity = @max(self.capacity * 2, self.items.len + additional);
                const new_items = try self.allocator.realloc(T, self.items, new_capacity);
                self.items.ptr = new_items.ptr;
                self.capacity = new_capacity;
            }
        }

        pub fn toOwnedSlice(self: *ArrayList(T)) []T {
            const new_items = self.allocator.realloc(T, self.items, self.items.len) catch unreachable; // can resizing down fail? i feel like it shouldnt ...
            self.* = ArrayList(T).init(self.allocator);
            return new_items;
        }
    };
}
