const std = @import("std");
const panic = std.debug.panic;
const fs = std.fs;
const path = std.fs.path;
const builtin = @import("builtin");
const core = @import("../core.zig");
const bp = @import("../breakpoints.zig");
const cov = @import("../coverage.zig");
const StringInterner = core.StringInterner;
const DebugInfo = @import("../file/debug_info.zig");
const Snapshot = @import("snapshots.zig");
const expectSnapshotMatchString = Snapshot.expectSnapshotMatchString;

const TestBed = @This();

// Sigh ... i really wish it was part of TestBed -.-
var arena_allocator = std.heap.ArenaAllocator.init(std.testing.allocator);

ctx: core.Context,
exe: []const u8,
debug_info: DebugInfo,
coverage_info: cov.CoverageInfo,

pub fn runTest(exe: []const u8, include_paths: []const []const u8) TestBed {
    var ctx = core.Context.init(std.testing.allocator, arena_allocator.allocator());

    const debug_info = DebugInfo.init(&ctx, exe, include_paths);
    bp.runInstrumentedAndWait(&ctx, &debug_info, &.{exe});
    const coverage_info = cov.getCoverageInfo(&ctx, &debug_info);

    return .{
        .ctx = ctx,
        .exe = exe,
        .debug_info = debug_info,
        .coverage_info = coverage_info,
    };
}

pub fn deinit(self: *TestBed) void {
    self.ctx.deinit();
    _ = arena_allocator.reset(.free_all);
}

pub fn expectSourceFiles(self: TestBed, expected: Snapshot) error{ SnapshotMismatch, SnapshotNotFound }!void {
    var received_text = std.ArrayList(u8).init(self.ctx.arena);

    var scratch_arena = std.heap.ArenaAllocator.init(self.ctx.gpa);
    defer scratch_arena.deinit();
    const scratch = scratch_arena.allocator();

    var dir_graph = std.StringHashMap(std.StringHashMap(void)).init(scratch);
    for (self.debug_info.source_files) |source_file| {
        const dir_path = path: {
            if (path.isAbsolute(source_file.dir)) {
                break :path path.relative(scratch, source_file.dir, source_file.comp_dir) catch unreachable;
            }

            break :path source_file.dir;
        };
        const dir_result = dir_graph.getOrPut(dir_path) catch unreachable;
        if (!dir_result.found_existing) {
            dir_result.value_ptr.* = std.StringHashMap(void).init(scratch);
        }
        dir_result.value_ptr.put(source_file.filename, {}) catch unreachable;
    }

    const writer = received_text.writer();
    var index: usize = 0;
    var it = dir_graph.iterator();
    while (it.next()) |entry| : (index += 1) {
        if (index > 0) {
            writer.writeByte('\n') catch unreachable;
        }

        const is_root = entry.key_ptr.*.len == 0;
        if (is_root) {
            writer.writeAll("~/") catch unreachable;
        } else {
            writer.print("{s}/", .{entry.key_ptr.*}) catch unreachable;
        }
        if (entry.value_ptr.count() > 0) {
            writer.writeAll("\n") catch unreachable;
            var file_index: usize = 0;
            var file_it = entry.value_ptr.iterator();
            while (file_it.next()) |file_entry| : (file_index += 1) {
                if (file_index > 0) {
                    writer.writeAll("\n") catch unreachable;
                }
                writer.print("  {s}", .{file_entry.key_ptr.*}) catch unreachable;
            }
        }
    }

    try expectSnapshotMatchString(received_text.items, expected);
}

pub fn expectCoverageInfo(self: TestBed, expected: Snapshot) error{ SnapshotMismatch, SnapshotNotFound }!void {
    var received_text = std.ArrayList(u8).init(self.ctx.arena);
    var scratch_arena = std.heap.ArenaAllocator.init(self.ctx.gpa);
    defer scratch_arena.deinit();
    const scratch = scratch_arena.allocator();

    const writer = received_text.writer();
    writer.print("Command: {s}\n", .{self.exe}) catch unreachable;
    for (self.debug_info.source_files, 0..) |source_file, i| {
        defer _ = scratch_arena.reset(.retain_capacity);

        if (i > 0) {
            writer.writeByte('\n') catch unreachable;
        }

        const file_info = self.coverage_info.file_info.get(@enumFromInt(i)) orelse panic("Cannot get file info for file {s}/{s}", .{ source_file.dir, source_file.filename });
        const filepath = path: {
            if (!path.isAbsolute(source_file.dir)) {
                break :path path.join(scratch, &.{ source_file.comp_dir, source_file.dir, source_file.filename }) catch unreachable;
            }

            break :path path.join(scratch, &.{ source_file.dir, source_file.filename }) catch unreachable;
        };

        writer.print(
            \\File: {s}
            \\Line coverage: {d}/{d}
            \\
        , .{
            filepath,
            file_info.covered_lines,
            file_info.executable_lines,
        }) catch unreachable;

        const fd = fs.openFileAbsolute(filepath, .{ .mode = .read_only }) catch |err| panic("Cannot open file {s}: {}", .{ filepath, err });
        const content = fd.readToEndAlloc(scratch, std.math.maxInt(u32)) catch |err| panic("Cannot read file {s}: {}", .{ filepath, err });

        var index: i32 = 1;
        const line_count = std.mem.count(u8, content, "\n") + 1;
        const line_col_width = std.math.log10(line_count) + 1;
        var line_it = std.mem.splitScalar(u8, content, '\n');
        while (line_it.next()) |line| : (index += 1) {
            const line_status: cov.LineStatus = self.coverage_info.line_info.get(.{ .source_file = @enumFromInt(i), .line = index }) orelse .not_executable;
            const status_char: u8 = switch (line_status) {
                .not_triggered => 'n',
                .triggered => 't',
                .not_executable => '-',
            };

            const cur_line_width = std.math.log10(@as(usize, @intCast(index))) + 1;
            if (cur_line_width < line_col_width) {
                for (0..line_col_width - cur_line_width) |_| {
                    writer.writeByte(' ') catch unreachable;
                }
            }
            writer.print("{d} [{c}]: {s}\n", .{ index, status_char, line }) catch unreachable;
        }
    }

    try expectSnapshotMatchString(received_text.items, expected);
}
