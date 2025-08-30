const std = @import("std");
const core = @import("../core.zig");
const debug = @import("../core/debug.zig");
const mem = @import("../core/mem.zig");
const builtin = @import("builtin");
const native_endian = builtin.cpu.arch.endian();

const io = @import("../core/io.zig");
const heap = @import("../core/heap.zig");

const Dwarf = @This();

pub const DwarfFormat = enum {
    bit32,
    bit64,
};

pub const DW = struct {
    pub const UT = enum(u8) {
        compile = 0x01,
        type = 0x02,
        partial = 0x03,
        skeleton = 0x04,
        split_compile = 0x05,
        split_type = 0x06,

        lo_user = 0x80,
        hi_user = 0xff,
        _,
    };

    pub const TAG = enum(u64) {
        array_type = 0x01,
        class_type = 0x02,
        entry_point = 0x03,
        enumeration_type = 0x04,
        formal_parameter = 0x05,
        imported_declaration = 0x08,
        label = 0x0a,
        lexical_block = 0x0b,
        member = 0x0d,
        pointer_type = 0x0f,
        reference_type = 0x10,
        compile_unit = 0x11,
        string_type = 0x12,
        structure_type = 0x13,
        subroutine_type = 0x15,
        typedef = 0x16,
        union_type = 0x17,
        unspecified_parameters = 0x18,
        variant = 0x19,
        common_block = 0x1a,
        common_inclusion = 0x1b,
        inheritance = 0x1c,
        inlined_subroutine = 0x1d,
        module = 0x1e,
        ptr_to_member_type = 0x1f,
        set_type = 0x20,
        subrange_type = 0x21,
        with_stmt = 0x22,
        access_declaration = 0x23,
        base_type = 0x24,
        catch_block = 0x25,
        const_type = 0x26,
        constant = 0x27,
        enumerator = 0x28,
        file_type = 0x29,
        friend = 0x2a,
        namelist = 0x2b,
        namelist_item = 0x2c,
        packed_type = 0x2d,
        subprogram = 0x2e,
        template_type_parameter = 0x2f,
        template_value_parameter = 0x30,
        thrown_type = 0x31,
        try_block = 0x32,
        variant_part = 0x33,
        variable = 0x34,
        volatile_type = 0x35,
        dwarf_procedure = 0x36,
        restrict_type = 0x37,
        interface_type = 0x38,
        namespace = 0x39,
        imported_module = 0x3a,
        unspecified_type = 0x3b,
        partial_unit = 0x3c,
        imported_unit = 0x3d,
        condition = 0x3f,
        shared_type = 0x40,
        type_unit = 0x41,
        rvalue_reference_type = 0x42,
        template_alias = 0x43,
        coarray_type = 0x44,
        generic_subrange = 0x45,
        dynamic_type = 0x46,
        atomic_type = 0x47,
        call_site = 0x48,
        call_site_parameter = 0x49,
        skeleton_unit = 0x4a,
        immutable_type = 0x4b,
        lo_user = 0x4080,
        hi_user = 0xffff,
        _,
    };

    pub const CHILDREN = enum(u8) {
        no = 0x00,
        yes = 0x01,
    };

    pub const FORM = enum(u64) {
        addr = 0x01,
        block2 = 0x03,
        block4 = 0x04,
        data2 = 0x05,
        data4 = 0x06,
        data8 = 0x07,
        string = 0x08,
        block = 0x09,
        block1 = 0x0a,
        data1 = 0x0b,
        flag = 0x0c,
        sdata = 0x0d,
        strp = 0x0e,
        udata = 0x0f,
        ref_addr = 0x10,
        ref1 = 0x11,
        ref2 = 0x12,
        ref4 = 0x13,
        ref8 = 0x14,
        ref_udata = 0x15,
        indirect = 0x16,
        sec_offset = 0x17,
        exprloc = 0x18,
        flag_present = 0x19,
        strx = 0x1a,
        addrx = 0x1b,
        ref_sup4 = 0x1c,
        strp_sup = 0x1d,
        data16 = 0x1e,
        line_strp = 0x1f,
        ref_sig8 = 0x20,
        implicit_const = 0x21,
        loclistx = 0x22,
        rnglistx = 0x23,
        ref_sup8 = 0x24,
        strx1 = 0x25,
        strx2 = 0x26,
        strx3 = 0x27,
        strx4 = 0x28,
        addrx1 = 0x29,
        addrx2 = 0x2a,
        addrx3 = 0x2b,
        addrx4 = 0x2c,
        _,
    };

    pub const AT = enum(u64) {
        sibling = 0x01,
        location = 0x02,
        name = 0x03,
        ordering = 0x09,
        byte_size = 0x0b,
        bit_size = 0x0d,
        stmt_list = 0x10,
        low_pc = 0x11,
        high_pc = 0x12,
        language = 0x13,
        discr = 0x15,
        discr_value = 0x16,
        visibility = 0x17,
        import = 0x18,
        string_length = 0x19,
        common_reference = 0x1a,
        comp_dir = 0x1b,
        const_value = 0x1c,
        containing_type = 0x1d,
        default_value = 0x1e,
        @"inline" = 0x20,
        is_optional = 0x21,
        lower_bound = 0x22,
        producer = 0x25,
        prototyped = 0x27,
        return_addr = 0x2a,
        start_scope = 0x2c,
        bit_stride = 0x2e,
        upper_bound = 0x2f,
        abstract_origin = 0x31,
        accessibility = 0x32,
        address_class = 0x33,
        artificial = 0x34,
        base_types = 0x35,
        calling_convention = 0x36,
        count = 0x37,
        data_member_location = 0x38,
        decl_column = 0x39,
        decl_file = 0x3a,
        decl_line = 0x3b,
        declaration = 0x3c,
        discr_list = 0x3d,
        encoding = 0x3e,
        external = 0x3f,
        frame_base = 0x40,
        friend = 0x41,
        identifier_case = 0x42,
        namelist_item = 0x44,
        priority = 0x45,
        segment = 0x46,
        specification = 0x47,
        static_link = 0x48,
        type = 0x49,
        use_location = 0x4a,
        variable_parameter = 0x4b,
        virtuality = 0x4c,
        vtable_elem_location = 0x4d,
        allocated = 0x4e,
        associated = 0x4f,
        data_location = 0x50,
        byte_stride = 0x51,
        entry_pc = 0x52,
        use_UTF8 = 0x53,
        extension = 0x54,
        ranges = 0x55,
        trampoline = 0x56,
        call_column = 0x57,
        call_file = 0x58,
        call_line = 0x59,
        description = 0x5a,
        binary_scale = 0x5b,
        decimal_scale = 0x5c,
        small = 0x5d,
        decimal_sign = 0x5e,
        digit_count = 0x5f,
        picture_string = 0x60,
        mutable = 0x61,
        threads_scaled = 0x62,
        explicit = 0x63,
        object_pointer = 0x64,
        endianity = 0x65,
        elemental = 0x66,
        pure = 0x67,
        recursive = 0x68,
        signature = 0x69,
        main_subprogram = 0x6a,
        data_bit_offset = 0x6b,
        const_expr = 0x6c,
        enum_class = 0x6d,
        linkage_name = 0x6e,
        string_length_bit_size = 0x6f,
        string_length_byte_size = 0x70,
        rank = 0x71,
        str_offsets_base = 0x72,
        addr_base = 0x73,
        rnglists_base = 0x74,
        dwo_name = 0x76,
        reference = 0x77,
        rvalue_reference = 0x78,
        macros = 0x79,
        call_all_calls = 0x7a,
        call_all_source_calls = 0x7b,
        call_all_tail_calls = 0x7c,
        call_return_pc = 0x7d,
        call_value = 0x7e,
        call_origin = 0x7f,
        call_parameter = 0x80,
        call_pc = 0x81,
        call_tail_call = 0x82,
        call_target = 0x83,
        call_target_clobbered = 0x84,
        call_data_location = 0x85,
        call_data_value = 0x86,
        noreturn = 0x87,
        alignment = 0x88,
        export_symbols = 0x89,
        deleted = 0x8a,
        defaulted = 0x8b,
        loclists_base = 0x8c,
        lo_user = 0x2000,
        hi_user = 0x3fff,
        _,
    };

    pub const AT_Value = union(enum) {
        addr: u64,
        addrx: usize,
        block: []const u8,
        udata: u64,
        data16: *const [16]u8,
        sdata: i64,
        exprloc: []const u8,
        flag: bool,
        sec_offset: u64,
        ref: u64,
        ref_addr: u64,
        string: [:0]const u8,
        strp: u64,
        strx: usize,
        line_strp: u64,
        loclistx: u64,
        rnglistx: u64,

        pub fn getString(self: AT_Value, di: *Dwarf) ![:0]const u8 {
            switch (self) {
                .string => |s| return s,
                .strp => |off| return di.getString(off),
                .line_strp => |off| return di.getLineString(off),
                else => return error.BadAttribute,
            }
        }

        pub fn getUInt(self: AT_Value, comptime U: type) !U {
            return switch (self) {
                inline .udata,
                .sdata,
                .sec_offset,
                => |c| @as(U, @intCast(c)),
                else => return error.BadAttribute,
            };
        }
    };

    pub const LNCT = enum(u64) {
        path = 0x1,
        directory_index = 0x2,
        timestamp = 0x3,
        size = 0x4,
        MD5 = 0x5,

        lo_user = 0x2000,
        hi_user = 0x3fff,

        LLVM_source = 0x2001,
        _,
    };

    pub const LNS = enum(u64) {
        extended_op = 0,
        copy,
        advance_pc,
        advance_line,
        set_file,
        set_column,
        negate_stmt,
        set_basic_block,
        const_add_pc,
        fixed_advance_pc,
        set_prologue_end,
        set_epilogue_begin,
        set_isa,
        _,
    };

    pub const LNE = enum(u64) {
        end_sequence = 1,
        set_address,
        define_file,
        set_discriminator,
        _,
    };
};

