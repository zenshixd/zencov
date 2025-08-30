const std = @import("std");
const builtin = @import("builtin");

pub const Endian = std.builtin.Endian;
pub const native_endian = builtin.cpu.arch.endian();

pub const posix = @import("platform/posix.zig");
pub const mach = @import("platform/mach.zig");
