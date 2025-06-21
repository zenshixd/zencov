const std = @import("std");
const path = std.fs.path;
const assert = std.debug.assert;
const panic = std.debug.panic;
const core = @import("./core.zig");
const cov = @import("./coverage.zig");

const DebugInfo = @import("./file/debug_info.zig");

const OUT_DIR = "zencov-report";
const CSS_SOURCE_FILE = "assets/file_report.css";
const CSS_DEST_FILE = "index.css";

pub const Subdir = struct {
    source_dir: std.fs.Dir,
    report_dir: std.fs.Dir,
    files: std.ArrayList(core.StringId),
};
pub fn generateReport(command: []const []const u8, source_files: []core.SourceFile, coverage_info: cov.CoverageInfo) void {
    var subdirs = std.StringHashMap(Subdir).init(core.gpa);
    defer {
        var it = subdirs.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.source_dir.close();
            entry.value_ptr.report_dir.close();
            entry.value_ptr.files.deinit();
        }
        subdirs.deinit();
    }

    var scratch_arena = std.heap.ArenaAllocator.init(core.gpa);
    defer scratch_arena.deinit();
    const scratch = scratch_arena.allocator();

    var report_root_dir = std.fs.cwd().makeOpenPath(OUT_DIR, .{}) catch |err| panic("Cannot open dir {s}: {}", .{ OUT_DIR, err });
    defer report_root_dir.close();

    report_root_dir.writeFile(.{ .sub_path = CSS_DEST_FILE, .data = @embedFile(CSS_SOURCE_FILE), .flags = .{} }) catch |err|
        panic("Cannot write file {s}: {}", .{ CSS_DEST_FILE, err });

    for (0..source_files.len) |id| {
        defer _ = scratch_arena.reset(.retain_capacity);

        const source_file = source_files[id];
        const source_dirpath = core.string_interner.lookup(source_file.dir).?;
        const source_filename = core.string_interner.lookup(source_file.filename).?;

        const comp_dir = core.string_interner.lookup(source_file.comp_dir).?;
        const source_reldirpath = std.mem.trimLeft(u8, source_dirpath, comp_dir);
        const report_dirpath = path.join(scratch, &.{ OUT_DIR, source_reldirpath }) catch unreachable;
        const css_dir = std.fs.path.relative(scratch, report_dirpath, OUT_DIR) catch unreachable;
        const css_filepath = path.join(scratch, &.{ css_dir, CSS_DEST_FILE }) catch unreachable;
        const report_filename = std.mem.concat(scratch, u8, &.{ source_filename, ".html" }) catch unreachable;

        const subdir = subdirs.getOrPut(source_dirpath) catch unreachable;
        if (!subdir.found_existing) {
            const source_dir = std.fs.cwd().openDir(source_dirpath, .{}) catch |err| panic("Cannot open dir {s}: {}", .{ source_dirpath, err });
            const report_dir = std.fs.cwd().makeOpenPath(report_dirpath, .{}) catch |err| panic("Cannot open dir {s}: {}", .{ report_dirpath, err });
            subdir.value_ptr.* = .{
                .source_dir = source_dir,
                .report_dir = report_dir,
                .files = std.ArrayList(core.StringId).init(core.arena),
            };
        }
        subdir.value_ptr.files.append(source_file.filename) catch unreachable;

        const source_content = subdir.value_ptr.source_dir.readFileAlloc(scratch, source_filename, std.math.maxInt(u32)) catch |err| panic("Cannot read file {s}: {}", .{ source_filename, err });

        std.log.debug("Writing report file {s}/{s}", .{ report_dirpath, report_filename });
        const cov_file = subdir.value_ptr.report_dir.createFile(report_filename, .{}) catch |err| panic("Cannot open file {s}: {}", .{ report_filename, err });

        cov_file.writer().print("{}", .{
            SourceFileReport{
                .arena = scratch,
                .css_path = css_filepath,
                .command = command,
                .coverage_info = coverage_info,
                .source_file = source_file,
                .source_id = @enumFromInt(id),
                .source_content = source_content,
            },
        }) catch |err| panic("Cannot write file {s}: {}", .{ report_filename, err });
    }

    var it = subdirs.iterator();
    while (it.next()) |entry| {
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
    }
}
pub const SourceFileReport = struct {
    arena: std.mem.Allocator,
    css_path: []const u8,
    command: []const []const u8,
    coverage_info: cov.CoverageInfo,
    source_file: core.SourceFile,
    source_id: core.SourceFileId,
    source_content: []const u8,

    pub fn format(self: SourceFileReport, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        var covered: f32 = 0;
        var total_executable: f32 = 0;

        var it = self.coverage_info.line_info.iterator();
        while (it.next()) |entry| {
            if (entry.key_ptr.source_file == self.source_id) {
                if (entry.value_ptr.* == .triggered) {
                    covered += 1;
                }
                total_executable += 1;
            }
        }

        const command = std.mem.join(self.arena, " ", self.command) catch unreachable;
        try writer.print(@embedFile("assets/file_report.html"), .{
            .filepath = core.SourceFilepathFmt.init(self.source_file),
            .command = command,
            .coverage = covered / total_executable * 100,
            .covered = covered,
            .total = total_executable,
            .css_path = self.css_path,
            .lines = LineNumbers.init(std.mem.count(u8, self.source_content, "\n")),
            .source = SourceCode.init(self.source_id, self.source_content, self.coverage_info),
        });
    }
};

pub const LineNumbers = struct {
    line_count: usize,

    pub fn init(line_count: usize) LineNumbers {
        return .{
            .line_count = line_count,
        };
    }

    pub fn format(self: LineNumbers, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
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
    source_id: core.SourceFileId,
    source_code: []const u8,
    coverage_info: cov.CoverageInfo,

    pub fn init(source_id: core.SourceFileId, source_code: []const u8, coverage_info: cov.CoverageInfo) SourceCode {
        return .{
            .source_id = source_id,
            .source_code = source_code,
            .coverage_info = coverage_info,
        };
    }

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
            const line_status = self.coverage_info.line_info.get(.{ .source_file = self.source_id, .line = index }) orelse .not_executable;
            try writer.print(
                \\<span class="{[status]s}">{[line]s}
                \\</span>
            , .{
                .status = @tagName(line_status),
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
