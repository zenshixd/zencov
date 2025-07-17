const std = @import("std");
const assert = std.debug.assert;
const panic = std.debug.panic;

const platform = @import("../platform.zig");

pub const MH_MAGIC = 0xfeedface;
pub const MH_MAGIC_64 = 0xfeedfacf;
pub const MachOHeader = extern struct {
    magic: u32,
    cpu_type: i32,
    cpu_sub_type: i32,
    filetype: u32,
    ncmds: u32,
    size_of_cmds: u32,
    flags: u32,
};

pub const MachOHeader64 = extern struct {
    magic: u32 = MH_MAGIC_64,
    cpu_type: i32 = 0,
    cpu_sub_type: i32 = 0,
    filetype: u32 = 0,
    ncmds: u32 = 0,
    size_of_cmds: u32 = 0,
    flags: u32 = 0,
    reserved: u32 = 0,
};

pub const Segment64Command = extern struct {
    /// LC_SEGMENT_64
    cmd: LoadCommand.CommandType = .segment_64,

    /// includes sizeof section_64 structs
    cmdsize: u32 = @sizeOf(Segment64Command),

    /// segment name
    segname: [16]u8,

    /// memory address of this segment
    vmaddr: u64 = 0,

    /// memory size of this segment
    vmsize: u64 = 0,

    /// file offset of this segment
    fileoff: u64 = 0,

    /// amount to map from the file
    filesize: u64 = 0,

    /// maximum VM protection
    maxprot: i32 = platform.VmProt.NONE,

    /// initial VM protection
    initprot: i32 = platform.VmProt.NONE,

    /// number of sections in segment
    nsects: u32 = 0,
    flags: u32 = 0,

    pub fn segName(self: *Segment64Command) []const u8 {
        return parseName(&self.segname);
    }
};

pub const Section64 = extern struct {
    /// name of this section
    sectname: [16]u8,

    /// segment this section goes in
    segname: [16]u8,

    /// memory address of this section
    addr: u64 = 0,

    /// size in bytes of this section
    size: u64 = 0,

    /// file offset of this section
    offset: u32 = 0,

    /// section alignment (power of 2)
    @"align": u32 = 0,

    /// file offset of relocation entries
    reloff: u32 = 0,

    /// number of relocation entries
    nreloc: u32 = 0,

    /// flags (section type and attributes
    flags: u32 = 0,

    /// reserved (for offset or index)
    reserved1: u32 = 0,

    /// reserved (for count or sizeof)
    reserved2: u32 = 0,

    /// reserved
    reserved3: u32 = 0,

    pub fn segName(sect: *const Section64) []const u8 {
        return parseName(&sect.segname);
    }

    pub fn sectName(sect: *const Section64) []const u8 {
        return parseName(&sect.sectname);
    }
};

pub const SymtabCommand = extern struct {
    /// LC_SYMTAB
    cmd: LoadCommand.CommandType = .symtab,

    /// sizeof(struct symtab_command)
    cmdsize: u32 = @sizeOf(SymtabCommand),

    /// symbol table offset
    symoff: u32 = 0,

    /// number of symbol table entries
    nsyms: u32 = 0,

    /// string table offset
    stroff: u32 = 0,

    /// string table size in bytes
    strsize: u32 = 0,
};

pub const N_STAB = 0xe0;
pub const N_PEXT = 0x10;
pub const N_TYPE = 0x0e;
pub const N_EXT = 0x01;

pub const N_UNDF = 0x0;
pub const N_ABS = 0x2;
pub const N_SECT = 0xe;
pub const N_PBUD = 0xc;
pub const N_INDR = 0xa;

