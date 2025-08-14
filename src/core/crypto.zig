const std = @import("std");

pub const Wyhash = struct {
    pub fn hash(seed: u64, input: []const u8) u64 {
        return std.hash.Wyhash.hash(seed, input);
    }
};
