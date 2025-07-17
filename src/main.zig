// TODO: branch coverage
// TODO: C macros support
// TODO: what about different DWARF versions? I can parse DWARF4, but what about DWARF5?
// TODO: pretty report
// TODO: better grid for index.html files

const std = @import("std");
const assert = std.debug.assert;
const panic = std.debug.panic;
const builtin = @import("builtin");

const DebugInfo = @import("./file/debug_info.zig");
const core = @import("core.zig");
const os = core.os;
const platform = @import("platform.zig");
const report = @import("report.zig");
const bp = @import("breakpoints.zig");
const cov = @import("coverage.zig");

const TestBed = @import("test/test_bed.zig");
const snap = @import("test/snapshots.zig").snap;

pub fn main() void {
    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    defer _ = debug_allocator.deinit();
    var arena_allocator = std.heap.ArenaAllocator.init(debug_allocator.allocator());
    defer {
        if (builtin.mode == .Debug) {
            arena_allocator.deinit();
        }
    }

    var ctx = core.Context.init(debug_allocator.allocator(), arena_allocator.allocator());

    const args = std.process.argsAlloc(ctx.arena) catch unreachable;
    const tracee_cmd = args[1..];
    const debug_info = DebugInfo.init(&ctx, tracee_cmd[0], .only_comp_dir);
    bp.runInstrumentedAndWait(&ctx, tracee_cmd, &debug_info);
    const coverage_info = cov.getCoverageInfo(&ctx, &debug_info);
    report.generateReport(&ctx, tracee_cmd, debug_info.source_files, coverage_info);
}

pub const std_options: std.Options = .{
    .log_level = if (builtin.mode == .Debug) .debug else .info,
    .logFn = covLog,
};
fn covLog(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const prefix1 = if (scope == .default) "" else "[" ++ @tagName(scope) ++ "] ";
    const prefix2 = switch (level) {
        .err => "error: ",
        .warn => "warning: ",
        .info => "",
        .debug => "debug: ",
    };
    const out_writer = if (level == .err) std.io.getStdErr().writer() else std.io.getStdOut().writer();

    var bw = std.io.bufferedWriter(out_writer);
    const bw_writer = bw.writer();

    nosuspend {
        bw_writer.print(prefix1 ++ prefix2 ++ format ++ "\n", args) catch return;
        bw.flush() catch return;
    }
}
test {
    _ = @import("core/enum_mask.zig");
    _ = @import("test/snapshots.zig");
}

test "basic" {
    var t = TestBed.runTest("zig-out/bin/basic", .only_comp_dir);
    defer t.deinit();

    try t.expectSourceFiles(snap(@src(),
        \\~/
        \\  main.zig
    ));
    try t.expectCoverageInfo(snap(@src(),
        \\Command: zig-out/bin/basic
        \\File: /Users/ownelek/Projects/zencov/tests/basic/main.zig
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
    var t = TestBed.runTest("zig-out/bin/basic_multifile", .only_comp_dir);
    defer t.deinit();

    try t.expectSourceFiles(snap(@src(),
        \\~/
        \\  other.zig
        \\  main.zig
    ));
    try t.expectCoverageInfo(snap(@src(),
        \\Command: zig-out/bin/basic_multifile
        \\File: /Users/ownelek/Projects/zencov/tests/basic_multifile/main.zig
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
        \\File: /Users/ownelek/Projects/zencov/tests/basic_multifile/other.zig
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
    var t = TestBed.runTest("zig-out/bin/basic_c", .only_comp_dir);
    defer t.deinit();

    try t.expectSourceFiles(snap(@src(),
        \\tests/basic_c/
        \\  main.c
    ));
    // FIXME: why closing bracket is counted as executable???
    try t.expectCoverageInfo(snap(@src(),
        \\Command: zig-out/bin/basic_c
        \\File: /Users/ownelek/Projects/zencov/tests/basic_c/main.c
        \\Line coverage: 4/6
        \\ 1 [-]: #include <stdio.h>
        \\ 2 [-]: 
        \\ 3 [t]: int main() {
        \\ 4 [t]:     int x = 1;
        \\ 5 [t]:     if (x < 1) {
        \\ 6 [n]:       x = 2;
        \\ 7 [n]:     }
        \\ 8 [t]:     return 0;
        \\ 9 [-]: }
        \\10 [-]: 
        \\
    ));
}

test "basic c multifile" {
    var t = TestBed.runTest("zig-out/bin/basic_c_multifile", .only_comp_dir);
    defer t.deinit();

    try t.expectSourceFiles(snap(@src(),
        \\tests/basic_c_multifile/
        \\  main.c
        \\  other.c
    ));
    // FIXME: Breakpoints are set incorrectly - C compiler bundles multiple .o files
    // and they have different addresses in executable than in debug info
    try t.expectCoverageInfo(snap(@src(),
        \\Command: zig-out/bin/basic_c_multifile
        \\File: /Users/ownelek/Projects/zencov/tests/basic_c_multifile/main.c
        \\Line coverage: 0/7
        \\ 1 [-]: #include <stdio.h> 
        \\ 2 [-]: 
        \\ 3 [-]: void otherFn(int* i);
        \\ 4 [-]: 
        \\ 5 [n]: int main() {
        \\ 6 [n]:     int i = 0;
        \\ 7 [n]:     otherFn(&i);
        \\ 8 [n]:     if (i == 0) {
        \\ 9 [n]:         i = 1;
        \\10 [n]:     }
        \\11 [n]:     return i;
        \\12 [-]: }
        \\13 [-]: 
        \\
        \\File: /Users/ownelek/Projects/zencov/tests/basic_c_multifile/other.c
        \\Line coverage: 0/3
        \\1 [n]: void otherFn(int* i) {
        \\2 [n]:     i++;
        \\3 [n]: }
        \\4 [-]: 
        \\
    ));
}
