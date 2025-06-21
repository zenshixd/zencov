const std = @import("std");
const assert = std.debug.assert;
const panic = std.debug.panic;
const fs = std.fs;
const path = fs.path;

const TESTS_DIR = "tests";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zencov = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "zencov",
        .root_module = zencov,
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const codesign = getCodesignStep(b, exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.step.dependOn(&codesign.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");
    const unit_tests = b.addTest(.{
        .root_module = zencov,
        .filter = b.option([]const u8, "filter", "Run only the specified test"),
    });

    const test_codesign = getCodesignStep(b, unit_tests);
    const run_unit_tests = b.addRunArtifact(unit_tests);
    run_unit_tests.step.dependOn(&test_codesign.step);
    if (b.option(bool, "update", "Update snapshots")) |_| {
        run_unit_tests.setEnvironmentVariable("SNAPSHOT_UPDATE", "1");
    }

    test_step.dependOn(&run_unit_tests.step);

    buildTestBinaries(b, run_unit_tests, target, optimize);
}

pub fn buildTestBinaries(b: *std.Build, test_run_step: *std.Build.Step.Run, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();

    const arena = arena_allocator.allocator();
    var tests_dir = fs.cwd().openDir(TESTS_DIR, .{ .iterate = true }) catch |err| panic("Cannot open tests dir, reason: {}", .{err});
    defer tests_dir.close();

    var it = tests_dir.iterate();
    while (true) {
        const entry = it.next() catch |err| panic("Cannot iterate tests dir, reason: {}", .{err}) orelse break;
        if (entry.kind != .directory) continue;

        var test_dir = tests_dir.openDir(entry.name, .{}) catch |err| panic("Cannot open test dir: {s}, reason: {}", .{ entry.name, err });
        defer test_dir.close();

        var test_kind: enum { none, zig, c } = .none;
        const zig_filepath = std.mem.concat(arena, u8, &.{ entry.name, ".zig" }) catch unreachable;
        const c_filepath = std.mem.concat(arena, u8, &.{ entry.name, ".c" }) catch unreachable;
        if (test_dir.access(zig_filepath, .{ .mode = .read_only })) {
            test_kind = .zig;
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => |e| panic("Cannot access test file: {s}, reason: {}", .{ zig_filepath, e }),
        }

        if (test_dir.access(c_filepath, .{ .mode = .read_only })) {
            if (test_kind != .none) panic("Multiple test files found in test dir: {s}", .{entry.name});
            test_kind = .c;
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => |e| panic("Cannot access test file: {s}, reason: {}", .{ c_filepath, e }),
        }

        assert(test_kind != .none);

        const entry_dir = path.join(arena, &.{ TESTS_DIR, entry.name }) catch unreachable;
        const entry_filepath = path.join(arena, &.{ entry_dir, switch (test_kind) {
            .zig => zig_filepath,
            .c => c_filepath,
            .none => unreachable,
        } }) catch unreachable;
        const exe = b.addExecutable(.{
            .name = entry.name,
            .root_source_file = b.path(entry_filepath),
            .target = target,
            .optimize = optimize,
        });

        const install_step = b.addInstallArtifact(exe, .{});
        test_run_step.step.dependOn(&install_step.step);
    }
}

fn getCodesignStep(b: *std.Build, exe: *std.Build.Step.Compile) *std.Build.Step.Run {
    const codesign = b.addSystemCommand(&.{
        "codesign",
        "--entitlements",
        "entitlements.plist",
        "-f",
        "-s",
        "-",
    });
    codesign.addArtifactArg(exe);
    codesign.step.dependOn(b.getInstallStep());

    return codesign;
}