pub const UnitHeader = struct {
    format: DwarfFormat,
    header_length: u4,
    unit_length: u64,
};

pub const DebugInfoEntry = struct {
    tag_id: DW.TAG,
    attrs: []Attr,
    children: []DebugInfoEntry,

    pub const Attr = struct {
        id: DW.AT,
        form_id: DW.FORM,
        value: DW.AT_Value,
    };

    pub fn deinit(self: *DebugInfoEntry, gpa: heap.Allocator) void {
        gpa.free(self.attrs);
        for (self.children) |*child_die| {
            child_die.deinit(gpa);
        }
        gpa.free(self.children);
    }

    pub fn getAttr(self: DebugInfoEntry, id: DW.AT) ?Attr {
        for (self.attrs) |attr| {
            if (attr.id == id) return attr;
        }
        return null;
    }

    pub fn getAttrLinePtr(self: DebugInfoEntry, id: DW.AT) !u64 {
        const attr = self.getAttr(id) orelse return error.MissingDebugInfo;
        return switch (attr.value) {
            .sec_offset => |offset| offset,
            else => error.InvalidAttributeForm,
        };
    }
};

pub const Abbrev = struct {
    code: u64,
    tag_id: DW.TAG,
    has_children: DW.CHILDREN,
    attrs: []Attr,

    fn deinit(abbrev: *Abbrev, allocator: heap.Allocator) void {
        allocator.free(abbrev.attrs);
        abbrev.* = undefined;
    }

    const Attr = struct {
        id: DW.AT,
        form_id: DW.FORM,
        /// Only valid if form_id is .implicit_const
        payload: i64,
    };
};

