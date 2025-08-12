// TODO: branch coverage
// TODO: C macros support
// TODO: what about different DWARF versions? I can parse DWARF4, but what about DWARF5?
// TODO: pretty report
// TODO: better grid for index.html files

const builtin = @import("builtin");

const core = @import("core.zig");
const mem = @import("core/mem.zig");
const debug = @import("core/debug.zig");
const logger = @import("core/logger.zig");
const process = @import("core/process.zig");
const platform = @import("platform.zig");
const report = @import("report.zig");
const bp = @import("breakpoints.zig");
const cov = @import("coverage.zig");
const DebugInfo = @import("./debug_info/debug_info.zig");

const TestBed = @import("test/test_bed.zig");
const snap = @import("test/snapshots.zig").snap;

const ZENCOV_INCLUDE_PATHS = &[_][]const u8{"zencov/"};
pub fn main() void {
    var debug_allocator = mem.GeneralAllocator.init();
    defer _ = debug_allocator.deinit();
    var arena_allocator = mem.ArenaAllocator.init();
    defer {
        if (builtin.mode == .Debug) {
            arena_allocator.deinit();
        }
    }

    var ctx = core.Context.init(debug_allocator.allocator(), arena_allocator.allocator());

    const args = process.argsAlloc(ctx.arena) catch unreachable;
    const tracee_cmd = args[1..];
    const debug_info = DebugInfo.init(&ctx, tracee_cmd[0], ZENCOV_INCLUDE_PATHS);
    const pid = bp.runInstrumentedAndWait(&ctx, &debug_info, tracee_cmd);
    const coverage_info = cov.getCoverageInfo(&ctx, pid, &debug_info);
    const coverage_info2 = cov.getCoverageInfo2(&ctx, pid, &debug_info);
    printDirEntry(&coverage_info2);

    report.generateReport(&ctx, tracee_cmd, debug_info.source_files, coverage_info);
}

pub fn printDirEntry(entry: *const cov.DirEntry) void {
    var dirs_it = entry.dirs.iterator();
    while (dirs_it.next()) |dir| {
        logger.debug("{s}/", .{dir.key_ptr.*});
        printDirEntry(dir.value_ptr);
    }

    var files_it = entry.files.iterator();
    while (files_it.next()) |file| {
        logger.debug("{s}", .{file.key_ptr.*});
    }
}

test {
    _ = @import("core/enum_mask.zig");
    _ = @import("core/radix_tree.zig");
    _ = @import("test/snapshots.zig");
}

test "basic" {
    var t = TestBed.runTest("zig-out/bin/basic", ZENCOV_INCLUDE_PATHS);
    defer t.deinit();

    try t.expectSourceFiles(snap(@src(),
        \\main.zig
        \\
    ));
    try t.expectCoverageInfo(snap(@src(),
        \\Command: zig-out/bin/basic
        \\File: tests/basic/main.zig
        \\Line coverage: 4/5
        \\ 1 [-]: const std = @import("std");
        \\ 2 [-]: 
        \\ 3 [t]: pub fn main() void {
        \\ 4 [t]:     var slide = std.c._dyld_get_image_vmaddr_slide(0);
        \\ 5 [t]:     if (slide <= 0) {
        \\ 6 [n]:         slide = 0;
        \\ 7 [-]:     }
        \\ 8 [t]:     slide += 1;
        \\ 9 [-]: }
        \\10 [-]: 
        \\
    ));
}

test "basic multifile" {
    var t = TestBed.runTest("zig-out/bin/basic_multifile", ZENCOV_INCLUDE_PATHS);
    defer t.deinit();

    try t.expectSourceFiles(snap(@src(),
        \\other.zig
        \\main.zig
        \\
    ));
    try t.expectCoverageInfo(snap(@src(),
        \\Command: zig-out/bin/basic_multifile
        \\File: tests/basic_multifile/main.zig
        \\Line coverage: 5/6
        \\ 1 [-]: const std = @import("std");
        \\ 2 [-]: const other_file = @import("other.zig");
        \\ 3 [-]: 
        \\ 4 [t]: pub fn main() void {
        \\ 5 [t]:     var slide = std.c._dyld_get_image_vmaddr_slide(0);
        \\ 6 [t]:     if (slide <= 0) {
        \\ 7 [n]:         slide = 0;
        \\ 8 [-]:     }
        \\ 9 [t]:     slide += 1;
        \\10 [t]:     _ = other_file.testFn(slide);
        \\11 [-]: }
        \\12 [-]: 
        \\
        \\File: tests/basic_multifile/other.zig
        \\Line coverage: 3/3
        \\1 [t]: pub fn testFn(value: usize) bool {
        \\2 [t]:     const x = value + 1;
        \\3 [t]:     return x > 10;
        \\4 [-]: }
        \\5 [-]: 
        \\
    ));
}

