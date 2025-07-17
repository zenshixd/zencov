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
    const arena = b.allocator;
    var tests_dir = fs.cwd().openDir(TESTS_DIR, .{ .iterate = true }) catch |err| panic("Cannot open tests dir, reason: {}", .{err});
    defer tests_dir.close();

    var it = tests_dir.iterate();
    while (true) {
        const entry = it.next() catch |err| panic("Cannot iterate tests dir, reason: {}", .{err}) orelse break;
        if (entry.kind != .directory) continue;

        var test_dir = tests_dir.openDir(entry.name, .{}) catch |err| panic("Cannot open test dir: {s}, reason: {}", .{ entry.name, err });
        defer test_dir.close();

        var test_kind: enum { none, zig, c } = .none;
        const entry_dir = path.join(arena, &.{ TESTS_DIR, entry.name }) catch unreachable;
        var entry_filepath: []const u8 = undefined;
        const zig_entry_file = "main.zig";
        const c_entry_file = "main.c";
        if (test_dir.access(zig_entry_file, .{ .mode = .read_only })) {
            test_kind = .zig;
            entry_filepath = path.join(arena, &.{ entry_dir, zig_entry_file }) catch unreachable;
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => |e| panic("Cannot access test file: {s}, reason: {}", .{ zig_entry_file, e }),
        }

        if (test_dir.access(c_entry_file, .{ .mode = .read_only })) {
            if (test_kind != .none) panic("Multiple test files found in test dir: {s}", .{entry.name});
            test_kind = .c;
            entry_filepath = path.join(arena, &.{ entry_dir, c_entry_file }) catch unreachable;
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => |e| panic("Cannot access test file: {s}, reason: {}", .{ c_entry_file, e }),
        }

        const exe = exe: {
            switch (test_kind) {
                .c => {
                    var c_source_files = std.ArrayList([]const u8).init(arena);

                    var walker = test_dir.walk(arena) catch unreachable;
                    defer walker.deinit();

                    while (walker.next() catch unreachable) |c_entry| {
                        if (c_entry.kind != .file) continue;
                        if (!std.mem.endsWith(u8, c_entry.basename, ".c")) continue;
                        c_source_files.append(arena.dupe(u8, c_entry.path) catch unreachable) catch unreachable;
                    }

                    const c_exe = b.addExecutable(.{
                        .name = entry.name,
                        .target = target,
                        .optimize = optimize,
                    });
                    c_exe.addCSourceFiles(.{
                        .root = b.path(entry_dir),
                        .files = c_source_files.toOwnedSlice() catch unreachable,
                        .language = .c,
                    });
                    c_exe.linkLibC();
                    break :exe c_exe;
                },
                .zig => {
                    const zig_exe = b.addExecutable(.{
                        .name = entry.name,
                        .root_source_file = b.path(entry_filepath),
                        .target = target,
                        .optimize = optimize,
                    });
                    break :exe zig_exe;
                },
                .none => unreachable,
            }
        };

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