pub const SectionId = enum {
    debug_info,
    debug_abbrev,
    debug_str,
    debug_str_offs,
    debug_line,
    debug_line_str,
};

pub const Section = struct {
    data: [:0]const u8,
};

sections: std.EnumArray(SectionId, ?Section),
abbrevs: []Abbrev,
debug_info_entries: []DebugInfoEntry,

pub fn init(gpa: heap.Allocator, sections: std.EnumArray(SectionId, ?Section)) error{
    NoDebugInfoSection,
    NoDebugAbbrevSection,
    InvalidDebugInfo,
    UnexpectedDebugInfoEnd,
    UnexpectedAbbrevTableEnd,
}!Dwarf {
    const section = sections.get(.debug_info) orelse return error.NoDebugInfoSection;
    var fbr = io.Source.fixed(section.data);
    const abbrevs = try parseAbbrevTable(sections, gpa);
    return Dwarf{
        .sections = sections,
        .abbrevs = abbrevs,
        .debug_info_entries = try parseDebugInfoEntries(&fbr, abbrevs, gpa),
    };
}

pub fn deinit(self: *Dwarf, gpa: heap.Allocator) void {
    for (self.sections.values) |maybe_section| {
        if (maybe_section) |section| {
            gpa.free(section.data);
        }
    }
    for (self.debug_info_entries) |*entry| {
        entry.deinit(gpa);
    }
    gpa.free(self.debug_info_entries);

    for (self.abbrevs) |*abbrev| {
        abbrev.deinit(gpa);
    }
    gpa.free(self.abbrevs);
}

pub fn getString(di: Dwarf, offset: u64) error{NoDebugStrSection}![:0]const u8 {
    const section = di.sections.get(.debug_str) orelse return error.NoDebugStrSection;
    return mem.sliceTo(section.data[offset..], 0);
}

pub fn getLineString(di: Dwarf, offset: u64) error{NoDebugLineStrSection}![:0]const u8 {
    const section = di.sections.get(.debug_line_str) orelse return error.NoDebugLineStrSection;
    return mem.sliceTo(section.data[offset..], 0);
}

pub fn readUnitHeader(fbr: *io.Source) error{ EndOfBuffer, InvalidHeaderLen }!UnitHeader {
    return switch (fbr.readInt(u32) catch return error.EndOfBuffer) {
        0...0xfffffff0 - 1 => |unit_length| .{
            .format = .bit32,
            .header_length = 4,
            .unit_length = unit_length,
        },
        0xfffffff0...0xffffffff - 1 => error.InvalidHeaderLen,
        0xffffffff => .{
            .format = .bit64,
            .header_length = 12,
            .unit_length = fbr.readInt(u64) catch return error.EndOfBuffer,
        },
    };
}
pub fn parseAbbrevTable(sections: std.EnumArray(SectionId, ?Section), gpa: heap.Allocator) error{ NoDebugAbbrevSection, UnexpectedAbbrevTableEnd }![]Abbrev {
    const section = sections.get(.debug_abbrev) orelse return error.NoDebugAbbrevSection;
    var fbr = io.Source.fixed(section.data);
    var abbrevs = std.ArrayListUnmanaged(Abbrev).empty;

    while (true) {
        const code = fbr.readUleb128(u64) catch return error.UnexpectedAbbrevTableEnd;
        if (code == 0) break;
        const tag = fbr.readUleb128(u64) catch return error.UnexpectedAbbrevTableEnd;
        const has_children = fbr.readInt(u8) catch return error.UnexpectedAbbrevTableEnd;
        var attrs = std.ArrayListUnmanaged(Abbrev.Attr).empty;

        while (true) {
            const attr_id = fbr.readUleb128(u64) catch return error.UnexpectedAbbrevTableEnd;
            const form_id = fbr.readUleb128(u64) catch return error.UnexpectedAbbrevTableEnd;
            if (attr_id == 0 and form_id == 0) break;
            attrs.append(gpa, .{
                .id = @enumFromInt(attr_id),
                .form_id = @enumFromInt(form_id),
                .payload = switch (form_id) {
                    @intFromEnum(DW.FORM.implicit_const) => fbr.readIleb128(i64) catch return error.UnexpectedAbbrevTableEnd,
                    else => undefined,
                },
            }) catch unreachable;
        }

        abbrevs.append(gpa, .{
            .code = code,
            .tag_id = @enumFromInt(tag),
            .has_children = @enumFromInt(has_children),
            .attrs = attrs.toOwnedSlice(gpa) catch unreachable,
        }) catch unreachable;
    }

    return abbrevs.toOwnedSlice(gpa) catch unreachable;
}

