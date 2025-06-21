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

pub fn main() !void {
    defer {
        // In Release mode this will get cleaned up by OS anyway
        if (builtin.mode == .Debug) {
            core.arena_allocator.deinit();
        }

        // Check for leaks
        _ = core.debug_allocator.deinit();
    }
    const args = try std.process.argsAlloc(core.arena);

    const tracee_cmd = args[1..];
    const debug_info = DebugInfo.init(tracee_cmd[0], .only_comp_dir);
    bp.runInstrumentedAndWait(tracee_cmd, &debug_info);
    const coverage_info = cov.getCoverageInfo(&debug_info);
    report.generateReport(tracee_cmd, debug_info.source_files, coverage_info);
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

    try t.expectCoverageInfo(snap(@src(),
        \\File: /Users/ownelek/Projects/zencov/tests/basic/basic.zig
        \\ 1 [-]: const std = @import("std");
        \\ 2 [-]:
        \\ 3 [t]: pub fn main() void {
        \\ 4 [t]:     const slide = std.c._dyld_get_image_vmaddr_slide(0);
        \\ 5 [t]:     std.log.info("slide: {x}", .{slide});
        \\ 6 [t]:     if (slide <= 0) {
        \\ 7 [n]:         std.log.info("slide is not set", .{});
        \\ 8 [-]:     }
        \\ 9 [t]:     std.log.info("base addr: {x}", .{0x10000000 + std.c._dyld_get_image_vmaddr_slide(0)});
        \\10 [t]:     std.log.info("Hello, World! {x}", .{&main});
        \\11 [-]: }
        \\12 [-]:
        \\
    ));
}
