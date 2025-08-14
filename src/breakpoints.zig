// TODO: make memory writable in bulk - no need to toggle writable for individual breakpoints
const std = @import("std");
const path = std.fs.path;
const core = @import("core.zig");
const fmt = @import("core/fmt.zig");
const inst = @import("instrumentation.zig");
const DebugInfo = @import("./debug_info/debug_info.zig");

pub fn runInstrumentedAndWait(ctx: *core.Context, debug_info: *const DebugInfo, tracee_cmd: []const []const u8) *inst.PID {
    std.log.debug("runInstrumentedAndWait: tracee_cmd: {s}", .{tracee_cmd[0]});
    const pid = inst.spawnForTracing(ctx, tracee_cmd);
    std.log.debug("runInstrumentedAndWait: pid: {*}", .{pid});
    pid.setupBreakpointHandler(&breakpointHandler);

    const base_vm_region = pid.getMemoryRegion(0);

    var line_it = debug_info.line_info.iterator();
    while (line_it.next()) |entry| {
        const src_file = debug_info.source_files[@intFromEnum(entry.value_ptr.source_file)];
        std.log.debug("Setting breakpoint in {} at line {d} at address {x}", .{
            fmt.SourceFilepathFmt{
                .ctx = ctx,
                .source_file = src_file,
            },
            entry.value_ptr.line,
            entry.value_ptr.*.address,
        });

        // Correct address first
        entry.value_ptr.address += @intFromPtr(base_vm_region.ptr);

        const bp = createBreakpoint(pid, @ptrFromInt(entry.value_ptr.address));
        ctx.breakpoints.put(.{ .pid = pid, .addr = @ptrFromInt(entry.value_ptr.address) }, bp) catch unreachable;
    }

    pid.processResume();
    pid.waitForPid();

    return pid;
}

fn breakpointHandler(handle: *anyopaque, pc: usize) bool {
    const pid: *inst.PID = @ptrCast(handle);
    const ctx = pid.getContext();
    const bp = ctx.breakpoints.getPtr(.{ .pid = pid, .addr = @ptrFromInt(pc) }).?;
    removeBreakpoint(pid, bp);
    bp.triggered = true;
    return true;
}

pub fn createBreakpoint(pid: *inst.PID, at: [*]const u8) inst.Breakpoint {
    std.log.debug("createBreakpoint: pid: {}, at: {*}", .{ pid, at });

    const prev_opcode = pid.readMemory(inst.InstructionSize, at);

    const instruction_addr = at[0..@sizeOf(inst.InstructionSize)];
    pid.setMemoryProtection(instruction_addr, .{ .read = 1, .write = 1 });
    pid.writeMemory(instruction_addr, std.mem.asBytes(&inst.BRK_OPCODE));
    pid.setMemoryProtection(instruction_addr, .{ .read = 1, .exec = 1 });

    return .{
        .enabled = true,
        .addr = at,
        .original_opcode = prev_opcode,
        .triggered = false,
    };
}

pub fn removeBreakpoint(pid: *inst.PID, breakpoint: *inst.Breakpoint) void {
    std.log.debug("removeBreakpoint: pid: {}, breakpoint: {}", .{ pid, breakpoint });

    const instruction_addr = breakpoint.addr[0..@sizeOf(inst.InstructionSize)];
    pid.setMemoryProtection(instruction_addr, .{ .read = 1, .write = 1 });
    pid.writeMemory(instruction_addr, std.mem.asBytes(&breakpoint.original_opcode));
    pid.setMemoryProtection(instruction_addr, .{ .read = 1, .exec = 1 });

    breakpoint.enabled = false;
}
