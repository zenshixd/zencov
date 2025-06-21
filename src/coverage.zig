const std = @import("std");
const core = @import("core.zig");
const DebugInfo = @import("./file/debug_info.zig");

pub const LineStatus = enum {
    not_triggered,
    triggered,
    not_executable,
};

pub const CoverageInfo = struct {
    line_info: std.AutoArrayHashMap(core.LineInfoKey, LineStatus),
};

pub fn getCoverageInfo(debug_info: *const DebugInfo) CoverageInfo {
    var line_info = std.AutoArrayHashMap(core.LineInfoKey, LineStatus).init(core.arena);
    line_info.ensureTotalCapacity(debug_info.line_info.count()) catch unreachable;

    var it = debug_info.line_info.iterator();
    while (it.next()) |entry| {
        const bp = core.breakpoints.get(entry.value_ptr.address).?;
        line_info.putAssumeCapacity(entry.key_ptr.*, if (bp.triggered) .triggered else .not_triggered);
    }
    return .{
        .line_info = line_info,
    };
}
