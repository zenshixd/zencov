const std = @import("std");
const assert = std.debug.assert;

const core = @import("../core.zig");
const DebugInfo = @import("../file/debug_info.zig");

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
    source_file: core.SourceFile,

    pub fn init(source_file: core.SourceFile) SourceFilepathFmt {
        return .{
            .source_file = source_file,
        };
    }

    pub fn format(self: SourceFilepathFmt, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        const comp_dir = core.string_interner.lookup(self.source_file.comp_dir).?;
        const filename = core.string_interner.lookup(self.source_file.filename).?;
        const dir = core.string_interner.lookup(self.source_file.dir).?;
        const display_dir = std.mem.trimLeft(u8, dir, comp_dir);
        if (display_dir.len > 0) {
            try writer.writeAll(display_dir);
            if (!std.mem.endsWith(u8, display_dir, std.fs.path.sep_str)) {
                try writer.writeAll(std.fs.path.sep_str);
            }
        }
        try writer.writeAll(filename);
    }
};
