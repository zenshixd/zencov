const std = @import("std");

const DebugAllocator = std.heap.DebugAllocator(.{});

pub const Allocator = std.mem.Allocator;
pub const AllocatorError = error{OutOfMemory};

pub const GeneralAllocator = struct {
    debug_allocator: DebugAllocator,

    pub fn init() GeneralAllocator {
        return .{
            .debug_allocator = DebugAllocator.init,
        };
    }

    pub fn deinit(self: *GeneralAllocator) void {
        _ = self.debug_allocator.deinit();
    }

    pub fn allocator(self: *GeneralAllocator) Allocator {
        return self.debug_allocator.allocator();
    }
};

pub const ArenaAllocator = struct {
    arena_allocator: std.heap.ArenaAllocator,

    pub fn init() ArenaAllocator {
        return .{
            .arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator),
        };
    }

    pub fn deinit(self: *ArenaAllocator) void {
        self.arena_allocator.deinit();
    }

    pub fn reset(self: *ArenaAllocator, comptime reset_mode: std.heap.ArenaAllocator.ResetMode) bool {
        return self.arena_allocator.reset(reset_mode);
    }

    pub fn allocator(self: *ArenaAllocator) Allocator {
        return self.arena_allocator.allocator();
    }
};
