const std = @import("std");
const heap = @import("./core/heap.zig");
const process = @import("./core/process.zig");
const builtin = @import("builtin");

const inst = @import("./instrumentation.zig");
const mach = @import("./platform.zig").mach;

pub const Context = struct {
    gpa: heap.Allocator,
    arena: heap.Allocator,
    cwd: []const u8,
    breakpoints: inst.BreakpointMap,

    pub fn init(gpa: heap.Allocator, arena: heap.Allocator) Context {
        return .{
            .gpa = gpa,
            .arena = arena,
            .cwd = process.getCwdAlloc(arena) catch unreachable,
            .breakpoints = .init(arena),
        };
    }

    pub fn deinit(self: *Context) void {
        self.breakpoints.deinit();
    }
};

pub const EnumMask = @import("core/enum_mask.zig").EnumMask;
