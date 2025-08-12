const mem = @import("./core/mem.zig");
const process = @import("./core/process.zig");
const builtin = @import("builtin");

const inst = @import("./instrumentation.zig");
const mach = @import("./platform.zig").mach;

pub const Context = struct {
    gpa: mem.Allocator,
    arena: mem.Allocator,
    cwd: []const u8,
    breakpoints: inst.BreakpointMap,

    pub fn init(gpa: mem.Allocator, arena: mem.Allocator) Context {
        return .{
            .gpa = gpa,
            .arena = arena,
            .cwd = process.getCwdAlloc(arena) catch unreachable,
            .breakpoints = .init(arena),
        };
    }

    pub fn deinit(self: *Context) void {
        self.breakpoints.deinit();
    }
};

pub const IncludeMode = enum {
    only_comp_dir,
    all,
};
pub const SourceFileId = enum(u32) {
    _,
};

pub const SourceFile = struct {
    path: []const u8,

    pub const Context = struct {
        pub fn hash(self: @This(), k: SourceFile) u32 {
            _ = self;
            return @truncate(hash.Wyhash.hash(0, k.path));
        }
        pub fn eql(self: @This(), a: SourceFile, b: SourceFile, b_index: usize) bool {
            _ = self;
            _ = b_index;
            return mem.eql(u8, a.path, b.path);
        }
    };
};

pub const SourceFileMap = AutoArrayHashMap(SourceFile, SourceFileId);

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
pub const LineInfoMap = AutoArrayHashMap(LineInfoKey, LineInfo);
