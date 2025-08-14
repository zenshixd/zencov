const std = @import("std");
const assert = std.debug.assert;

const core = @import("../core.zig");
const path = @import("../core/path.zig");
const DebugInfo = @import("../debug_info/debug_info.zig");

pub const ByteCodeFormatter = struct {
    at: usize,
    bytes: []const u8,

    pub fn format(self: ByteCodeFormatter, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Byte code:\n", .{});
        for (0..@divFloor(self.bytes.len, 4)) |i| {
            // Arm is in little endian but we want to print in big endian
            var instr: [4]u8 = self.bytes[i * 4 ..][0..4].*;
            std.mem.reverse(u8, &instr);
            if (self.at == i) {
                try writer.writeAll(">");
            } else {
                try writer.writeAll(" ");
            }
            try writer.print("{}\n", .{std.fmt.fmtSliceHexUpper(&instr)});
        }
    }
};

pub const SourceFilepathFmt = struct {
    ctx: *core.Context,
    source_file: DebugInfo.SourceFile,

    pub fn format(self: SourceFilepathFmt, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.writeAll(path.relativeToCwd(self.ctx.cwd, self.source_file.path));
    }
};
