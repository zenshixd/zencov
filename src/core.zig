const std = @import("std");
const heap = @import("./core/heap.zig");
const process = @import("./core/process.zig");
const builtin = @import("builtin");

const inst = @import("./instrumentation.zig");
const mach = @import("./core/platform.zig").mach;

pub const Context = struct {
    gpa: heap.Allocator,
    arena: *heap.ArenaAllocator,
    cwd: []const u8,
    breakpoints: inst.BreakpointMap,

    pub fn init(gpa: heap.Allocator, arena: *heap.ArenaAllocator) Context {
        return .{
            .gpa = gpa,
            .arena = arena,
            .cwd = process.getCwdAlloc(arena.allocator()) catch unreachable,
            .breakpoints = inst.BreakpointMap.init(arena.allocator()),
        };
    }

    pub fn deinit(self: *Context) void {
        self.breakpoints.deinit();
    }
};

pub const ArrayList = @import("core/array_list.zig").ArrayList;
pub const HashMap = @import("core/hash_map.zig").HashMap;
pub const HashMapDefaultContext = @import("core/hash_map.zig").DefaultContext;
pub const EnumMask = @import("core/enum_mask.zig").EnumMask;
pub const EnumArray = std.EnumArray;

test {
    _ = @import("core/array_list.zig");
    _ = @import("core/buffer_reader.zig");
    _ = @import("core/crypto.zig");
    _ = @import("core/debug.zig");
    _ = @import("core/enum_mask.zig");
    _ = @import("core/fmt.zig");
    _ = @import("core/hash_map.zig");
    _ = @import("core/heap.zig");
    _ = @import("core/io.zig");
    _ = @import("core/logger.zig");
    _ = @import("core/math.zig");
    _ = @import("core/mem.zig");
    _ = @import("core/meta.zig");
    _ = @import("core/path.zig");
    _ = @import("core/platform.zig");
    _ = @import("core/process.zig");
    _ = @import("core/radix_tree.zig");
}