fn getAbbrevEntry(abbrevs: []Abbrev, code: u64) ?Abbrev {
    for (abbrevs) |abbrev| {
        if (abbrev.code == code) {
            return abbrev;
        }
    }

    return null;
}

pub fn parseDebugInfoEntries(fbr: *io.Source, abbrevs: []Abbrev, gpa: heap.Allocator) error{ UnexpectedDebugInfoEnd, InvalidDebugInfo }![]DebugInfoEntry {
    var debug_info_entries = core.ArrayList(DebugInfoEntry).empty;
    const unit_header = readUnitHeader(fbr) catch return error.UnexpectedDebugInfoEnd;
    const version = fbr.readInt(u16) catch return error.UnexpectedDebugInfoEnd;

    std.log.debug("Found debug info entry, version: {d}", .{version});
    // Order changes depending on version -.-
    const unit_type, const address_size, const debug_abbrev_offset = blk: {
        if (version >= 5) {
            const unit_type: DW.UT = @enumFromInt(fbr.readInt(u8) catch return error.UnexpectedDebugInfoEnd);
            const address_size = fbr.readInt(u8) catch return error.UnexpectedDebugInfoEnd;
            const debug_abbrev_offset = readAddress(fbr, unit_header.format) catch return error.UnexpectedDebugInfoEnd;
            break :blk .{ unit_type, address_size, debug_abbrev_offset };
        } else {
            const debug_abbrev_offset = readAddress(fbr, unit_header.format) catch return error.UnexpectedDebugInfoEnd;
            const address_size = fbr.readInt(u8) catch return error.UnexpectedDebugInfoEnd;
            break :blk .{ DW.UT.compile, address_size, debug_abbrev_offset };
        }
    };
    _ = unit_type;
    _ = address_size;
    _ = debug_abbrev_offset;
    while (try parseDebugInfoEntry(fbr, unit_header.format, abbrevs, gpa)) |die| {
        debug_info_entries.append(gpa, die) catch unreachable;
    }

    return debug_info_entries.toOwnedSlice(gpa) catch unreachable;
}

pub fn parseDebugInfoEntry(fbr: *io.Source, format: DwarfFormat, abbrevs: []Abbrev, gpa: heap.Allocator) error{ UnexpectedDebugInfoEnd, InvalidDebugInfo }!?DebugInfoEntry {
    if (fbr.pos >= fbr.buf.len) return null;
    const code = fbr.readUleb128(u64) catch return error.UnexpectedDebugInfoEnd;
    if (code == 0) return null;
    const entry = getAbbrevEntry(abbrevs, code) orelse return error.InvalidDebugInfo;

    var attrs = std.ArrayListUnmanaged(DebugInfoEntry.Attr).empty;
    for (entry.attrs) |attr| {
        attrs.append(gpa, .{
            .id = attr.id,
            .form_id = attr.form_id,
            .value = parseAttrValue(fbr, format, attr.form_id) catch return error.UnexpectedDebugInfoEnd,
        }) catch unreachable;
    }

    var child_entries = std.ArrayListUnmanaged(DebugInfoEntry).empty;
    if (entry.has_children == DW.CHILDREN.yes) {
        while (try parseDebugInfoEntry(fbr, format, abbrevs, gpa)) |child| {
            child_entries.append(gpa, child) catch unreachable;
        }
    }
    return DebugInfoEntry{
        .tag_id = entry.tag_id,
        .attrs = attrs.toOwnedSlice(gpa) catch unreachable,
        .children = child_entries.toOwnedSlice(gpa) catch unreachable,
    };
}

pub const FileEntryFormat = struct {
    content_type_code: DW.LNCT,
    form_code: DW.FORM,
};

pub const FileEntry = struct {
    path: []const u8,
    dir_index: u32 = 0,
    mtime: u64 = 0,
    size: u64 = 0,
    md5: [16]u8 = [1]u8{0} ** 16,

    pub fn format(self: FileEntry, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("FileEntry: {s}, dir_index: {}, mtime: {}, size: {}", .{ self.path, self.dir_index, self.mtime, self.size });
    }
};

