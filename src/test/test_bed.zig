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

exe: []const u8,
debug_info: DebugInfo,
coverage_info: cov.CoverageInfo,

pub fn runTest(exe: []const u8, include_mode: core.IncludeMode) TestBed {
    core.string_interner = StringInterner.init(core.arena);
    core.pid = undefined;
    core.breakpoints = .init(core.arena);

    _ = include_mode;
    // const debug_info = DebugInfo.init(exe, include_mode);
    // bp.runInstrumentedAndWait(&.{exe}, &debug_info);
    // const coverage_info = cov.getCoverageInfo(&debug_info);

    return .{
        .exe = exe,
        .debug_info = DebugInfo{
            .source_files = &.{},
            .line_info = core.LineInfoMap.init(core.arena),
        },
        .coverage_info = .{
            .line_info = std.AutoArrayHashMap(core.LineInfoKey, cov.LineStatus).init(core.arena),
        },
    };
}

pub fn deinit(_: *TestBed) void {
    _ = core.debug_allocator.deinit();
    core.arena_allocator.deinit();
}

pub fn expectCoverageInfo(self: TestBed, expected: Snapshot) error{ SnapshotMismatch, SnapshotNotFound }!void {
    var received_text = std.ArrayList(u8).init(core.gpa);
    defer received_text.deinit();

    var scratch_arena = std.heap.ArenaAllocator.init(core.gpa);
    defer scratch_arena.deinit();
    const scratch = scratch_arena.allocator();

    const writer = received_text.writer();
    for (self.debug_info.source_files, 0..) |source_file, i| {
        defer _ = scratch_arena.reset(.retain_capacity);

        if (i > 0) {
            writer.writeByte('\n') catch unreachable;
        }
        const filename = core.string_interner.lookup(source_file.filename).?;
        const dir = core.string_interner.lookup(source_file.dir).?;

        const filepath = path.join(scratch, &.{ dir, filename }) catch unreachable;

        writer.print("File: {s}\n", .{filepath}) catch unreachable;

        const fd = fs.openFileAbsolute(filepath, .{ .mode = .read_only }) catch |err| panic("Cannot open file {s}: {}", .{ filepath, err });
        const content = fd.readToEndAlloc(scratch, std.math.maxInt(u32)) catch |err| panic("Cannot read file {s}: {}", .{ filepath, err });

        var index: i32 = 1;
        const line_count = std.mem.count(u8, content, "\n");
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
            for (0..line_col_width - cur_line_width) |_| {
                writer.writeByte(' ') catch unreachable;
            }
            writer.print("{d} [{c}]: {s}\n", .{ index, status_char, line }) catch unreachable;
        }
    }

    try expectSnapshotMatchString(received_text.items, expected);
}
