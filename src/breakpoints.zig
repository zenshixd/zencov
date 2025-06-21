// TODO: make memory writable in bulk - no need to toggle writable for individual breakpoints
const std = @import("std");
const core = @import("core.zig");
const os = core.os;
const DebugInfo = @import("./file/debug_info.zig");

pub fn runInstrumentedAndWait(tracee_cmd: []const []const u8, debug_info: *const DebugInfo) void {
    std.log.debug("runInstrumentedAndWait: tracee_cmd: {s}", .{tracee_cmd[0]});
    core.pid = os.spawnForTracing(tracee_cmd);
    std.log.debug("runInstrumentedAndWait: core.pid: {d}", .{core.pid});
    os.setupBreakpointHandler(core.pid, &breakpointHandler);

    const base_vm_region = os.getMemoryRegion(core.pid, 0);

    var line_it = debug_info.line_info.iterator();
    while (line_it.next()) |entry| {
        // Correct address first
        entry.value_ptr.address += @intFromPtr(base_vm_region.ptr);

        std.log.debug("Setting breakpoint in {} at line {d}", .{ core.SourceFilepathFmt.init(debug_info.source_files[@intFromEnum(entry.value_ptr.source_file)]), entry.value_ptr.line });

        const bp = createBreakpoint(@ptrFromInt(entry.value_ptr.address));
        core.breakpoints.put(entry.value_ptr.address, bp) catch unreachable;
    }

    os.processResume(core.pid);
    os.waitForPid(core.pid);
}

fn breakpointHandler(pc: usize) bool {
    const bp = core.breakpoints.getPtr(pc).?;
    removeBreakpoint(bp);
    bp.triggered = true;
    return true;
}

pub fn createBreakpoint(at: [*]const u8) core.Breakpoint {
    std.log.debug("createBreakpoint: pid: {}, at: {*}", .{ core.pid, at });

    const prev_opcode = os.readMemory(core.pid, core.InstructionSize, at);

    const instruction_addr = at[0..@sizeOf(core.InstructionSize)];
    os.setMemoryProtection(core.pid, instruction_addr, .{ .READ = 1, .WRITE = 1, .COPY = 1 });
    os.writeMemory(core.pid, instruction_addr, std.mem.asBytes(&core.BRK_OPCODE));
    os.setMemoryProtection(core.pid, instruction_addr, .{ .READ = 1, .EXEC = 1 });

    return .{
        .enabled = true,
        .addr = at,
        .original_opcode = prev_opcode,
        .triggered = false,
    };
}

pub fn removeBreakpoint(breakpoint: *core.Breakpoint) void {
    std.log.debug("removeBreakpoint: pid: {}, breakpoint: {}", .{ core.pid, breakpoint });

    const instruction_addr = breakpoint.addr[0..@sizeOf(core.InstructionSize)];
    os.setMemoryProtection(core.pid, instruction_addr, .{ .READ = 1, .WRITE = 1, .COPY = 1 });
    os.writeMemory(core.pid, instruction_addr, std.mem.asBytes(&breakpoint.original_opcode));
    os.setMemoryProtection(core.pid, instruction_addr, .{ .READ = 1, .EXEC = 1 });

    breakpoint.enabled = false;
}