pub fn getLineNumberProgram(di: *Dwarf, gpa: heap.Allocator, entry: DebugInfoEntry) error{ NoDebugLineSection, UnexpectedDebugLineSectionEnd }!LineNumberProgram {
    const debug_line_off = entry.getAttrLinePtr(DW.AT.stmt_list) catch unreachable;
    const section = di.sections.get(.debug_line) orelse return error.NoDebugLineSection;
    var fbr = io.Source{
        .buf = section.data,
        .endian = native_endian,
        .pos = debug_line_off,
    };

    const unit_header = readUnitHeader(&fbr) catch return error.UnexpectedDebugLineSectionEnd;
    const version = fbr.readInt(u16) catch return error.UnexpectedDebugLineSectionEnd;
    const address_size, const segment_size = blk: {
        if (version >= 5) {
            const address_size = fbr.readInt(u8) catch return error.UnexpectedDebugLineSectionEnd;
            const segment_size = fbr.readInt(u8) catch return error.UnexpectedDebugLineSectionEnd;
            break :blk .{ address_size, segment_size };
        } else {
            break :blk .{ 4, 0 };
        }
    };

    const header_length = readAddress(&fbr, unit_header.format) catch return error.UnexpectedDebugLineSectionEnd;
    const prog_start_off = fbr.pos + header_length;

    const minimum_instruction_length = fbr.readInt(u8) catch return error.UnexpectedDebugLineSectionEnd;
    const maximum_operations_per_instruction = fbr.readInt(u8) catch return error.UnexpectedDebugLineSectionEnd;
    const default_is_stmt = fbr.readInt(u8) catch return error.UnexpectedDebugLineSectionEnd;
    const line_base = fbr.readInt(i8) catch return error.UnexpectedDebugLineSectionEnd;
    const line_range = fbr.readInt(u8) catch return error.UnexpectedDebugLineSectionEnd;
    const opcode_base = fbr.readInt(u8) catch return error.UnexpectedDebugLineSectionEnd;
    const standard_opcode_lengths = fbr.readBytes(opcode_base - 1) catch return error.UnexpectedDebugLineSectionEnd;
    _ = address_size;
    _ = segment_size;
    _ = standard_opcode_lengths;

    var directories = std.ArrayListUnmanaged(FileEntry).empty;
    var files = std.ArrayListUnmanaged(FileEntry).empty;
    if (version < 5) {
        const comp_dir_attr = entry.getAttr(DW.AT.comp_dir) orelse debug.panic("Cannot retrieve compilation directory", .{});
        const comp_dir = comp_dir_attr.value.getString(di) catch |err| debug.panic("Cannot retrieve copilation dir value: {}", .{err});
        directories.append(gpa, .{ .path = comp_dir }) catch unreachable;
        while (true) {
            const directory = fbr.readBytesTo(0) catch return error.UnexpectedDebugLineSectionEnd;
            if (directory.len == 0) break;
            directories.append(gpa, .{ .path = directory }) catch unreachable;
        }
        while (true) {
            const file = fbr.readBytesTo(0) catch return error.UnexpectedDebugLineSectionEnd;
            if (file.len == 0) break;
            const dir_index = fbr.readUleb128(u32) catch return error.UnexpectedDebugLineSectionEnd;
            const mtime = fbr.readUleb128(u64) catch return error.UnexpectedDebugLineSectionEnd;
            const length = fbr.readUleb128(u64) catch return error.UnexpectedDebugLineSectionEnd;
            files.append(gpa, .{
                .path = file,
                .dir_index = dir_index,
                .mtime = mtime,
                .size = length,
            }) catch unreachable;
        }
    } else {
        const directory_entry_format_count = fbr.readInt(u8) catch return error.UnexpectedDebugLineSectionEnd;
        var directory_entry_formats = gpa.alloc(FileEntryFormat, directory_entry_format_count) catch unreachable;
        for (0..directory_entry_format_count) |i| {
            directory_entry_formats[i].content_type_code = @enumFromInt(fbr.readUleb128(u64) catch return error.UnexpectedDebugLineSectionEnd);
            directory_entry_formats[i].form_code = @enumFromInt(fbr.readUleb128(u64) catch return error.UnexpectedDebugLineSectionEnd);
        }
        const directory_count = fbr.readUleb128(usize) catch return error.UnexpectedDebugLineSectionEnd;
        for (0..directory_count) |_| {
            const dir_entry = directories.addOne(gpa) catch unreachable;
            for (directory_entry_formats) |fmt| {
                const val = parseAttrValue(&fbr, unit_header.format, fmt.form_code) catch return error.UnexpectedDebugLineSectionEnd;
                switch (fmt.content_type_code) {
                    DW.LNCT.path => dir_entry.path = val.getString(di) catch return error.UnexpectedDebugLineSectionEnd,
                    DW.LNCT.directory_index => dir_entry.dir_index = val.getUInt(u32) catch return error.UnexpectedDebugLineSectionEnd,
                    DW.LNCT.timestamp => dir_entry.mtime = val.getUInt(u64) catch return error.UnexpectedDebugLineSectionEnd,
                    DW.LNCT.size => dir_entry.size = val.getUInt(u64) catch return error.UnexpectedDebugLineSectionEnd,
                    DW.LNCT.MD5 => dir_entry.md5 = switch (val) {
                        .data16 => |data16| data16.*,
                        else => blk: {
                            std.log.debug("Invalid data type for DW.LNCT.MD5: {}", .{val});
                            break :blk .{0} ** 16;
                        },
                    },
                    else => continue,
                }
            }
        }
        const file_entry_format_count = fbr.readInt(u8) catch return error.UnexpectedDebugLineSectionEnd;
        var file_entry_formats = gpa.alloc(FileEntryFormat, file_entry_format_count) catch unreachable;
        for (0..file_entry_format_count) |i| {
            file_entry_formats[i].content_type_code = @enumFromInt(fbr.readUleb128(u64) catch return error.UnexpectedDebugLineSectionEnd);
            file_entry_formats[i].form_code = @enumFromInt(fbr.readUleb128(u64) catch return error.UnexpectedDebugLineSectionEnd);
        }
        const file_count = fbr.readUleb128(usize) catch return error.UnexpectedDebugLineSectionEnd;
        for (0..file_count) |_| {
            const file_entry = files.addOne(gpa) catch unreachable;
            for (file_entry_formats) |fmt| {
                const val = parseAttrValue(&fbr, unit_header.format, fmt.form_code) catch return error.UnexpectedDebugLineSectionEnd;
                switch (fmt.content_type_code) {
                    DW.LNCT.path => file_entry.path = val.getString(di) catch return error.UnexpectedDebugLineSectionEnd,
                    DW.LNCT.directory_index => file_entry.dir_index = val.getUInt(u32) catch return error.UnexpectedDebugLineSectionEnd,
                    DW.LNCT.timestamp => file_entry.mtime = val.getUInt(u64) catch return error.UnexpectedDebugLineSectionEnd,
                    DW.LNCT.size => file_entry.size = val.getUInt(u64) catch return error.UnexpectedDebugLineSectionEnd,
                    DW.LNCT.MD5 => file_entry.md5 = switch (val) {
                        .data16 => |data16| data16.*,
                        else => blk: {
                            std.log.debug("Invalid data type for DW.LNCT.MD5: {}", .{val});
                            break :blk .{0} ** 16;
                        },
                    },
                    else => continue,
                }
            }
        }
    }

    fbr.seekTo(prog_start_off) catch return error.UnexpectedDebugLineSectionEnd;
    const section_end = debug_line_off + unit_header.unit_length;
    return LineNumberProgram{
        .gpa = gpa,
        .fbr = fbr,
        .section_end = section_end,
        .files = files,
        .directories = directories,
        .opcode_base = opcode_base,
        .line_base = line_base,
        .line_range = line_range,
        .minimum_instruction_length = minimum_instruction_length,
        .maximum_operations_per_instruction = maximum_operations_per_instruction,
        .default_is_stmt = default_is_stmt != 0,
        .is_stmt = default_is_stmt != 0,
    };
}

