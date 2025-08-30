const std = @import("std");
const builtin = @import("builtin");
const native_os = builtin.os.tag;
const AtomicOrder = std.builtin.AtomicOrder;

const debug = @import("../debug.zig");
const heap = @import("../heap.zig");
const mem = @import("../mem.zig");
const math = @import("../math.zig");
const posix = @import("../platform/posix.zig");
const mach = @import("../platform/mach.zig");
const expect = @import("../../test/expect.zig").expect;

pub fn allocFn(self: *anyopaque, len: usize, alignment: usize) heap.AllocatorError![]u8 {
    _ = self;
    return alloc(len, alignment);
}

pub fn reallocFn(self: *anyopaque, memory: []u8, alignment: usize, new_len: usize) heap.AllocatorError![]u8 {
    _ = self;
    return realloc(memory, alignment, new_len);
}

pub fn freeFn(self: *anyopaque, memory: []u8) void {
    _ = self;
    return free(memory);
}

/// Allocates memory on heap using platform-specific syscall
/// mmap on Linux
/// mach_vm_allocate on macOS
pub fn alloc(len: usize, alignment: usize) heap.AllocatorError![]u8 {
    return switch (native_os) {
        .linux => allocPosix(len, alignment),
        .macos => allocMach(len, alignment),
        else => @compileError("Unsupported OS"),
    };
}

/// Reallocates memory on heap
/// Uses mremap on Linux
/// Other platforms dont have remap syscall, so we use regular alloc to check if next page is available
pub fn realloc(memory: []u8, alignment: usize, new_len: usize) heap.AllocatorError![]u8 {
    if (memory.len == 0) {
        return alloc(new_len, alignment);
    }

    const cur_end_page_addr = mem.alignBackward(@intFromPtr(memory.ptr + memory.len), heap.pageSize());
    const new_end_page_addr = mem.alignBackward(@intFromPtr(memory.ptr + new_len), heap.pageSize());

    if (new_len < memory.len) {
        // Shrink
        if (new_end_page_addr < cur_end_page_addr) {
            // Free unused page
            free(@as([*]u8, @ptrFromInt(cur_end_page_addr))[0..heap.pageSize()]);
        }

        return memory.ptr[0..new_len];
    }

    if (new_end_page_addr == cur_end_page_addr) {
        // new_len is within current page boundary
        return memory.ptr[0..new_len];
    }

    if (native_os == .linux) {
        return try posix.mremap(memory.ptr, memory.len, new_len, posix.MmapFlags{ .may_move = 1 }, null);
    }

    // No support for remap, so just full realloc
    // We could *potentially* alloc just 1 page - check if it will be continuous,
    // and dont move the pointer, buuuut its too sketchy probably
    const new_memory = try alloc(new_len, alignment);
    @memcpy(new_memory[0..memory.len], memory);
    free(memory);
    return new_memory;
}

/// Frees memory on heap
/// Uses munmap on Linux
/// mach_vm_deallocate on macOS
pub fn free(memory: []u8) void {
    debug.assert(mem.isAligned(@intFromPtr(memory.ptr), heap.pageSize()));
    switch (native_os) {
        .linux => freePosix(memory),
        .macos => freeMach(memory),
        else => @compileError("Unsupported OS"),
    }
}

fn allocPosix(len: usize, alignment: usize) heap.AllocatorError![]u8 {
    debug.assert(alignment <= std.heap.page_size_min);
    const ptr = try posix.mmap(
        null,
        len,
        posix.MemProt{ .read = 1, .write = 1 },
        posix.MmapFlags{ .private = 1, .anonymous = 1 },
        -1,
        0,
    );

    return ptr[0..len];
}

fn allocMach(len: usize, alignment: usize) heap.AllocatorError![]u8 {
    debug.assert(alignment <= std.heap.page_size_min);
    const port = mach.taskSelf();
    const ptr = port.vmAllocate(len, mach.AllocateFlags{ .anywhere = 1, .chunk_4gb = 1 }) catch |err| switch (err) {
        error.MemoryFailure => return error.OutOfMemory,
        else => unreachable,
    };
    return ptr;
}

fn freePosix(memory: []u8) void {
    posix.munmap(memory.ptr, memory.len);
}

fn freeMach(memory: []u8) void {
    const port = mach.taskSelf();
    port.vmDeallocate(memory) catch unreachable;
}

test "alloc" {
    const page_allocator = heap.Allocator{
        .ctx = undefined,
        .allocFn = allocFn,
        .reallocFn = reallocFn,
        .freeFn = freeFn,
    };

    var buf = try page_allocator.alloc(u8, 1024);
    defer page_allocator.free(buf);

    try expect(buf.len).toEqual(1024);
    for (0..buf.len) |i| {
        buf[i] = @truncate(i);
        try expect(buf[i]).toEqual(@truncate(i));
    }

    var buf2 = try page_allocator.alloc(u8, heap.pageSize() * 2);
    defer page_allocator.free(buf2);

    try expect(buf2.len).toEqual(heap.pageSize() * 2);
    for (0..buf2.len) |i| {
        buf2[i] = @truncate(i);
        try expect(buf2[i]).toEqual(@truncate(i));
    }
}

test "realloc" {
    // TODO: maybe add a test for Segfaults ???
    // I know its possible to register a segfault handler
    // But not sure if test can continue running after handling it
    const page_allocator = heap.Allocator{
        .ctx = undefined,
        .allocFn = allocFn,
        .reallocFn = reallocFn,
        .freeFn = freeFn,
    };
    var buf = try page_allocator.alloc(u8, 1024);
    defer page_allocator.free(buf);

    try expect(buf.len).toEqual(1024);
    for (0..buf.len) |i| {
        buf[i] = @truncate(i);
        try expect(buf[i]).toEqual(@truncate(i));
    }

    // Realloc withtin same page
    buf = try page_allocator.realloc(u8, buf, 2048);
    try expect(buf.len).toEqual(2048);
    for (0..buf.len) |i| {
        buf[i] = @truncate(i);
        try expect(buf[i]).toEqual(@truncate(i));
    }

    // Realloc to larger page
    buf = try page_allocator.realloc(u8, buf, heap.pageSize() * 2);
    try expect(buf.len).toEqual(heap.pageSize() * 2);
    for (0..buf.len) |i| {
        buf[i] = @truncate(i);
        try expect(buf[i]).toEqual(@truncate(i));
    }

    // Shrink to same page
    buf = try page_allocator.realloc(u8, buf, heap.pageSize() * 2 - 1000);
    try expect(buf.len).toEqual(heap.pageSize() * 2 - 1000);
    for (0..buf.len) |i| {
        buf[i] = @truncate(i);
        try expect(buf[i]).toEqual(@truncate(i));
    }

    // Shrink and free unused page
    buf = try page_allocator.realloc(u8, buf, heap.pageSize());
    try expect(buf.len).toEqual(heap.pageSize());
    for (0..buf.len) |i| {
        buf[i] = @truncate(i);
        try expect(buf[i]).toEqual(@truncate(i));
    }
}
