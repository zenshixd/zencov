const std = @import("std");
const core = @import("core.zig");
const DebugInfo = @import("./file/debug_info.zig");

pub const LineStatus = enum {
    not_triggered,
    triggered,
    not_executable,
};

pub const CoverageInfo = struct {
    executable_lines: usize,
    covered_lines: usize,
    line_info: std.AutoArrayHashMap(core.LineInfoKey, LineStatus),
};

pub fn getCoverageInfo(ctx: *core.Context, debug_info: *const DebugInfo) CoverageInfo {
    var executable_lines: usize = 0;
    var covered_lines: usize = 0;
    var line_info = std.AutoArrayHashMap(core.LineInfoKey, LineStatus).init(ctx.arena);
    line_info.ensureTotalCapacity(debug_info.line_info.count()) catch unreachable;

    var it = debug_info.line_info.iterator();
    while (it.next()) |entry| {
        const bp = ctx.breakpoints.get(entry.value_ptr.address).?;
        const status = status: {
            if (bp.triggered) {
                covered_lines += 1;
                break :status LineStatus.triggered;
            }

            break :status LineStatus.not_triggered;
        };
        line_info.putAssumeCapacity(entry.key_ptr.*, status);
        executable_lines += 1;
    }
    return .{
        .executable_lines = executable_lines,
        .covered_lines = covered_lines,
        .line_info = line_info,
    };
}
