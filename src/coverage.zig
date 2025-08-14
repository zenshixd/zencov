const std = @import("std");
const panic = std.debug.panic;
const core = @import("core.zig");
const path = @import("core/path.zig");
const inst = @import("instrumentation.zig");
const DebugInfo = @import("./debug_info/debug_info.zig");

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
    file_info: std.AutoArrayHashMap(DebugInfo.SourceFileId, FileInfo),
    line_info: std.AutoArrayHashMap(DebugInfo.LineInfoKey, LineStatus),
};

pub fn getCoverageInfo(ctx: *core.Context, pid: *inst.PID, debug_info: *const DebugInfo) CoverageInfo {
    var file_info = std.AutoArrayHashMap(DebugInfo.SourceFileId, FileInfo).init(ctx.arena);
    var line_info = std.AutoArrayHashMap(DebugInfo.LineInfoKey, LineStatus).init(ctx.arena);
    line_info.ensureTotalCapacity(debug_info.line_info.count()) catch unreachable;

    var it = debug_info.line_info.iterator();
    while (it.next()) |entry| {
        const bp = ctx.breakpoints.get(.{ .pid = pid, .addr = @ptrFromInt(entry.value_ptr.address) }).?;

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

pub const FileEntry = struct {
    executable_lines: u32,
    covered_lines: u32,
    line_info: std.AutoArrayHashMap(i32, LineStatus),
};

pub const DirEntry = struct {
    dirs: std.StringHashMap(@This()),
    files: std.StringHashMap(FileEntry),
    executable_lines: u32,
    covered_lines: u32,

    pub fn ensureParentDirs(entry: *@This(), allocator: std.mem.Allocator, dir_path: []const u8) *@This() {
        var cur_entry = entry;
        var it = path.componentIterator(dir_path) catch |err| panic("Cannot iterate components of {s}: {s}", .{ dir_path, err });
        while (it.next()) |component| {
            const comp_entry = cur_entry.dirs.getOrPut(component.name) catch unreachable;
            if (!comp_entry.found_existing) {
                comp_entry.value_ptr.* = .{
                    .dirs = std.StringHashMap(@This()).init(allocator),
                    .files = std.StringHashMap(FileEntry).init(allocator),
                    .executable_lines = 0,
                    .covered_lines = 0,
                };
            }
            cur_entry = comp_entry.value_ptr;
        }

        return cur_entry;
    }

    pub fn updateLineStatus(entry: *DirEntry, relpath: []const u8, status: LineStatus) void {
        var cur_entry = entry;
        var it = path.componentIterator(path.dirname(relpath).?) catch |err| panic("Cannot iterate components of {s}: {s}", .{ relpath, err });
        while (it.next()) |component| {
            cur_entry.executable_lines += 1;
            if (status == LineStatus.triggered) {
                cur_entry.covered_lines += 1;
            }

            cur_entry = cur_entry.dirs.getPtr(component.name) orelse panic("Cannot find child entry {s}", .{component.name});
        }
    }
};

pub fn getCoverageInfo2(ctx: *core.Context, pid: *inst.PID, debug_info: *const DebugInfo) DirEntry {
    var root_entry = DirEntry{
        .dirs = std.StringHashMap(DirEntry).init(ctx.arena),
        .files = std.StringHashMap(FileEntry).init(ctx.arena),
        .executable_lines = 0,
        .covered_lines = 0,
    };

    var it = debug_info.line_info.iterator();
    while (it.next()) |entry| {
        const source_file = debug_info.source_files[@intFromEnum(entry.value_ptr.source_file)];
        const relpath = path.relativeToCwd(ctx.cwd, source_file.path);

        var dir_entry = root_entry.ensureParentDirs(ctx.arena, path.dirname(relpath) orelse "");
        var file_entry = dir_entry.files.getOrPut(path.basename(relpath)) catch unreachable;
        if (!file_entry.found_existing) {
            file_entry.value_ptr.* = .{
                .executable_lines = 0,
                .covered_lines = 0,
                .line_info = std.AutoArrayHashMap(i32, LineStatus).init(ctx.arena),
            };
        }

        const bp = ctx.breakpoints.get(.{ .pid = pid, .addr = @ptrFromInt(entry.value_ptr.address) }).?;
        const status = status: {
            if (bp.triggered) {
                file_entry.value_ptr.covered_lines += 1;
                break :status LineStatus.triggered;
            }

            break :status LineStatus.not_triggered;
        };
        file_entry.value_ptr.executable_lines += 1;
        file_entry.value_ptr.line_info.put(entry.value_ptr.line, status) catch unreachable;
        root_entry.updateLineStatus(relpath, status);
    }

    return root_entry;
}
