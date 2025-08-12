const std = @import("std");

pub fn relativeToCwd(cwd: []const u8, path: []const u8) []const u8 {
    if (std.mem.startsWith(u8, path, cwd)) {
        return path[cwd.len..];
    }

    return path;
}
