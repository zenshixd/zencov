const std = @import("std");
const path = std.fs.path;
const assert = std.debug.assert;
const panic = std.debug.panic;
const core = @import("./core.zig");

const DebugInfo = @import("./file/debug_info.zig");

const OUT_DIR = "zencov-report";

pub const Subdir = struct {
    source_dir: std.fs.Dir,
    report_dir: std.fs.Dir,
    files: std.ArrayList(core.StringId),
};
pub fn generateReport(command: []const []const u8, debug_info: DebugInfo) void {
    var subdirs = std.StringHashMap(Subdir).init(core.gpa);
    defer {
        var it = subdirs.iterator();
        while (it.next()) |entry| {
            // Before closing, write index.html
            const index_file = entry.value_ptr.report_dir.createFile("index.html", .{}) catch unreachable;
            index_file.writer().print(
                \\<html>
                \\<head>
                \\<title>{s}</title>
                \\</head>
                \\<body>
                \\<ul>
                \\{}
                \\</ul>
                \\</body>
                \\</html>
            , .{
                entry.key_ptr.*,
                ReportList{
                    .files = entry.value_ptr.files.items,
                },
            }) catch unreachable;
            entry.value_ptr.source_dir.close();
            entry.value_ptr.report_dir.close();
            entry.value_ptr.files.deinit();
        }
        subdirs.deinit();
    }

    var temp_arena = std.heap.ArenaAllocator.init(core.gpa);
    defer temp_arena.deinit();
    const arena = temp_arena.allocator();

    for (0..debug_info.source_files.len) |id| {
        defer _ = temp_arena.reset(.retain_capacity);

        const source_file = debug_info.source_files[id];
        const source_dirpath = core.string_interner.lookup(source_file.dir).?;
        const source_filename = core.string_interner.lookup(source_file.filename).?;

        const comp_dir = core.string_interner.lookup(source_file.comp_dir).?;
        const source_reldirpath = std.mem.trimLeft(u8, source_dirpath, comp_dir);
        const report_dirpath = path.join(arena, &.{ OUT_DIR, source_reldirpath }) catch unreachable;
        const report_filename = std.mem.concat(arena, u8, &.{ source_filename, ".html" }) catch unreachable;

        const subdir = subdirs.getOrPut(source_dirpath) catch unreachable;
        if (!subdir.found_existing) {
            const source_dir = std.fs.cwd().openDir(source_dirpath, .{}) catch |err| panic("Cannot open dir {s}: {}", .{ source_dirpath, err });
            const report_dir = std.fs.cwd().makeOpenPath(report_dirpath, .{}) catch |err| panic("Cannot open dir {s}: {}", .{ report_dirpath, err });
            subdir.value_ptr.* = .{
                .source_dir = source_dir,
                .report_dir = report_dir,
                .files = std.ArrayList(core.StringId).init(core.gpa),
            };
        }
        subdir.value_ptr.files.append(source_file.filename) catch unreachable;

        const source_content = subdir.value_ptr.source_dir.readFileAlloc(arena, source_filename, std.math.maxInt(u32)) catch |err| panic("Cannot read file {s}: {}", .{ source_filename, err });

        std.log.debug("Writing report file {s}/{s}", .{ report_dirpath, report_filename });
        const cov_file = subdir.value_ptr.report_dir.createFile(report_filename, .{}) catch |err| panic("Cannot open file {s}: {}", .{ report_filename, err });

        cov_file.writer().print("{}", .{
            SourceFileReport{
                .arena = arena,
                .command = command,
                .debug_info = &debug_info,
                .source_id = @enumFromInt(id),
                .source_content = source_content,
            },
        }) catch |err| panic("Cannot write file {s}: {}", .{ report_filename, err });
    }
}

pub const SourceFileReport = struct {
    arena: std.mem.Allocator,
    command: []const []const u8,
    debug_info: *const DebugInfo,
    source_id: core.SourceFileId,
    source_content: []const u8,

    pub fn format(self: SourceFileReport, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        var line_status = std.ArrayList(LineStatus).init(self.arena);
        defer line_status.deinit();

        var covered: f32 = 0;
        var total_executable: f32 = 0;

        var index: i32 = 1;
        var it = std.mem.splitScalar(u8, self.source_content, '\n');
        while (it.next()) |_| : (index += 1) {
            // If not found - then this line is not executable
            const line_info = self.debug_info.line_info.get(.{ .source_file = self.source_id, .line = index }) orelse {
                line_status.append(.not_executable) catch unreachable;
                continue;
            };

            const bp = core.breakpoints.get(line_info.address).?;
            if (bp.triggered) {
                covered += 1;
                line_status.append(.triggered) catch unreachable;
            } else {
                line_status.append(.not_triggered) catch unreachable;
            }

            total_executable += 1;
        }

        const command = std.mem.join(self.arena, " ", self.command) catch unreachable;
        try writer.print(@embedFile("assets/file_report.html"), .{
            .filepath = core.fmtSourceFilepath(self.debug_info, self.source_id),
            .command = command,
            .coverage = covered / total_executable * 100,
            .covered = covered,
            .total = total_executable,
            .css = @embedFile("assets/file_report.css"),
            .lines = SourceLines{ .line_count = line_status.items.len },
            .source = SourceCode{ .debug_info = self.debug_info, .line_status = line_status.items, .source_id = self.source_id, .source_code = self.source_content },
        });
    }
};

pub const SourceLines = struct {
    line_count: usize,
    pub fn format(self: SourceLines, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.writeAll(
            \\<pre class="line-number">
        );
        for (0..self.line_count) |i| {
            try writer.print("{d}\n", .{i + 1});
        }
        try writer.writeAll(
            \\</pre>
        );
    }
};

const LineStatus = enum { not_triggered, triggered, not_executable };
pub const SourceCode = struct {
    debug_info: *const DebugInfo,
    line_status: []LineStatus,
    source_id: core.SourceFileId,
    source_code: []const u8,

    pub fn format(self: SourceCode, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        var it = std.mem.splitScalar(u8, self.source_code, '\n');
        var index: i32 = 1;
        try writer.writeAll(
            \\<pre>
        );
        while (it.next()) |line| : (index += 1) {
            // If not found - then this line is not executable
            try writer.print(
                \\<span class="{[status]s}">{[line]s}
                \\</span>
            , .{
                .status = @tagName(self.line_status[@intCast(index - 1)]),
                .line = line,
            });
        }
        try writer.writeAll(
            \\</pre>
        );
    }
};

const ReportList = struct {
    files: []core.StringId,

    pub fn format(self: ReportList, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        for (self.files) |file| {
            const filename = core.string_interner.lookup(file).?;
            try writer.print(
                \\<li><a href="{s}.html">{0s}</a></li>
            , .{filename});
        }
    }
};