pub const N_GSYM = 0x20; // global symbol: name,,NO_SECT,type,0
pub const N_FNAME = 0x22; // procedure name (f77 kludge): name,,NO_SECT,0,0
pub const N_FUN = 0x24; // procedure: name,,n_sect,linenumber,address
pub const N_STSYM = 0x26; // static symbol: name,,n_sect,type,address
pub const N_LCSYM = 0x28; // .lcomm symbol: name,,n_sect,type,address
pub const N_BNSYM = 0x2e; // begin nsect sym: 0,,n_sect,0,address
pub const N_AST = 0x32; // AST file path: name,,NO_SECT,0,0
pub const N_OPT = 0x3c; // emitted with gcc2_compiled and in gcc source
pub const N_RSYM = 0x40; // register sym: name,,NO_SECT,type,register
pub const N_SLINE = 0x44; // src line: 0,,n_sect,linenumber,address
pub const N_ENSYM = 0x4e; // end nsect sym: 0,,n_sect,0,address
pub const N_SSYM = 0x60; // structure elt: name,,NO_SECT,type,struct_offset
pub const N_SO = 0x64; // source file name: name,,n_sect,0,address
pub const N_OSO = 0x66; // object file name: name,,0,0,st_mtime
pub const N_LSYM = 0x80; // local sym: name,,NO_SECT,type,offset
pub const N_BINCL = 0x82; // include file beginning: name,,NO_SECT,0,sum
pub const N_SOL = 0x84; // #included file name: name,,n_sect,0,address
pub const N_PARAMS = 0x86; // compiler parameters: name,,NO_SECT,0,0
pub const N_VERSION = 0x88; // compiler version: name,,NO_SECT,0,0
pub const N_OLEVEL = 0x8A; // compiler -O level: name,,NO_SECT,0,0
pub const N_PSYM = 0xa0; // parameter: name,,NO_SECT,type,offset
pub const N_EINCL = 0xa2; // include file end: name,,NO_SECT,0,0
pub const N_ENTRY = 0xa4; // alternate entry: name,,n_sect,linenumber,address
pub const N_LBRAC = 0xc0; // left bracket: 0,,NO_SECT,nesting level,address
pub const N_EXCL = 0xc2; // deleted include file: name,,NO_SECT,0,sum
pub const N_RBRAC = 0xe0; // right bracket: 0,,NO_SECT,nesting level,address
pub const N_BCOMM = 0xe2; // begin common: name,,NO_SECT,0,0
pub const N_ECOMM = 0xe4; // end common: name,,n_sect,0,0
pub const N_ECOML = 0xe8; // end common (local name): 0,,n_sect,0,address
pub const N_LENG = 0xfe; // second stab entry with length information

pub const NList64 = extern struct {
    n_strx: u32,
    n_type: u8,
    n_sect: u8,
    n_desc: u16,
    n_value: u64,

    pub fn stab(sym: NList64) bool {
        return N_STAB & sym.n_type != 0;
    }
};

fn parseName(buf: *const [16]u8) []const u8 {
    return std.mem.sliceTo(buf, 0);
}

pub const LoadCommand = struct {
    pub const CommandType = enum(u32) {
        /// No load command - invalid
        none = 0,
        /// link-edit stab symbol table info
        symtab = 2,
        /// 64-bit segment of this file to be mapped
        segment_64 = 25,

        // there are others but we dont care for now
        _,
    };

    pub const Header = extern struct {
        cmd: CommandType,
        size: u32,
    };

    hdr: Header,
    data: []const u8,

    pub fn getSections(self: *const LoadCommand) []align(1) const Section64 {
        assert(self.hdr.cmd == .segment_64);
        const segment_cmd = @as(*align(1) const Segment64Command, @ptrCast(self.data.ptr)).*;
        if (segment_cmd.nsects == 0) {
            return &.{};
        }

        const data = self.data[@sizeOf(Segment64Command)..];
        return @as([*]align(1) const Section64, @ptrCast(data.ptr))[0..segment_cmd.nsects];
    }

    pub fn getSymtab(self: *const LoadCommand, file_content: []const u8) []align(1) const NList64 {
        assert(self.hdr.cmd == .symtab);
        const symtab_cmd = std.mem.bytesToValue(SymtabCommand, self.data);
        return @as([*]align(1) const NList64, @ptrCast(file_content[symtab_cmd.symoff..]))[0..symtab_cmd.nsyms];
    }

    pub fn deinit(self: *LoadCommand, gpa: std.mem.Allocator) void {
        gpa.free(self.data);
    }
};

pub const LoadCommandIterator = struct {
    ncmds: usize,
    buf: []const u8,
    index: usize = 0,

    pub fn next(self: *LoadCommandIterator) ?LoadCommand {
        if (self.index >= self.ncmds) {
            return null;
        }

        const hdr = std.mem.bytesToValue(LoadCommand.Header, self.buf);
        const data = self.buf[0..hdr.size];

        self.buf = self.buf[hdr.size..];
        self.index += 1;

        return .{
            .hdr = hdr,
            .data = data,
        };
    }
};
