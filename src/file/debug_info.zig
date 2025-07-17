const std = @import("std");
const path = std.fs.path;
const panic = std.debug.panic;
const builtin = @import("builtin");
const native_endian = builtin.cpu.arch.endian();
const core = @import("../core.zig");
const macho = @import("./macho.zig");
const Dwarf = @import("./dwarf.zig");
const DW = @import("./dwarf.zig").DW;
const SectionId = @import("./dwarf.zig").SectionId;
const Section = @import("./dwarf.zig").Section;

const DebugInfo = @This();

source_files: []core.SourceFile,
line_info: core.LineInfoMap,

pub fn init(ctx: *core.Context, exec_file: []const u8, include_mode: core.IncludeMode) DebugInfo {
    var scratch_arena = std.heap.ArenaAllocator.init(ctx.gpa);
    defer scratch_arena.deinit();
    const scratch = scratch_arena.allocator();

    var source_files_map = std.ArrayHashMap(core.SourceFile, core.SourceFileId, core.SourceFile.Context, false).init(scratch);
    var line_info = core.LineInfoMap.init(ctx.arena);

    var dwarfs = std.ArrayList(Dwarf).init(scratch);
    const parsed_exec = parseMachoBinary(scratch, exec_file);
    std.log.debug(".o file count: {d}", .{parsed_exec.o_files.len});
    if (parsed_exec.dwarf) |d| {
        dwarfs.append(d) catch unreachable;
    }

    for (parsed_exec.o_files) |o_file| {
        std.log.debug("Parsing .o file: {s}", .{o_file});
        if (getObjectFileDwarf(scratch, o_file)) |dwarf| {
            dwarfs.append(dwarf) catch unreachable;
        } else {
            std.log.debug("Failed to parse .o file: {s}", .{o_file});
        }
    }

    std.log.debug("DIE count: {d}", .{dwarfs.items.len});

    var filenames_map = std.AutoArrayHashMap(struct { dir: u32, file: u32 }, core.SourceFileId).init(scratch);
    for (dwarfs.items) |*di| {
        for (di.debug_info_entries) |entry| {
            defer filenames_map.clearRetainingCapacity();

            if (entry.tag_id != DW.TAG.compile_unit) continue;

            const comp_dir_attr = entry.getAttr(DW.AT.comp_dir) orelse panic("Cannot retrieve compilation directory", .{});
            const comp_dir = comp_dir_attr.value.getString(di) catch |err| panic("Cannot retrieve copilation dir value: {}", .{err});

            var prog = di.getLineNumberProgram(scratch, parsed_exec.vmaddr_offset, entry) catch |err|
                panic("Couldnt get line number information: {}", .{err});

            while (prog.hasNext()) {
                const line = prog.next() catch |err| panic("Cannot read line number information: {}", .{err}) orelse continue;
                if (line.line == 0) continue;
                // TODO:: is this always line.file - 1 ? or is it DWARF5 (or DWARF4?) thing? i dont remember
                const file = prog.files.items[line.file - 1];
                var dir_path = prog.directories.items[file.dir_index].path;
                if (!path.isAbsolute(dir_path)) {
                    dir_path = path.join(ctx.arena, &.{ comp_dir, dir_path }) catch unreachable;
                }
                if (include_mode == .only_comp_dir and !std.mem.startsWith(u8, dir_path, comp_dir)) {
                    continue;
                }
                const dir = prog.directories.items[file.dir_index].path;
                const source_file_id = id: {
                    if (source_files_map.get(.{ .comp_dir = comp_dir, .dir = dir, .filename = file.path })) |id| {
                        break :id id;
                    }

                    std.log.debug("Adding source file {s}/{s}", .{ dir, file.path });
                    const new_source_file_id: core.SourceFileId = @enumFromInt(source_files_map.count());
                    source_files_map.put(.{
                        .comp_dir = ctx.arena.dupe(u8, comp_dir) catch unreachable,
                        .dir = ctx.arena.dupe(u8, dir) catch unreachable,
                        .filename = ctx.arena.dupe(u8, file.path) catch unreachable,
                    }, new_source_file_id) catch unreachable;
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
                        .address = line.address,
                    };
                }
            }
        }
    }

    const source_files = ctx.arena.dupe(core.SourceFile, source_files_map.keys()) catch unreachable;
    return .{
        .source_files = source_files,
        .line_info = line_info,
    };
}