pub const LineInfo = struct {
    file: usize,
    address: u64,
    line: i64,
    col: u64,
};

pub const LineNumberProgram = struct {
    gpa: heap.Allocator,
    fbr: io.Source,
    section_end: usize,
    directories: std.ArrayListUnmanaged(FileEntry),
    files: std.ArrayListUnmanaged(FileEntry),

    // Options
    default_is_stmt: bool,
    opcode_base: u64,
    line_base: i8,
    line_range: u8,
    minimum_instruction_length: u64,
    maximum_operations_per_instruction: u64,

    // Registers
    address: u64 = 0,
    op_index: usize = 0,
    file: usize = 1,
    line: i64 = 1,
    column: u64 = 0,
    is_stmt: bool = false,
    basic_block: bool = false,
    end_sequence: bool = false,
    prologue_end: bool = false,
    epilogue_begin: bool = false,
    isa: u64 = 0,
    discriminator: u64 = 0,

    pub fn deinit(self: *LineNumberProgram, gpa: heap.Allocator) void {
        self.directories.deinit(gpa);
        self.files.deinit(gpa);
    }

    pub fn hasNext(self: *LineNumberProgram) bool {
        return self.fbr.pos < self.section_end;
    }

    pub fn next(self: *LineNumberProgram) !?LineInfo {
        if (!self.hasNext()) {
            return null;
        }

        const opcode: DW.LNS = @enumFromInt(self.fbr.readByte() catch return error.UnexpectedDebugLineSectionEnd);
        if (opcode == DW.LNS.extended_op) {
            // extended opcode
            const op_size = self.fbr.readUleb128(u64) catch return error.UnexpectedDebugLineSectionEnd;
            const extended_opcode: DW.LNE = @enumFromInt(self.fbr.readByte() catch return error.UnexpectedDebugLineSectionEnd);
            switch (extended_opcode) {
                DW.LNE.end_sequence => {
                    // End sequence maps end address of a line
                    // we dont use those so just skip
                    self.reset();
                },
                DW.LNE.set_address => {
                    self.address = self.fbr.readInt(usize) catch return error.UnexpectedDebugLineSectionEnd;
                    self.op_index = 0;
                },
                DW.LNE.set_discriminator => {
                    self.discriminator = self.fbr.readUleb128(u64) catch return error.UnexpectedDebugLineSectionEnd;
                },
                DW.LNE.define_file => {
                    const path = self.fbr.readBytesTo(0) catch return error.UnexpectedDebugLineSectionEnd;
                    const dir_index = self.fbr.readUleb128(u32) catch return error.UnexpectedDebugLineSectionEnd;
                    const mtime = self.fbr.readUleb128(u64) catch return error.UnexpectedDebugLineSectionEnd;
                    const length = self.fbr.readUleb128(u64) catch return error.UnexpectedDebugLineSectionEnd;
                    self.files.append(self.gpa, .{
                        .path = path,
                        .dir_index = dir_index,
                        .mtime = mtime,
                        .size = length,
                    }) catch unreachable;
                },
                else => self.fbr.seekForward(op_size - 1) catch return error.UnexpectedDebugLineSectionEnd,
            }
        } else if (@intFromEnum(opcode) >= self.opcode_base) {
            const adjusted_opcode = @intFromEnum(opcode) - self.opcode_base;
            const operation_advance = adjusted_opcode / self.line_range;

            self.address += self.minimum_instruction_length * ((self.op_index + operation_advance) / self.maximum_operations_per_instruction);
            self.op_index = (self.op_index + operation_advance) % self.maximum_operations_per_instruction;
            self.line += self.line_base + @as(i32, @intCast(adjusted_opcode % self.line_range));
            self.basic_block = false;
            self.prologue_end = false;
            self.epilogue_begin = false;
            self.discriminator = 0;
            return LineInfo{
                .file = self.file,
                .address = self.address,
                .line = self.line,
                .col = self.column,
            };
        } else {
            // Regular opcodes
            switch (opcode) {
                DW.LNS.copy => {
                    self.discriminator = 0;
                    self.basic_block = false;
                    self.prologue_end = false;
                    self.epilogue_begin = false;
                    return LineInfo{
                        .file = self.file,
                        .address = self.address,
                        .line = self.line,
                        .col = self.column,
                    };
                },
                DW.LNS.advance_pc => {
                    const advance_value = self.fbr.readUleb128(u64) catch return error.UnexpectedDebugLineSectionEnd;
                    self.address += self.minimum_instruction_length * ((self.op_index + advance_value) / self.maximum_operations_per_instruction);
                    self.op_index = (self.op_index + advance_value) % self.maximum_operations_per_instruction;
                },
                DW.LNS.advance_line => {
                    const advance_value = self.fbr.readIleb128(i64) catch return error.UnexpectedDebugLineSectionEnd;
                    self.line += @intCast(advance_value);
                },
                DW.LNS.set_file => {
                    const file = self.fbr.readUleb128(u64) catch return error.UnexpectedDebugLineSectionEnd;
                    self.file = file;
                },
                DW.LNS.set_column => {
                    const column = self.fbr.readUleb128(u64) catch return error.UnexpectedDebugLineSectionEnd;
                    self.column = column;
                },
                DW.LNS.negate_stmt => {
                    self.is_stmt = !self.is_stmt;
                },
                DW.LNS.set_basic_block => {
                    self.basic_block = true;
                },
                DW.LNS.const_add_pc => {
                    const adjusted_opcode = 255 - self.opcode_base;
                    const advance_value = adjusted_opcode / self.line_range;
                    self.address += self.minimum_instruction_length * ((self.op_index + advance_value) / self.maximum_operations_per_instruction);
                    self.op_index = (self.op_index + advance_value) % self.maximum_operations_per_instruction;
                },
                DW.LNS.fixed_advance_pc => {
                    const offset = self.fbr.readInt(u16) catch return error.UnexpectedDebugLineSectionEnd;
                    self.address += offset;
                    self.op_index = 0;
                },
                DW.LNS.set_prologue_end => {
                    self.prologue_end = true;
                },
                DW.LNS.set_epilogue_begin => {
                    self.epilogue_begin = true;
                },
                DW.LNS.set_isa => {
                    self.isa = self.fbr.readUleb128(u64) catch return error.UnexpectedDebugLineSectionEnd;
                },
                else => unreachable,
            }
        }

        return null;
    }

    pub fn reset(self: *LineNumberProgram) void {
        self.address = 0;
        self.op_index = 0;
        self.file = 1;
        self.line = 1;
        self.column = 0;
        self.is_stmt = self.default_is_stmt;
        self.basic_block = false;
        self.end_sequence = false;
        self.prologue_end = false;
        self.epilogue_begin = false;
        self.isa = 0;
        self.discriminator = 0;
    }
};

