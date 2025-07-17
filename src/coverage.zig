const std = @import("std");
const core = @import("core.zig");
const DebugInfo = @import("./file/debug_info.zig");

pub const FileInfo = struct {
    executable_lines: usize,
    covered_lines: usize,
};

pub const LineStatus = enum {
    not_triggered,
    triggered,
    not_executable,
};

pub const CoverageInfo = struct {
    file_info: std.AutoArrayHashMap(core.SourceFileId, FileInfo),
    line_info: std.AutoArrayHashMap(core.LineInfoKey, LineStatus),
};

pub fn getCoverageInfo(ctx: *core.Context, debug_info: *const DebugInfo) CoverageInfo {
    var file_info = std.AutoArrayHashMap(core.SourceFileId, FileInfo).init(ctx.arena);
    var line_info = std.AutoArrayHashMap(core.LineInfoKey, LineStatus).init(ctx.arena);
    line_info.ensureTotalCapacity(debug_info.line_info.count()) catch unreachable;

    var it = debug_info.line_info.iterator();
    while (it.next()) |entry| {
        const bp = ctx.breakpoints.get(entry.value_ptr.address).?;

        const file_info_item = file_info.getOrPut(entry.key_ptr.source_file) catch unreachable;
        if (!file_info_item.found_existing) {
            file_info_item.value_ptr.* = .{
                .executable_lines = 0,
                .covered_lines = 0,
            };
        }
        const status = status: {
            if (bp.triggered) {
                file_info_item.value_ptr.covered_lines += 1;
                break :status LineStatus.triggered;
            }

            break :status LineStatus.not_triggered;
        };
        line_info.putAssumeCapacity(entry.key_ptr.*, status);
        file_info_item.value_ptr.executable_lines += 1;
    }

    return .{
        .file_info = file_info,
        .line_info = line_info,
    };
}