test "basic c" {
    var t = TestBed.runTest("zig-out/bin/basic_c", ZENCOV_INCLUDE_PATHS);
    defer t.deinit();

    try t.expectSourceFiles(snap(@src(),
        \\tests/
        \\  basic_c/
        \\    main.c
        \\
    ));
    try t.expectCoverageInfo(snap(@src(),
        \\Command: zig-out/bin/basic_c
        \\File: tests/basic_c/main.c
        \\Line coverage: 7/9
        \\ 1 [-]: #include <stdio.h>
        \\ 2 [-]: 
        \\ 3 [t]: int main() {
        \\ 4 [t]:     int x = 1;
        \\ 5 [t]:     if (x < 1) {
        \\ 6 [n]:       x = 2;
        \\ 7 [n]:     }
        \\ 8 [-]: 
        \\ 9 [t]:     if (x == 1) {
        \\10 [t]:         x = 3;
        \\11 [t]:     }
        \\12 [t]:     return 0;
        \\13 [-]: }
        \\14 [-]: 
        \\
    ));
}

test "basic c multifile" {
    var t = TestBed.runTest("zig-out/bin/basic_c_multifile", ZENCOV_INCLUDE_PATHS);
    defer t.deinit();

    try t.expectSourceFiles(snap(@src(),
        \\tests/
        \\  basic_c_multifile/
        \\    main.c
        \\    other.c
        \\
    ));
    try t.expectCoverageInfo(snap(@src(),
        \\Command: zig-out/bin/basic_c_multifile
        \\File: tests/basic_c_multifile/main.c
        \\Line coverage: 5/7
        \\ 1 [-]: #include <stdio.h> 
        \\ 2 [-]: 
        \\ 3 [-]: void otherFn(int* i);
        \\ 4 [-]: 
        \\ 5 [t]: int main() {
        \\ 6 [t]:     int i = 0;
        \\ 7 [t]:     otherFn(&i);
        \\ 8 [t]:     if (i == 0) {
        \\ 9 [n]:         i = 1;
        \\10 [n]:     }
        \\11 [t]:     return i;
        \\12 [-]: }
        \\13 [-]: 
        \\
        \\File: tests/basic_c_multifile/other.c
        \\Line coverage: 3/3
        \\1 [t]: void otherFn(int* i) {
        \\2 [t]:     *i += 1;
        \\3 [t]: }
        \\4 [-]: 
        \\
    ));
}

test "basic with subdirs" {
    var t = TestBed.runTest("zig-out/bin/basic_with_subdirs", ZENCOV_INCLUDE_PATHS);
    defer t.deinit();

    try t.expectSourceFiles(snap(@src(),
        \\a/
        \\  other.zig
        \\main.zig
        \\
    ));
    try t.expectCoverageInfo(snap(@src(),
        \\Command: zig-out/bin/basic_with_subdirs
        \\File: tests/basic_with_subdirs/main.zig
        \\Line coverage: 2/2
        \\1 [-]: const other = @import("a/other.zig");
        \\2 [-]: 
        \\3 [t]: pub fn main() void {
        \\4 [t]:     _ = other.testFn(0);
        \\5 [-]: }
        \\6 [-]: 
        \\
        \\File: tests/basic_with_subdirs/a/other.zig
        \\Line coverage: 3/3
        \\1 [t]: pub fn testFn(value: usize) bool {
        \\2 [t]:     const x = value + 1;
        \\3 [t]:     return x > 10;
        \\4 [-]: }
        \\5 [-]: 
        \\
    ));
}
