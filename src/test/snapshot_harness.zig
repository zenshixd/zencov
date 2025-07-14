const std = @import("std");
const fs = std.fs;
const panic = std.debug.panic;
const path = std.fs.path;
const Snapshot = @import("snapshots.zig");

const expectEqualStrings = std.testing.expectEqualStrings;

const SnapshotHarness = @This();
pub const TEST_FILE = ".tmp/test.zig";

arena_allocator: std.heap.ArenaAllocator,
src_dir: fs.Dir,
snapshots: []Snapshot,

pub fn init(text: []const u8) SnapshotHarness {
    return initMultiple(&.{text});
}

pub fn initMultiple(snapshot_texts: []const []const u8) SnapshotHarness {
    var arena_allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    const arena = arena_allocator.allocator();

    const src_dir = Snapshot.getSourceDir() catch |err| panic("Cannot open source dir: {}", .{err});

    var content = std.ArrayList(u8).init(arena);
    var snapshots = std.ArrayList(Snapshot).init(arena);
    for (snapshot_texts) |snapshot_text| {
        const start_line = std.mem.count(u8, content.items, "\n") + 1;
        content.writer().print(
            \\snap(@src(),
            \\{}
            \\);
            \\
        , .{StringAsZigMultilineFmt.init(snapshot_text)}) catch unreachable;

        snapshots.append(Snapshot{
            .source_location = .{
                .file = TEST_FILE,
                .line = @intCast(start_line),
                .column = 1,
                .fn_name = "",
                .module = "",
            },
            .text = snapshot_text,
            .should_update = std.process.hasEnvVarConstant("SNAPSHOT_UPDATE"),
        }) catch unreachable;
    }

    var tmp_dir = src_dir.makeOpenPath(path.dirname(TEST_FILE).?, .{}) catch |err| panic("Cannot create tmp dir {s}: {}", .{ path.dirname(TEST_FILE).?, err });
    defer tmp_dir.close();

    src_dir.writeFile(.{
        .sub_path = TEST_FILE,
        .data = content.items,
        .flags = .{
            .truncate = true,
        },
    }) catch |err| panic("Cannot write file {s}: {}", .{ TEST_FILE, err });

    return SnapshotHarness{
        .arena_allocator = arena_allocator,
        .src_dir = src_dir,
        .snapshots = snapshots.items,
    };
}

pub fn deinit(self: *SnapshotHarness) void {
    self.arena_allocator.deinit();
    self.src_dir.deleteTree(path.dirname(TEST_FILE).?) catch |err| panic("Cannot delete dir {s}: {}", .{ path.dirname(TEST_FILE).?, err });
    self.src_dir.close();
    Snapshot.deinit();
}

pub fn updateTestFile(self: *SnapshotHarness, text: []const u8) void {
    self.src_dir.writeFile(.{
        .sub_path = TEST_FILE,
        .data = text,
        .flags = .{
            .truncate = true,
        },
    }) catch |err| panic("Cannot write file {s}: {}", .{ TEST_FILE, err });
}

pub fn expectTestFileEqual(self: *SnapshotHarness, expected: []const u8) !void {
    const arena = self.arena_allocator.allocator();
    const file = self.src_dir.openFile(TEST_FILE, .{}) catch |err| panic("Cannot open file {s}: {}", .{ TEST_FILE, err });
    defer file.close();

    const content = file.readToEndAlloc(arena, std.math.maxInt(u32)) catch |err| panic("Cannot read file {s}: {}", .{ TEST_FILE, err });

    try expectEqualStrings(expected, content);
}

const StringAsZigMultilineFmt = struct {
    str: []const u8,

    pub fn init(str: []const u8) StringAsZigMultilineFmt {
        return .{ .str = str };
    }

    pub fn format(self: StringAsZigMultilineFmt, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        var it = std.mem.splitScalar(u8, self.str, '\n');
        var line_num: u32 = 0;
        while (it.next()) |line| : (line_num += 1) {
            if (line_num > 0) {
                try writer.writeByte('\n');
            }
            try writer.writeAll("    \\\\");
            try writer.writeAll(line);
        }
    }
};