pub const ParsedExec = struct {
    vmaddr_offset: usize,
    o_files: []const []const u8,
    dwarf: ?Dwarf,
};

pub fn parseMachoBinary(scratch: std.mem.Allocator, filename: []const u8) ParsedExec {
    const file = std.fs.cwd().openFile(filename, .{}) catch |err| panic("Cannot open file {s}: {}", .{ filename, err });
    const content = file.readToEndAlloc(scratch, std.math.maxInt(u32)) catch |err| panic("Cannot load file {s}: {}", .{ filename, err });

    const header = std.mem.bytesToValue(macho.MachOHeader64, content);
    if (header.magic != macho.MH_MAGIC_64) {
        panic("Unsupported binary", .{});
    }

    var it = macho.LoadCommandIterator{
        .ncmds = header.ncmds,
        .buf = content[@sizeOf(macho.MachOHeader64)..],
    };

    var o_files = std.ArrayList([]const u8).init(scratch);
    var vmaddr_base: ?usize = null;
    var sections = std.EnumArray(Dwarf.SectionId, ?Dwarf.Section).initFill(null);
    while (it.next()) |*lc| {
        switch (lc.hdr.cmd) {
            .segment_64 => {
                for (lc.getSections()) |sect| {
                    if (std.mem.eql(u8, "__TEXT", sect.segName()) and std.mem.eql(u8, "__text", sect.sectName())) {
                        vmaddr_base = sect.offset;
                    }

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
                    if (sym.stab() and sym.n_type == macho.N_OSO) {
                        const sym_name = std.mem.sliceTo(strtab[sym.n_strx..], 0);
                        const o_file_path = getOFilepath(scratch, filename, sym_name);
                        o_files.append(o_file_path) catch unreachable;
                    }
                }
            },
            else => {},
        }
    }

    const dwarf = Dwarf.init(scratch, sections) catch |err| switch (err) {
        error.NoDebugInfoSection, error.NoDebugAbbrevSection => null,
        else => panic("Cannot parse dwarf info: {}", .{err}),
    };

    return ParsedExec{
        .vmaddr_offset = vmaddr_base orelse panic("Failed to retrieve vmaddr_base", .{}),
        .o_files = o_files.toOwnedSlice() catch unreachable,
        .dwarf = dwarf,
    };
}

pub fn getOFilepath(scratch: std.mem.Allocator, exec_path: []const u8, sym_name: []const u8) []const u8 {
    if (std.mem.startsWith(u8, sym_name, "/")) {
        // FIXME: Fix parsing
        // OSO name can be like "/Users/ownelek/.cache/zig/o/0c1df40e33f4fc80145a07f5ebcb2c57/libcompiler_rt.a(libcompiler_rt.a.o)"
        // Do we need to check both files ? not sure whats the format here
        return scratch.dupe(u8, sym_name) catch unreachable;
    }

    if (path.dirname(exec_path)) |exec_dir| {
        return path.join(scratch, &.{ exec_dir, sym_name }) catch unreachable;
    }

    return scratch.dupe(u8, sym_name) catch unreachable;
}

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

fn getObjectFileDwarf(scratch: std.mem.Allocator, o_file: []const u8) ?Dwarf {
    var sections = std.EnumArray(SectionId, ?Section).initUndefined();
    const file = std.fs.cwd().openFile(o_file, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => panic("Cannot open object file {s}: {}", .{ o_file, err }),
    };
    const content = file.readToEndAlloc(scratch, std.math.maxInt(u32)) catch |err| panic("Cannot read object file: {s}: {}", .{ o_file, err });

    const header = std.mem.bytesToValue(macho.MachOHeader64, content);
    var it = macho.LoadCommandIterator{
        .buf = content[@sizeOf(macho.MachOHeader64)..],
        .ncmds = header.ncmds,
    };

    while (it.next()) |lc| {
        switch (lc.hdr.cmd) {
            .segment_64 => {
                for (lc.getSections()) |sect| {
                    if (!std.mem.eql(u8, "__DWARF", sect.segName())) continue;

                    parseDwarfSection(scratch, content, &sections, sect);
                }
            },
            else => {},
        }
    }

    return Dwarf.init(scratch, sections) catch |err| switch (err) {
        error.NoDebugInfoSection, error.NoDebugAbbrevSection => null,
        else => panic("Failed to read DWARF info: {}", .{err}),
    };
}
