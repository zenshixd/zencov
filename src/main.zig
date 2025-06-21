const std = @import("std");
const assert = std.debug.assert;
const panic = std.debug.panic;
const builtin = @import("builtin");

const DebugInfo = @import("./file/debug_info.zig");
const core = @import("core.zig");
const os = core.os;
const platform = @import("platform.zig");
const report = @import("report.zig");

pub fn main() !void {
    defer {
        // In Release mode this will get cleaned up by OS anyway
        if (builtin.mode == .Debug) {
            core.arena_allocator.deinit();
        }

        // Check for leaks
        _ = core.debug_allocator.deinit();
    }

    const tracee = "zig-out/bin/tracee";

    core.pid = os.spawnForTracing(&.{tracee});
    os.setupBreakpointHandler(core.pid, &breakpointHandler);

    const base_vm_region = os.getMemoryRegion(core.pid, 0);

    std.log.debug("Child process base addr: {*}", .{base_vm_region});
    const debug_info = DebugInfo.init(@intFromPtr(base_vm_region.ptr), tracee);

    var line_it = debug_info.line_info.iterator();
    while (line_it.next()) |entry| {
        std.log.debug("Setting breakpoint in {} at line {d}", .{ core.fmtSourceFilepath(&debug_info, entry.value_ptr.source_file), entry.value_ptr.line });
        const bp = createBreakpoint(@ptrFromInt(entry.value_ptr.address));
        core.breakpoints.put(entry.value_ptr.address, bp) catch unreachable;
    }

    os.processResume(core.pid);
    os.waitForPid(core.pid);

    var breakpoints_triggered: usize = 0;
    var bp_it = core.breakpoints.iterator();
    while (bp_it.next()) |entry| {
        if (entry.value_ptr.triggered) {
            breakpoints_triggered += 1;
        }
    }

    std.log.debug("Breakpoints triggered: {d}/{d}", .{ breakpoints_triggered, core.breakpoints.count() });
    report.generateReport(&.{tracee}, debug_info);
}

fn breakpointHandler(pc: usize) bool {
    const bp = core.breakpoints.getPtr(pc) orelse return false;
    removeBreakpoint(bp);
    bp.triggered = true;
    return true;
}

pub fn createBreakpoint(at: [*]u8) core.Breakpoint {
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

pub const std_options: std.Options = .{
    .log_level = if (builtin.mode == .Debug) .debug else .info,
    .logFn = covLog,
};
fn covLog(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const prefix1 = if (scope == .default) "" else "[" ++ @tagName(scope) ++ "] ";
    const prefix2 = switch (level) {
        .err => "error: ",
        .warn => "warning: ",
        .info => "",
        .debug => "debug: ",
    };
    const out_writer = if (level == .err) std.io.getStdErr().writer() else std.io.getStdOut().writer();

    var bw = std.io.bufferedWriter(out_writer);
    const bw_writer = bw.writer();

    nosuspend {
        bw_writer.print(prefix1 ++ prefix2 ++ format ++ "\n", args) catch return;
        bw.flush() catch return;
    }
}
test {
    _ = @import("core/enum_mask.zig");
}
