// TODO: make memory writable in bulk - no need to toggle writable for individual breakpoints
const std = @import("std");
const core = @import("core.zig");
const os = core.os;
const DebugInfo = @import("./file/debug_info.zig");

pub fn runInstrumentedAndWait(ctx: *core.Context, tracee_cmd: []const []const u8, debug_info: *const DebugInfo) void {
    std.log.debug("runInstrumentedAndWait: tracee_cmd: {s}", .{tracee_cmd[0]});
    ctx.pid = os.spawnForTracing(ctx, tracee_cmd);
    std.log.debug("runInstrumentedAndWait: ctx.pid: {d}", .{ctx.pid});
    os.setupBreakpointHandler(ctx, ctx.pid, &breakpointHandler);

    const base_vm_region = os.getMemoryRegion(ctx, ctx.pid, 0);

    var line_it = debug_info.line_info.iterator();
    while (line_it.next()) |entry| {
        std.log.debug("Setting breakpoint in {} at line {d} at address {x}", .{
            core.SourceFilepathFmt.init(debug_info.source_files[@intFromEnum(entry.value_ptr.source_file)]),
            entry.value_ptr.line,
            entry.value_ptr.*.address,
        });

        // Correct address first
        entry.value_ptr.address += @intFromPtr(base_vm_region.ptr);

        const bp = createBreakpoint(ctx, @ptrFromInt(entry.value_ptr.address));
        ctx.breakpoints.put(entry.value_ptr.address, bp) catch unreachable;
    }

    os.processResume(ctx, ctx.pid);
    os.waitForPid(ctx);
}

fn breakpointHandler(ctx: *core.Context, pc: usize) bool {
    const bp = ctx.breakpoints.getPtr(pc).?;
    removeBreakpoint(ctx, bp);
    bp.triggered = true;
    return true;
}

pub fn createBreakpoint(ctx: *core.Context, at: [*]const u8) core.Breakpoint {
    std.log.debug("createBreakpoint: pid: {}, at: {*}", .{ ctx.pid, at });

    const prev_opcode = os.readMemory(ctx, ctx.pid, core.InstructionSize, at);

    const instruction_addr = at[0..@sizeOf(core.InstructionSize)];
    os.setMemoryProtection(ctx, ctx.pid, instruction_addr, .{ .READ = 1, .WRITE = 1, .COPY = 1 });
    os.writeMemory(ctx, ctx.pid, instruction_addr, std.mem.asBytes(&core.BRK_OPCODE));
    os.setMemoryProtection(ctx, ctx.pid, instruction_addr, .{ .READ = 1, .EXEC = 1 });

    return .{
        .enabled = true,
        .addr = at,
        .original_opcode = prev_opcode,
        .triggered = false,
    };
}

pub fn removeBreakpoint(ctx: *core.Context, breakpoint: *core.Breakpoint) void {
    std.log.debug("removeBreakpoint: pid: {}, breakpoint: {}", .{ ctx.pid, breakpoint });

    const instruction_addr = breakpoint.addr[0..@sizeOf(core.InstructionSize)];
    os.setMemoryProtection(ctx, ctx.pid, instruction_addr, .{ .READ = 1, .WRITE = 1, .COPY = 1 });
    os.writeMemory(ctx, ctx.pid, instruction_addr, std.mem.asBytes(&breakpoint.original_opcode));
    os.setMemoryProtection(ctx, ctx.pid, instruction_addr, .{ .READ = 1, .EXEC = 1 });

    breakpoint.enabled = false;
}
