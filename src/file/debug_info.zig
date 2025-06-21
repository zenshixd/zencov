const std = @import("std");
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

pub fn init(vmaddr_base: usize, exec_file: []const u8) DebugInfo {
    var temp_arena = std.heap.ArenaAllocator.init(core.gpa);
    defer temp_arena.deinit();

    var source_files_map = std.AutoArrayHashMap(core.SourceFile, core.SourceFileId).init(temp_arena.allocator());
    var line_info = core.LineInfoMap.init(core.arena);

    var dwarfs = std.ArrayList(Dwarf).init(temp_arena.allocator());
    const parsed_exec = parseMachoBinary(temp_arena.allocator(), exec_file);
    if (parsed_exec.dwarf) |d| {
        dwarfs.append(d) catch unreachable;
    }

    for (parsed_exec.o_files) |o_file| {
        if (getObjectFileDwarf(temp_arena.allocator(), o_file)) |dwarf| {
            dwarfs.append(dwarf) catch unreachable;
        }
    }

    var filenames_map = std.AutoArrayHashMap(struct { dir: u32, file: u32 }, core.SourceFileId).init(temp_arena.allocator());
    for (dwarfs.items) |*di| {
        for (di.debug_info_entries) |entry| {
            defer filenames_map.clearRetainingCapacity();

            if (entry.tag_id != DW.TAG.compile_unit) continue;

            const comp_dir_attr = entry.getAttr(DW.AT.comp_dir) orelse panic("Cannot retrieve compilation directory", .{});
            const comp_dir = comp_dir_attr.value.getString(di) catch |err| panic("Cannot retrieve copilation dir value: {}", .{err});
            const comp_dir_id = core.string_interner.intern(comp_dir);

            var prog = di.getLineNumberProgram(temp_arena.allocator(), vmaddr_base + parsed_exec.vmaddr_offset, entry) catch |err|
                panic("Couldnt get line number information: {}", .{err});

            while (prog.hasNext()) {
                const line = prog.next() catch |err| panic("Cannot read line number information: {}", .{err}) orelse continue;
                // TODO:: is this always line.file - 1 ? or is it DWARF5 (or DWARF4?) thing? i dont remember
                const file = prog.files.items[line.file - 1];
                const dir = core.string_interner.intern(prog.directories.items[file.dir_index].path);
                const filename = core.string_interner.intern(file.path);
                const source_file = source_files_map.getOrPut(.{
                    .comp_dir = comp_dir_id,
                    .dir = dir,
                    .filename = filename,
                }) catch unreachable;

                if (!source_file.found_existing) {
                    source_file.value_ptr.* = @enumFromInt(source_files_map.count() - 1);
                }

                const result = line_info.getOrPut(.{
                    .source_file = source_file.value_ptr.*,
                    .line = @intCast(line.line),
                }) catch unreachable;
                if (!result.found_existing) {
                    result.value_ptr.* = .{
                        .source_file = source_file.value_ptr.*,
                        .line = @intCast(line.line),
                        .col = @intCast(line.col),
                        .address = line.address,
                    };
                }
            }
        }
    }

    // We are not going to be interning files later, so we swapping to array is better
    const source_files = core.arena.alloc(core.SourceFile, source_files_map.count()) catch unreachable;
    for (source_files_map.keys(), 0..) |key, i| {
        source_files[i] = key;
    }
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

pub fn parseMachoBinary(arena: std.mem.Allocator, filename: []const u8) ParsedExec {
    const file = std.fs.cwd().openFile(filename, .{}) catch |err| panic("Cannot open file {s}: {}", .{ filename, err });
    const content = file.readToEndAlloc(core.gpa, std.math.maxInt(u32)) catch |err| panic("Cannot load file {s}: {}", .{ filename, err });
    defer core.gpa.free(content);

    const header = std.mem.bytesToValue(macho.MachOHeader64, content);
    if (header.magic != macho.MH_MAGIC_64) {
        panic("Unsupported binary", .{});
    }

    var it = macho.LoadCommandIterator{
        .ncmds = header.ncmds,
        .buf = content[@sizeOf(macho.MachOHeader64)..],
    };

    var o_files = std.ArrayListUnmanaged([]const u8).empty;
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
                        parseDwarfSection(arena, content, &sections, sect);
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
                        o_files.append(arena, arena.dupe(u8, sym_name) catch unreachable) catch unreachable;
                    }
                }
            },
            else => {},
        }
    }

    const dwarf = Dwarf.init(arena, sections) catch |err| switch (err) {
        error.NoDebugInfoSection, error.NoDebugAbbrevSection => null,
        else => panic("Cannot parse dwarf info: {}", .{err}),
    };

    return ParsedExec{
        .vmaddr_offset = vmaddr_base orelse panic("Failed to retrieve vmaddr_base", .{}),
        .o_files = o_files.toOwnedSlice(arena) catch unreachable,
        .dwarf = dwarf,
    };
}

pub fn parseDwarfSection(arena: std.mem.Allocator, content: []const u8, sections: *std.EnumArray(Dwarf.SectionId, ?Dwarf.Section), sect: macho.Section64) void {
    var section_index: ?usize = null;
    inline for (@typeInfo(Dwarf.SectionId).@"enum".fields, 0..) |section, i| {
        if (std.mem.eql(u8, "__" ++ section.name, sect.sectName())) section_index = i;
    }
    if (section_index == null) {
        return;
    }

    const section_bytes = content[sect.offset..][0..sect.size];
    sections.set(@enumFromInt(section_index.?), Dwarf.Section{
        .data = arena.dupeZ(u8, section_bytes) catch unreachable,
    });
}

fn getObjectFileDwarf(arena: std.mem.Allocator, o_file: []const u8) ?Dwarf {
    var sections = std.EnumArray(SectionId, ?Section).initUndefined();
    const file = std.fs.cwd().openFile(o_file, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => panic("Cannot open object file {s}: {}", .{ o_file, err }),
    };
    const content = file.readToEndAlloc(core.gpa, std.math.maxInt(u32)) catch |err| panic("Cannot read object file: {s}: {}", .{ o_file, err });
    defer core.gpa.free(content);

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

                    parseDwarfSection(arena, content, &sections, sect);
                }
            },
            else => {},
        }
    }

    return Dwarf.init(arena, sections) catch |err| switch (err) {
        error.NoDebugInfoSection, error.NoDebugAbbrevSection => null,
        else => panic("Failed to read DWARF info: {}", .{err}),
    };
}