fn parseAttrValue(fbr: *io.Source, format: DwarfFormat, form_id: DW.FORM) error{EndOfBuffer}!DW.AT_Value {
    return switch (form_id) {
        DW.FORM.addr => DW.AT_Value{
            .addr = fbr.readInt(usize) catch
                return error.EndOfBuffer,
        },
        DW.FORM.addrx => DW.AT_Value{
            .addrx = fbr.readUleb128(usize) catch
                return error.EndOfBuffer,
        },
        DW.FORM.addrx1 => DW.AT_Value{
            .addrx = fbr.readUleb128(u8) catch
                return error.EndOfBuffer,
        },
        DW.FORM.addrx2 => DW.AT_Value{
            .addrx = fbr.readUleb128(u16) catch
                return error.EndOfBuffer,
        },
        DW.FORM.addrx3 => DW.AT_Value{
            .addrx = fbr.readUleb128(u24) catch
                return error.EndOfBuffer,
        },
        DW.FORM.addrx4 => DW.AT_Value{
            .addrx = fbr.readUleb128(u32) catch
                return error.EndOfBuffer,
        },
        DW.FORM.block => blk: {
            const size = fbr.readUleb128(usize) catch
                return error.EndOfBuffer;
            break :blk DW.AT_Value{
                .block = fbr.readBytes(size) catch
                    return error.EndOfBuffer,
            };
        },
        DW.FORM.block1 => blk: {
            const size = fbr.readInt(u8) catch
                return error.EndOfBuffer;
            break :blk DW.AT_Value{
                .block = fbr.readBytes(size) catch
                    return error.EndOfBuffer,
            };
        },
        DW.FORM.block2 => blk: {
            const size = fbr.readInt(u16) catch
                return error.EndOfBuffer;

            break :blk DW.AT_Value{
                .block = fbr.readBytes(size) catch
                    return error.EndOfBuffer,
            };
        },
        DW.FORM.block4 => blk: {
            const size = fbr.readInt(u32) catch
                return error.EndOfBuffer;

            break :blk DW.AT_Value{
                .block = fbr.readBytes(size) catch
                    return error.EndOfBuffer,
            };
        },
        DW.FORM.data1 => DW.AT_Value{
            .udata = fbr.readInt(u8) catch
                return error.EndOfBuffer,
        },
        DW.FORM.data2 => DW.AT_Value{
            .udata = fbr.readInt(u16) catch
                return error.EndOfBuffer,
        },
        DW.FORM.data4 => DW.AT_Value{
            .udata = fbr.readInt(u32) catch
                return error.EndOfBuffer,
        },
        DW.FORM.data8 => DW.AT_Value{
            .udata = fbr.readInt(u64) catch
                return error.EndOfBuffer,
        },
        DW.FORM.data16 => blk: {
            const size = fbr.readBytes(16) catch
                return error.EndOfBuffer;

            break :blk DW.AT_Value{ .data16 = size[0..16] };
        },
        DW.FORM.sdata => DW.AT_Value{
            .sdata = fbr.readIleb128(i64) catch
                return error.EndOfBuffer,
        },
        DW.FORM.udata => DW.AT_Value{
            .udata = fbr.readUleb128(u64) catch
                return error.EndOfBuffer,
        },
        DW.FORM.exprloc => blk: {
            const size = fbr.readUleb128(usize) catch
                return error.EndOfBuffer;

            break :blk DW.AT_Value{
                .exprloc = fbr.readBytes(size) catch
                    return error.EndOfBuffer,
            };
        },
        DW.FORM.flag => DW.AT_Value{
            .flag = (fbr.readByte() catch
                return error.EndOfBuffer) != 0,
        },
        DW.FORM.flag_present => DW.AT_Value{
            .flag = true,
        },
        DW.FORM.loclistx => DW.AT_Value{
            .loclistx = fbr.readUleb128(u64) catch
                return error.EndOfBuffer,
        },
        DW.FORM.rnglistx => DW.AT_Value{
            .rnglistx = fbr.readUleb128(u64) catch
                return error.EndOfBuffer,
        },
        DW.FORM.ref1 => DW.AT_Value{
            .ref = fbr.readInt(u8) catch
                return error.EndOfBuffer,
        },
        DW.FORM.ref2 => DW.AT_Value{
            .ref = fbr.readInt(u16) catch
                return error.EndOfBuffer,
        },
        DW.FORM.ref4 => DW.AT_Value{
            .ref = fbr.readInt(u32) catch
                return error.EndOfBuffer,
        },
        DW.FORM.ref8 => DW.AT_Value{
            .ref = fbr.readInt(u64) catch
                return error.EndOfBuffer,
        },
        DW.FORM.ref_udata => DW.AT_Value{
            .ref = fbr.readUleb128(u64) catch
                return error.EndOfBuffer,
        },
        DW.FORM.ref_addr => DW.AT_Value{
            .ref_addr = readAddress(fbr, format) catch
                return error.EndOfBuffer,
        },
        DW.FORM.ref_sig8 => DW.AT_Value{
            .ref = fbr.readInt(u64) catch
                return error.EndOfBuffer,
        },
        DW.FORM.ref_sup4 => DW.AT_Value{
            .ref = fbr.readInt(u32) catch
                return error.EndOfBuffer,
        },
        DW.FORM.ref_sup8 => DW.AT_Value{
            .ref = fbr.readInt(u64) catch
                return error.EndOfBuffer,
        },
        DW.FORM.sec_offset => DW.AT_Value{
            .sec_offset = readAddress(fbr, format) catch
                return error.EndOfBuffer,
        },
        DW.FORM.string => DW.AT_Value{
            .string = fbr.readBytesTo(0) catch
                return error.EndOfBuffer,
        },
        DW.FORM.strp, DW.FORM.strp_sup => DW.AT_Value{
            .strp = readAddress(fbr, format) catch
                return error.EndOfBuffer,
        },
        DW.FORM.line_strp => DW.AT_Value{
            .line_strp = readAddress(fbr, format) catch
                return error.EndOfBuffer,
        },
        DW.FORM.strx => DW.AT_Value{
            .strx = fbr.readUleb128(usize) catch
                return error.EndOfBuffer,
        },
        DW.FORM.strx1 => DW.AT_Value{
            .strx = fbr.readInt(u8) catch
                return error.EndOfBuffer,
        },
        DW.FORM.strx2 => DW.AT_Value{
            .strx = fbr.readInt(u16) catch
                return error.EndOfBuffer,
        },
        DW.FORM.strx3 => DW.AT_Value{
            .strx = fbr.readInt(u24) catch
                return error.EndOfBuffer,
        },
        DW.FORM.strx4 => DW.AT_Value{
            .strx = fbr.readInt(u32) catch
                return error.EndOfBuffer,
        },
        else => unreachable,
    };
}

fn readAddress(fbr: *io.Source, format: DwarfFormat) error{EndOfBuffer}!u64 {
    return switch (format) {
        .bit32 => fbr.readInt(u32) catch return error.EndOfBuffer,
        .bit64 => fbr.readInt(u64) catch return error.EndOfBuffer,
    };
}
