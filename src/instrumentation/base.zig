const std = @import("std");
const builtin = @import("builtin");
const core = @import("../core.zig");

pub const InstructionSize = if (builtin.cpu.arch.isX86()) u8 else u32;
pub const BRK_OPCODE: InstructionSize = if (builtin.cpu.arch.isX86()) 0xCC else 0xD4200000;

pub const MemoryProtection = enum(u8) {
    read = 1,
    write = 2,
    exec = 4,
};
