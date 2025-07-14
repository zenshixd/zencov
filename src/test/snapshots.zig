const std = @import("std");
const builtin = @import("builtin");
const panic = std.debug.panic;
const assert = std.debug.assert;

const SourceLocation = std.builtin.SourceLocation;
const Allocator = std.mem.Allocator;
const SnapshotHarness = @import("snapshot_harness.zig");

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

pub const Snapshot = @This();

const SourceShift = struct {
    line_num: u32,
    line_shift: i32,
};

var gpa = std.testing.allocator;
var source_shifts: std.StringHashMap(std.ArrayList(SourceShift)) = .init(std.heap.page_allocator);
var snapshots_updated: u32 = 0;

pub fn deinit() void {
    var it = source_shifts.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.clearAndFree();
    }
    source_shifts.clearAndFree();
}

source_location: SourceLocation,
text: []const u8,
should_update: bool = false,

pub fn getSnapshotsUpdated() u32 {
    return snapshots_updated;
}

pub fn getSourceDir() std.fs.Dir.OpenError!std.fs.Dir {
    return std.fs.cwd().openDir("src/", .{});
}

pub fn getSourceFile(self: Snapshot, allocator: Allocator) []const u8 {
    var dir = getSourceDir() catch |err| panic("Cannot open source dir: {}", .{err});
    defer dir.close();

    var file = dir.openFileZ(self.source_location.file, .{}) catch |err| panic("Cannot open source file {s}: {}", .{ self.source_location.file, err });
    defer file.close();

    return file.readToEndAlloc(allocator, std.math.maxInt(u32)) catch |err| panic("Cannot read source file: {}", .{err});
}

pub const SourceFileParts = struct {
    beginning: []const u8,
    snapshot: []const u8,
    snapshot_indent: u32,
    snapshot_end_line: u32,
    ending: []const u8,
};

pub fn getSourceFileParts(self: Snapshot, content: []const u8) error{SnapshotNotFound}!SourceFileParts {
    var state: enum { begin, snapshot } = .begin;
    var begin_end_idx: usize = 0;
    var snapshot_end_idx: usize = 0;
    var snapshot_end_line: u32 = 0;
    var indent: u32 = 0;
    var it = std.mem.splitScalar(u8, content, '\n');

    var line_num: u32 = 1;
    const snapshot_begin_line = self.getSnapshotBeginLine();
    while (it.next()) |line| : (line_num += 1) {
        switch (state) {
            .begin => {
                if (line_num == snapshot_begin_line) {
                    begin_end_idx = it.index orelse panic("reached end of file, content: {s}", .{content});
                    state = .snapshot;
                }
            },
            .snapshot => {
                if (indent == 0) {
                    if (std.mem.indexOf(u8, line, "\\\\") == null) {
                        return error.SnapshotNotFound;
                    }
                    indent = getIndent(line);
                }

                if (std.mem.indexOf(u8, line, "\\\\") == null) {
                    snapshot_end_line = line_num - 1;
                    break;
                } else {
                    snapshot_end_idx = it.index.?;
                }
            },
        }
    }

    return .{
        .beginning = content[0..begin_end_idx],
        .snapshot = content[begin_end_idx..snapshot_end_idx],
        .snapshot_indent = indent,
        .snapshot_end_line = snapshot_end_line,
        .ending = content[snapshot_end_idx..],
    };
}

fn getIndent(text: []const u8) u32 {
    var indent: u32 = 0;
    for (text) |c| {
        if (c == ' ') {
            indent += 1;
        } else {
            break;
        }
    }

    return indent;
}

pub fn getSnapshotBeginLine(self: Snapshot) u32 {
    if (source_shifts.getPtr(self.source_location.file)) |shifts| {
        var new_line_num = self.source_location.line;
        for (shifts.items) |shift| {
            if (new_line_num >= shift.line_num) {
                const signed_line_num: i32 = @intCast(new_line_num);
                new_line_num = @intCast(signed_line_num + shift.line_shift);
            }
        }

        return new_line_num;
    }

    return self.source_location.line;
}

pub fn writeNewSnapshot(self: Snapshot, writer: anytype, parts: SourceFileParts, new_snapshot: []const u8) void {
    const old_snapshot_line_count: i32 = @intCast(std.mem.count(u8, parts.snapshot, "\n"));
    var new_snapshot_line_count: i32 = 0;
    var it = std.mem.splitScalar(u8, new_snapshot, '\n');

    while (it.next()) |line| {
        for (0..parts.snapshot_indent) |_| {
            writer.writeByte(' ') catch unreachable;
        }
        writer.writeAll("\\\\") catch unreachable;
        writer.writeAll(line) catch unreachable;
        writer.writeByte('\n') catch unreachable;
        new_snapshot_line_count += 1;
    }

    const line_shift: i32 = new_snapshot_line_count - old_snapshot_line_count;
    if (line_shift != 0) {
        const result = source_shifts.getOrPutValue(self.source_location.file, .init(std.heap.page_allocator)) catch unreachable;
        result.value_ptr.append(.{
            .line_num = parts.snapshot_end_line,
            .line_shift = line_shift,
        }) catch unreachable;
    }
}

pub fn updateSourceFile(self: Snapshot, new_text: []const u8) void {
    var dir = getSourceDir() catch |err| panic("Cannot open source dir: {}", .{err});
    defer dir.close();

    var file = dir.createFile(self.source_location.file, .{}) catch |err| panic("Cannot open source file {s}: {}", .{ self.source_location.file, err });
    defer file.close();

    file.writeAll(new_text) catch |err| panic("Cannot write source file {s}: {}", .{ self.source_location.file, err });
}

