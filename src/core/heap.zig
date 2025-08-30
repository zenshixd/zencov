const std = @import("std");
const debug = @import("debug.zig");
const fmt = @import("fmt.zig");

const PageAllocator = @import("./heap/page_allocator.zig");

pub fn pageSize() usize {
    return std.heap.pageSize();
}

pub const page_size_min = std.heap.page_size_min;
pub const page_size_max = std.heap.page_size_max;

pub const page_allocator = Allocator{
    .ctx = undefined,
    .allocFn = PageAllocator.allocFn,
    .reallocFn = PageAllocator.reallocFn,
    .freeFn = PageAllocator.freeFn,
};

pub const GeneralAllocator = @import("heap/general_allocator.zig").GeneralAllocator;
pub const ArenaAllocator = @import("heap/arena_allocator.zig").ArenaAllocator;

pub const AllocatorError = error{OutOfMemory};
pub const Allocator = struct {
    ctx: *anyopaque,
    allocFn: *const fn (ctx: *anyopaque, len: usize, alignment: usize) AllocatorError![]u8,
    reallocFn: *const fn (ctx: *anyopaque, memory: []u8, alignment: usize, new_len: usize) AllocatorError![]u8,
    freeFn: *const fn (ctx: *anyopaque, memory: []u8) void,

    pub fn alloc(self: Allocator, T: type, len: usize) AllocatorError![]T {
        return self.allocAligned(T, len, @alignOf(T));
    }

    pub fn allocZ(self: Allocator, T: type, len: usize, comptime sentinel: T) AllocatorError![:sentinel]T {
        return self.allocAlignedZ(T, len, @alignOf(T), sentinel);
    }

    pub fn allocAligned(self: Allocator, T: type, len: usize, comptime alignment: usize) AllocatorError![]align(alignment) T {
        return @ptrCast(@alignCast(try self.allocFn(self.ctx, @sizeOf(T) * len, alignment)));
    }

    pub fn allocAlignedZ(self: Allocator, T: type, len: usize, comptime alignment: usize, comptime sentinel: T) AllocatorError![:sentinel]align(alignment) T {
        const bytes = try self.allocFn(self.ctx, @sizeOf(T) * len + 1, alignment);
        bytes[bytes.len] = sentinel;
        return bytes[0..bytes.len :sentinel];
    }

    pub fn realloc(self: Allocator, T: type, memory: []T, new_len: usize) AllocatorError![]T {
        return self.reallocAligned(T, memory, @alignOf(T), new_len);
    }

    pub fn reallocAligned(self: Allocator, T: type, memory: []T, comptime alignment: usize, new_len: usize) AllocatorError![]align(alignment) T {
        const new_mem = try self.reallocFn(self.ctx, @ptrCast(memory), alignment, new_len * @sizeOf(T));
        return @ptrCast(@alignCast(new_mem));
    }

    pub fn dupe(self: Allocator, T: type, memory: []const T) AllocatorError![]T {
        const new_mem = try self.alloc(T, memory.len);
        @memcpy(new_mem, memory);
        return new_mem;
    }

    pub fn dupeZ(self: Allocator, T: type, memory: []const T) AllocatorError![:0]T {
        const new_mem = try self.alloc(T, memory.len + 1);
        @memcpy(new_mem[0..memory.len], memory);
        new_mem[memory.len] = 0;
        return new_mem[0..memory.len :0];
    }

    pub fn free(self: Allocator, memory: anytype) void {
        self.freeFn(self.ctx, @ptrCast(memory));
    }

    pub fn create(self: Allocator, T: type) AllocatorError!*T {
        const ptr = try self.allocFn(self.ctx, @sizeOf(T), @alignOf(T));
        return @ptrCast(ptr);
    }

    pub fn destroy(self: Allocator, ptr: anytype) void {
        return self.freeFn(self.ctx, @ptrCast(ptr));
    }

    fn stdAlloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *Allocator = @ptrCast(@alignCast(ctx));
        _ = ret_addr;
        const ptr = self.allocFn(self.ctx, len, alignment.toByteUnits()) catch |err| switch (err) {
            error.OutOfMemory => return null,
        };
        return @ptrCast(ptr);
    }

    fn stdResize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = memory;
        _ = alignment;
        _ = new_len;
        _ = ret_addr;
        return false;
    }

    fn stdRemap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *Allocator = @ptrCast(@alignCast(ctx));
        const new_mem = self.reallocFn(self.ctx, memory, alignment.toByteUnits(), new_len) catch |err| switch (err) {
            error.OutOfMemory => return null,
        };
        return new_mem.ptr;
    }

    fn stdFree(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        _ = alignment;
        _ = ret_addr;
        const self: *Allocator = @ptrCast(@alignCast(ctx));
        return self.freeFn(self.ctx, memory);
    }

    // Std compatibility
    pub fn stdAllocator(self: *const Allocator) std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = @ptrCast(@constCast(self)),
            .vtable = &.{
                .alloc = stdAlloc,
                .resize = stdResize,
                .remap = stdRemap,
                .free = stdFree,
            },
        };
    }
};

test {
    _ = @import("heap/page_allocator.zig");
    _ = @import("heap/general_allocator.zig");
    _ = @import("heap/arena_allocator.zig");
}
