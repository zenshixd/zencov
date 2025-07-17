const std = @import("std");
const builtin = @import("builtin");

pub usingnamespace @import("./core/fmt.zig");
pub usingnamespace @import("./core/meta.zig");
pub usingnamespace @import("./core/enum_mask.zig");

const platform = @import("./platform.zig");

pub const ContextDarwin = struct {
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    pid: os.PID,
    breakpoints: BreakpointMap,
    process_port_map: std.AutoArrayHashMap(os.PID, platform.MachPort),
    exception_port_map: std.AutoArrayHashMap(os.PID, platform.MachPort),
    breakpoint_handler_map: std.AutoArrayHashMap(os.PID, *const fn (ctx: *Context, pc: usize) bool),

    pub fn init(gpa: std.mem.Allocator, arena: std.mem.Allocator) Context {
        return .{
            .gpa = gpa,
            .arena = arena,
            .pid = undefined,
            .breakpoints = .init(arena),
            .process_port_map = .init(arena),
            .exception_port_map = .init(arena),
            .breakpoint_handler_map = .init(arena),
        };
    }

    pub fn deinit(self: *Context) void {
        self.breakpoints.deinit();
        self.process_port_map.deinit();
        self.exception_port_map.deinit();
        self.breakpoint_handler_map.deinit();
    }
};

pub const Context = switch (builtin.os.tag) {
    .macos => ContextDarwin,
    else => @compileError("Unsupported OS"),
};

pub const IncludeMode = enum {
    only_comp_dir,
    all,
};
pub const SourceFileId = enum(u32) {
    _,
};

pub const SourceFile = struct {
    comp_dir: []const u8,
    dir: []const u8,
    filename: []const u8,

    pub const Context = struct {
        pub fn hash(self: @This(), k: SourceFile) u32 {
            _ = self;
            return @truncate(std.hash.Wyhash.hash(0, k.comp_dir) ^ std.hash.Wyhash.hash(0, k.dir) ^ std.hash.Wyhash.hash(0, k.filename));
        }
        pub fn eql(self: @This(), a: SourceFile, b: SourceFile, b_index: usize) bool {
            _ = self;
            _ = b_index;
            return std.mem.eql(u8, a.comp_dir, b.comp_dir) and std.mem.eql(u8, a.dir, b.dir) and std.mem.eql(u8, a.filename, b.filename);
        }
    };
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

pub const os = switch (builtin.os.tag) {
    .macos => @import("./os/macos.zig"),
    else => @compileError("Unsupported OS"),
};
