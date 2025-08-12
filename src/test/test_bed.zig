const std = @import("std");
const panic = std.debug.panic;
const fs = std.fs;
const path = std.fs.path;
const builtin = @import("builtin");
const core = @import("../core.zig");
const bp = @import("../breakpoints.zig");
const cov = @import("../coverage.zig");
const DebugInfo = @import("../debug_info/debug_info.zig");
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
    const pid = bp.runInstrumentedAndWait(&ctx, &debug_info, &.{exe});
    const coverage_info = cov.getCoverageInfo(&ctx, pid, &debug_info);

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

    const DirGraphEntry = struct {
        dirs: std.StringHashMap(@This()),
        files: std.StringHashMap(void),

        pub fn format(entry: @This(), writer: anytype, depth: usize) void {
            var dir_it = entry.dirs.iterator();
            while (dir_it.next()) |dir| {
                for (0..depth) |_| {
                    writer.writeAll("  ") catch unreachable;
                }
                writer.print("{s}/\n", .{dir.key_ptr.*}) catch unreachable;
                dir.value_ptr.format(writer, depth + 1);
            }

            var files_it = entry.files.iterator();
            while (files_it.next()) |file| {
                for (0..depth) |_| {
                    writer.writeAll("  ") catch unreachable;
                }
                writer.print("{s}\n", .{file.key_ptr.*}) catch unreachable;
            }
        }

        pub fn ensureParentDirs(entry: *@This(), allocator: std.mem.Allocator, dir_path: []const u8) *@This() {
            var cur_entry = entry;
            var it = path.componentIterator(dir_path) catch |err| panic("Cannot iterate components of {s}: {s}", .{ dir_path, err });
            while (it.next()) |component| {
                const comp_entry = cur_entry.dirs.getOrPut(component.name) catch unreachable;
                if (!comp_entry.found_existing) {
                    comp_entry.value_ptr.* = .{
                        .dirs = std.StringHashMap(@This()).init(allocator),
                        .files = std.StringHashMap(void).init(allocator),
                    };
                }
                cur_entry = comp_entry.value_ptr;
            }

            return cur_entry;
        }
    };

    var root_entry = DirGraphEntry{
        .dirs = std.StringHashMap(DirGraphEntry).init(scratch),
        .files = std.StringHashMap(void).init(scratch),
    };
    for (self.debug_info.source_files) |source_file| {
        var nested_entry = root_entry.ensureParentDirs(scratch, path.dirname(source_file.path).?);
        nested_entry.files.put(path.basename(source_file.path), {}) catch unreachable;
    }

    const writer = received_text.writer();
    root_entry.format(writer, 0);
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

        const file_info = self.coverage_info.file_info.get(@enumFromInt(i)) orelse panic("Cannot get file info for file {s}", .{source_file.path});
        const display_path = core.relativeToCwd(self.ctx.cwd, source_file.path);
        writer.print(
            \\File: {s}
            \\Line coverage: {d}/{d}
            \\
        , .{
            display_path,
            file_info.covered_lines,
            file_info.executable_lines,
        }) catch unreachable;

        const fd = fs.openFileAbsolute(source_file.path, .{ .mode = .read_only }) catch |err| panic("Cannot open file {s}: {}", .{ source_file.path, err });
        const content = fd.readToEndAlloc(scratch, std.math.maxInt(u32)) catch |err| panic("Cannot read file {s}: {}", .{ source_file.path, err });

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
