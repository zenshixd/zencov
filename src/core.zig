const std = @import("std");
const builtin = @import("builtin");

pub usingnamespace @import("./core/fmt.zig");
pub usingnamespace @import("./core/meta.zig");
pub usingnamespace @import("./core/enum_mask.zig");

pub const StringInterner = @import("./core/string_interner.zig");
pub const StringId = StringInterner.StringId;

pub var debug_allocator = std.heap.DebugAllocator(.{}).init;
pub const gpa = debug_allocator.allocator();

pub var arena_allocator = std.heap.ArenaAllocator.init(gpa);
pub const arena = arena_allocator.allocator();

pub const IncludeMode = enum {
    only_comp_dir,
    all,
};
pub const SourceFileId = enum(u32) {
    _,
};

pub const SourceFile = struct {
    comp_dir: StringId,
    dir: StringId,
    filename: StringId,
};

pub const SourceFileMap = std.AutoArrayHashMap(SourceFile, SourceFileId);

pub const LineInfo = struct {
    source_file: SourceFileId,
    line: i32,
    col: u32,
    address: usize,
};

pub const LineInfoKey = struct {
    source_file: SourceFileId,
    line: i32,
};
pub const LineInfoMap = std.AutoArrayHashMap(LineInfoKey, LineInfo);

pub const InstructionSize = if (builtin.cpu.arch.isX86()) u8 else u32;
pub const BRK_OPCODE: InstructionSize = if (builtin.cpu.arch.isX86()) 0xCC else 0xD4200000;
pub const Breakpoint = struct {
    enabled: bool,
    addr: [*]const u8,
    original_opcode: InstructionSize,
    triggered: bool,
};
pub const BreakpointMap = std.AutoArrayHashMap(usize, Breakpoint);

pub var string_interner = StringInterner.init(arena);
pub var pid: os.PID = undefined;
pub var breakpoints: BreakpointMap = .init(arena);

pub const os = switch (builtin.os.tag) {
    .macos => @import("./os/macos.zig"),
    else => @compileError("Unsupported OS"),
};