pub fn diff(expected: Snapshot, got: []const u8) error{ SnapshotMismatch, SnapshotNotFound }!void {
    if (!std.mem.eql(u8, expected.text, got)) {
        if (!expected.shouldUpdate()) {
            return error.SnapshotMismatch;
        }

        return expected.update(got) catch |err| {
            // LCOV_EXCL_START
            if (err == error.SnapshotNotFound) {
                std.debug.print("Snapshot not found ! Expected snapshot at {s}:{}", .{ expected.source_location.file, getSnapshotBeginLine(expected) });
            }

            return err;
            // LCOV_EXCL_STOP
        };
    }
}

pub fn shouldUpdate(self: Snapshot) bool {
    return self.should_update or std.process.hasEnvVarConstant("SNAPSHOT_UPDATE");
}

pub fn update(self: Snapshot, new_text: []const u8) error{SnapshotNotFound}!void {
    var new_file_content = std.ArrayList(u8).init(gpa);
    defer new_file_content.deinit();

    const content = self.getSourceFile(gpa);
    defer gpa.free(content);

    const parts = try self.getSourceFileParts(content);

    new_file_content.appendSlice(parts.beginning) catch unreachable;
    self.writeNewSnapshot(new_file_content.writer(), parts, new_text);
    new_file_content.appendSlice(parts.ending) catch unreachable;

    self.updateSourceFile(new_file_content.items);

    snapshots_updated += 1;
}

pub inline fn snap(source_location: SourceLocation, text: []const u8) Snapshot {
    return .{
        .source_location = source_location,
        .text = text,
    };
}

pub fn expectSnapshotMatchString(received: []const u8, expected: Snapshot) error{ SnapshotMismatch, SnapshotNotFound }!void {
    expected.diff(received) catch |err| {
        // LCOV_EXCL_START
        if (err == error.SnapshotMismatch) {
            std.debug.print(
                \\SnapshotMismatch
                \\expected:
                \\{s}
                \\
                \\got:
                \\{s}
                \\
            , .{ expected.text, received });
        }

        return err;
        // LCOV_EXCL_STOP
    };
}

test "should return void if snapshot matches" {
    const snapshot_text = "\"hello world\"";

    var h = SnapshotHarness.init(snapshot_text);
    defer h.deinit();

    try expectSnapshotMatchString("\"hello world\"", h.snapshots[0]);
}

test "should return error if snapshot is mismatched" {
    const snapshot_text = "hello world";

    var h = SnapshotHarness.init(snapshot_text);
    defer h.deinit();

    const result = h.snapshots[0].diff("hello worlds");

    if (h.snapshots[0].should_update) {
        try result;
    } else {
        try expectError(error.SnapshotMismatch, result);
    }
}

test "should return error if snapshot is not found when trying to update" {
    const file_content =
        \\snap(@src(), "hello world");
        \\
    ;

    var h = SnapshotHarness.init("");
    defer h.deinit();
    h.updateTestFile(file_content);

    const result = h.snapshots[0].update("hello worlds");

    try expectError(error.SnapshotNotFound, result);
}

test "should update single line snapshot" {
    const snapshot_text =
        \\1
    ;

    var h = SnapshotHarness.init(snapshot_text);
    defer h.deinit();

    try h.snapshots[0].update(
        \\2
    );
    try h.expectTestFileEqual(
        \\snap(@src(),
        \\    \\2
        \\);
        \\
    );
}

test "should update multiline snapshot" {
    const snapshot_text =
        \\1
        \\2
        \\3
    ;

    var h = SnapshotHarness.init(snapshot_text);
    defer h.deinit();
    try h.snapshots[0].update(
        \\1
        \\2
        \\3
        \\4
        \\5
    );

    try h.expectTestFileEqual(
        \\snap(@src(),
        \\    \\1
        \\    \\2
        \\    \\3
        \\    \\4
        \\    \\5
        \\);
        \\
    );
}

test "should update multiple snapshots" {
    const snapshot_text1 =
        \\11
    ;
    const snapshot_text2 =
        \\21
    ;

    var h = SnapshotHarness.initMultiple(&.{ snapshot_text1, snapshot_text2 });
    defer h.deinit();

    try h.snapshots[0].update(
        \\11
        \\12
    );
    try h.snapshots[1].update(
        \\21
        \\22
    );

    try h.expectTestFileEqual(
        \\snap(@src(),
        \\    \\11
        \\    \\12
        \\);
        \\snap(@src(),
        \\    \\21
        \\    \\22
        \\);
        \\
    );
}

test "should update multiple multiline snapshots" {
    const snapshot_texts = [_][]const u8{
        \\1
        ,
        \\2
        ,
        \\3
        ,
        \\4
        ,
    };

    const updated_texts = [_][]const u8{
        \\11
        \\12
        \\13
        \\14
        ,
        \\21
        \\22
        \\23
        \\24
        ,
        \\31
        \\32
        \\33
        \\34
        ,
        \\41
        \\42
        \\43
        \\44
        ,
    };

    var h = SnapshotHarness.initMultiple(&snapshot_texts);
    defer h.deinit();

    for (h.snapshots, 0..) |snapshot, i| {
        try snapshot.update(updated_texts[i]);
    }

    try h.expectTestFileEqual(
        \\snap(@src(),
        \\    \\11
        \\    \\12
        \\    \\13
        \\    \\14
        \\);
        \\snap(@src(),
        \\    \\21
        \\    \\22
        \\    \\23
        \\    \\24
        \\);
        \\snap(@src(),
        \\    \\31
        \\    \\32
        \\    \\33
        \\    \\34
        \\);
        \\snap(@src(),
        \\    \\41
        \\    \\42
        \\    \\43
        \\    \\44
        \\);
        \\
    );
}
