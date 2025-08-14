const std = @import("std");
const builtin = @import("builtin");
const native_endian = builtin.cpu.arch.endian();

const core = @import("../core.zig");
const debug = @import("../core/debug.zig");
const heap = @import("../core/heap.zig");
const crypto = @import("../core/crypto.zig");
const fmt = @import("../core/fmt.zig");
const path = @import("../core/path.zig");
const logger = @import("../core/logger.zig");
const mem = @import("../core/mem.zig");
const macho = @import("./macho.zig");
const Dwarf = @import("./dwarf.zig");
const DW = @import("./dwarf.zig").DW;
const SectionId = @import("./dwarf.zig").SectionId;
const Section = @import("./dwarf.zig").Section;

const DebugInfo = @This();
const PAGEZERO_OFFSET = 0x100000000;

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
            return @truncate(crypto.Wyhash.hash(0, k.path));
        }
        pub fn eql(self: @This(), a: SourceFile, b: SourceFile, b_index: usize) bool {
            _ = self;
            _ = b_index;
            return mem.eql(u8, a.path, b.path);
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

source_files: []SourceFile,
line_info: LineInfoMap,

pub fn init(ctx: *core.Context, exec_file: []const u8, include_paths: []const []const u8) DebugInfo {
    var scratch_arena = heap.ArenaAllocator.init();
    defer scratch_arena.deinit();
    const scratch = scratch_arena.allocator();

    var source_files_map = std.ArrayHashMap(SourceFile, SourceFileId, SourceFile.Context, false).init(scratch);
    var line_info = LineInfoMap.init(ctx.arena);

    var dwarfs = std.ArrayList(Dwarf).init(scratch);
    const parsed_exec = parseMachoBinary(scratch, exec_file) catch |err| switch (err) {
        error.FileNotFound => debug.panic("Cannot open executable file {s}: {}", .{ exec_file, err }),
    };
    logger.debug(".o file count: {d}", .{parsed_exec.obj_files.len});
    if (parsed_exec.dwarf) |d| {
        dwarfs.append(d) catch unreachable;
    }

    logger.debug("DIE count: {d}", .{dwarfs.items.len});

    var loop_arena = heap.ArenaAllocator.init();
    defer loop_arena.deinit();
    const loop = loop_arena.allocator();
    var filenames_map = std.AutoArrayHashMap(struct { dir: u32, file: u32 }, SourceFileId).init(scratch);
    for (parsed_exec.obj_files) |o_file| {
        logger.debug("Parsing .o file: {s}", .{o_file});
        const parsed_obj_file = parseMachoBinary(scratch, o_file) catch |err| switch (err) {
            error.FileNotFound => {
                logger.debug("Cannot open .o file: {s}", .{o_file});
                continue;
            },
        };
        var di = parsed_obj_file.dwarf orelse {
            logger.debug("Failed to parse .o file: {s}", .{o_file});
            continue;
        };

        // .o files can be relocated in main executable
        // Calculate offset of .o file in main executable
        const o_file_offset = calcOFileOffset(parsed_exec, parsed_obj_file);
        for (di.debug_info_entries) |entry| {
            defer filenames_map.clearRetainingCapacity();

            if (entry.tag_id != DW.TAG.compile_unit) continue;

            const comp_dir_attr = entry.getAttr(DW.AT.comp_dir) orelse debug.panic("Cannot retrieve compilation directory", .{});
            const comp_dir = comp_dir_attr.value.getString(&di) catch |err| debug.panic("Cannot retrieve copilation dir value: {}", .{err});

            var prog = di.getLineNumberProgram(scratch, entry) catch |err|
                debug.panic("Couldnt get line number information: {}", .{err});

            while (prog.hasNext()) {
                defer _ = loop_arena.reset(.retain_capacity);

                const line = prog.next() catch |err| debug.panic("Cannot read line number information: {}", .{err}) orelse continue;
                if (line.line == 0) continue;
                // TODO:: is this always line.file - 1 ? or is it DWARF5 (or DWARF4?) thing? i dont remember
                const file = prog.files.items[line.file - 1];
                const dir = prog.directories.items[file.dir_index].path;

                const fullpath = path: {
                    if (path.isAbsolute(dir)) {
                        break :path std.mem.concat(loop, u8, &.{ dir, path.sep_str, file.path }) catch unreachable;
                    }

                    break :path std.mem.concat(loop, u8, &.{ comp_dir, path.sep_str, dir, path.sep_str, file.path }) catch unreachable;
                };
                if (!hasIncludePath(include_paths, fullpath)) {
                    continue;
                }
                const source_file_id = id: {
                    if (source_files_map.get(.{ .path = fullpath })) |id| {
                        break :id id;
                    }

                    const new_source_file = SourceFile{ .path = ctx.arena.dupe(u8, fullpath) catch unreachable };
                    logger.debug("Adding source file {}", .{fmt.SourceFilepathFmt{ .ctx = ctx, .source_file = new_source_file }});
                    const new_source_file_id: SourceFileId = @enumFromInt(source_files_map.count());
                    source_files_map.put(new_source_file, new_source_file_id) catch unreachable;
                    break :id new_source_file_id;
                };

                const result = line_info.getOrPut(.{
                    .source_file = source_file_id,
                    .line = @intCast(line.line),
                }) catch unreachable;
                if (!result.found_existing) {
                    result.value_ptr.* = .{
                        .source_file = source_file_id,
                        .line = @intCast(line.line),
                        .col = @intCast(line.col),
                        .address = line.address + o_file_offset,
                    };
                }
            }
        }
    }

    const source_files = ctx.arena.dupe(SourceFile, source_files_map.keys()) catch unreachable;
    return .{
        .source_files = source_files,
        .line_info = line_info,
    };
}

pub const MachOBinary = struct {
    obj_files: []const []const u8,
    symbols: []const Symbol,
    dwarf: ?Dwarf,
};

pub fn parseMachoBinary(scratch: std.mem.Allocator, filename: []const u8) error{FileNotFound}!MachOBinary {
    const file = std.fs.cwd().openFile(filename, .{}) catch |err| switch (err) {
        error.FileNotFound => return error.FileNotFound,
        else => debug.panic("Cannot open file {s}: {}", .{ filename, err }),
    };
    const content = file.readToEndAlloc(scratch, std.math.maxInt(u32)) catch |err| debug.panic("Cannot load file {s}: {}", .{ filename, err });

    const header = std.mem.bytesToValue(macho.MachOHeader64, content);
    if (header.magic != macho.MH_MAGIC_64) {
        debug.panic("Unsupported binary", .{});
    }

    var it = macho.LoadCommandIterator{
        .ncmds = header.ncmds,
        .buf = content[@sizeOf(macho.MachOHeader64)..],
    };

    var obj_files = std.ArrayList([]const u8).init(scratch);
    var symbols = std.ArrayList(Symbol).init(scratch);
    var sections = std.EnumArray(Dwarf.SectionId, ?Dwarf.Section).initFill(null);
    while (it.next()) |*lc| {
        switch (lc.hdr.cmd) {
            .segment_64 => {
                for (lc.getSections()) |sect| {
                    if (std.mem.eql(u8, "__DWARF", sect.segName())) {
                        parseDwarfSection(scratch, content, &sections, sect);
                    }
                }
            },
            .symtab => {
                const symtab_cmd = std.mem.bytesToValue(macho.SymtabCommand, lc.data);
                const symtab = lc.getSymtab(content);
                const strtab = content[symtab_cmd.stroff..][0..symtab_cmd.strsize];
                for (symtab) |sym| {
                    if (sym.n_type & macho.N_SECT != 0) {
                        const name = std.mem.sliceTo(strtab[sym.n_strx..], 0);
                        symbols.append(.{
                            .name = name,
                            .address = sym.n_value,
                        }) catch unreachable;
                    }
                    if (sym.stab()) {
                        if (sym.n_type == macho.N_OSO) {
                            const sym_name = std.mem.sliceTo(strtab[sym.n_strx..], 0);
                            const o_file_path = getOFilepath(scratch, filename, sym_name);
                            obj_files.append(o_file_path) catch unreachable;
                        }
                    }
                }
            },
            else => {},
        }
    }

    const dwarf = Dwarf.init(scratch, sections) catch |err| switch (err) {
        error.NoDebugInfoSection, error.NoDebugAbbrevSection => null,
        else => debug.panic("Cannot parse dwarf info: {}", .{err}),
    };

    return MachOBinary{
        .obj_files = obj_files.toOwnedSlice() catch unreachable,
        .symbols = symbols.toOwnedSlice() catch unreachable,
        .dwarf = dwarf,
    };
}

pub fn calcOFileOffset(parsed_exec: MachOBinary, parsed_obj_file: MachOBinary) usize {
    for (parsed_obj_file.symbols) |sym| {
        for (parsed_exec.symbols) |exec_sym| {
            if (std.mem.eql(u8, sym.name, exec_sym.name)) {
                logger.debug("Found matching symbols: {} and {}", .{ sym, exec_sym });
                return exec_sym.address - sym.address - PAGEZERO_OFFSET;
            }
        }
    }

    debug.panic("Cannot find offset", .{});
}

pub fn getOFilepath(scratch: std.mem.Allocator, binary_filepath: []const u8, sym_name: []const u8) []const u8 {
    var filename = path.basename(sym_name);
    // If parenthesis - then path to .o file is in parenthesis
    if (std.mem.indexOf(u8, filename, "(")) |index| {
        const closing_paren_index = std.mem.indexOf(u8, filename[index..], ")").?;
        filename = filename[index + 1 ..][0 .. closing_paren_index - 1];
    }

    const sym_dirpath = path.dirname(sym_name) orelse "";
    if (std.mem.startsWith(u8, sym_name, "/")) {
        return path.join(scratch, &.{ sym_dirpath, filename }) catch unreachable;
    }

    if (path.dirname(binary_filepath)) |binary_dir| {
        return path.join(scratch, &.{ binary_dir, filename }) catch unreachable;
    }

    return scratch.dupe(u8, filename) catch unreachable;
}

pub const Symbol = struct {
    name: []const u8,
    address: usize,

    pub fn format(self: Symbol, comptime text: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = text;
        _ = options;
        try writer.print("Symbol{{ .name = {s}, .address = 0x{x} }}", .{ self.name, self.address });
    }
};

pub fn parseDwarfSection(scratch: std.mem.Allocator, content: []const u8, sections: *std.EnumArray(Dwarf.SectionId, ?Dwarf.Section), sect: macho.Section64) void {
    var section_index: ?usize = null;
    inline for (@typeInfo(Dwarf.SectionId).@"enum".fields, 0..) |section, i| {
        if (std.mem.eql(u8, "__" ++ section.name, sect.sectName())) section_index = i;
    }
    if (section_index == null) {
        return;
    }

    const section_bytes = content[sect.offset..][0..sect.size];
    sections.set(@enumFromInt(section_index.?), Dwarf.Section{
        .data = scratch.dupeZ(u8, section_bytes) catch unreachable,
    });
}

fn hasIncludePath(include_paths: []const []const u8, dir: []const u8) bool {
    for (include_paths) |include_path| {
        if (std.mem.indexOf(u8, dir, include_path) != null) {
            return true;
        }
    }
    return false;
}
