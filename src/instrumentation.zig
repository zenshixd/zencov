const std = @import("std");
const builtin = @import("builtin");
const core = @import("core.zig");

pub const base = @import("instrumentation/base.zig");

pub const internal = switch (builtin.os.tag) {
    // .windows => @import("instrumentation/win32.zig"),
    // .linux => @import("instrumentation/linux.zig"),
    .macos => @import("instrumentation/macos.zig"),
    else => @compileError("Unsupported OS"),
};

pub fn spawnForTracing(ctx: *core.Context, args: []const []const u8) *PID {
    return @ptrCast(internal.spawnForTracing(ctx, args));
}

pub const PID = opaque {
    pub fn getContext(pid: *PID) *core.Context {
        const internal_pid: *internal.PID = @ptrCast(@alignCast(pid));
        return internal_pid.getContext();
    }

    pub fn processResume(pid: *PID) void {
        const internal_pid: *internal.PID = @ptrCast(@alignCast(pid));
        return internal_pid.processResume();
    }

    pub fn processSuspend(pid: *PID) void {
        const internal_pid: *internal.PID = @ptrCast(@alignCast(pid));
        return internal_pid.processSuspend();
    }

    pub fn getMemoryRegion(pid: *PID, address: usize) []const u8 {
        const internal_pid: *internal.PID = @ptrCast(@alignCast(pid));
        return internal_pid.getMemoryRegion(address);
    }

    pub fn setupBreakpointHandler(pid: *PID, handler: *const fn (pid: *anyopaque, pc: usize) bool) void {
        const internal_pid: *internal.PID = @ptrCast(@alignCast(pid));
        return internal_pid.setupBreakpointHandler(handler);
    }

    pub fn setMemoryProtection(pid: *PID, addr: []const u8, prot: core.EnumMask(MemoryProtection)) void {
        const internal_pid: *internal.PID = @ptrCast(@alignCast(pid));
        return internal_pid.setMemoryProtection(addr, prot);
    }

    pub fn readMemory(pid: *PID, T: type, at: [*]const u8) T {
        const internal_pid: *internal.PID = @ptrCast(@alignCast(pid));
        return internal_pid.readMemory(T, at);
    }

    pub fn writeMemory(pid: *PID, addr: []const u8, data: []const u8) void {
        const internal_pid: *internal.PID = @ptrCast(@alignCast(pid));
        return internal_pid.writeMemory(addr, data);
    }

    pub fn waitForPid(pid: *PID) void {
        const internal_pid: *internal.PID = @ptrCast(@alignCast(pid));
        return internal_pid.waitForPid();
    }
};

pub const BreakpointKey = struct {
    pid: *PID,
    addr: [*]const u8,
};
pub const Breakpoint = struct {
    enabled: bool,
    addr: [*]const u8,
    original_opcode: base.InstructionSize,
    triggered: bool,
};
pub const BreakpointMap = std.AutoArrayHashMap(BreakpointKey, Breakpoint);
pub const BRK_OPCODE = base.BRK_OPCODE;
pub const InstructionSize = base.InstructionSize;
pub const MemoryProtection = base.MemoryProtection;
