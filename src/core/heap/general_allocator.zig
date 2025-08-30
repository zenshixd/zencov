const std = @import("std");
const fmt = @import("../fmt.zig");
const core = @import("../../core.zig");
const mem = @import("../mem.zig");
const debug = @import("../debug.zig");
const heap = @import("../heap.zig");
const logger = @import("../logger.zig");
const expect = @import("../../test/expect.zig").expect;

const AllocationInfo = struct {
    freed_size: ?usize,
    size: usize,
    ret_addr: usize,
};

const AllocationMapContext = struct {
    pub fn hash(k: usize) u64 {
        return k;
    }

    pub fn eql(a: usize, b: usize) bool {
        return a == b;
    }
};

const AllocationMap = core.HashMap(usize, AllocationInfo, AllocationMapContext);

pub const GeneralAllocatorOptions = struct {
    log_leaks: bool = true,
};

pub var options: GeneralAllocatorOptions = .{};
pub const GeneralAllocator = struct {
    allocations: AllocationMap,

    pub fn init() GeneralAllocator {
        return .{
            .allocations = AllocationMap.init(heap.page_allocator),
        };
    }

    pub fn detectLeaks(self: *GeneralAllocator) bool {
        var leak_count: u8 = 0;
        var it = self.allocations.iterator();
        while (it.next()) |entry| {
            const info = entry.value;
            if (info.freed_size == null) {
                leak_count += 1;
            } else if (info.freed_size.? != info.size) {
                leak_count += 1;
            }
        }
        if (leak_count > 0 and options.log_leaks) {
            logger.err("{} allocations leaked", .{leak_count});
        }
        return leak_count > 0;
    }

    pub fn unwind(self: *GeneralAllocator) void {
        _ = self;
        var maybe_fa: ?*usize = @ptrFromInt(@frameAddress());
        while (maybe_fa) |fa| {
            const ra: *usize = @ptrFromInt(@intFromPtr(maybe_fa) + 8);
            debug.print("ra: {}\n", .{fmt.int(ra.*, fmt.FormatIntMode.hex)});
            maybe_fa = @ptrFromInt(fa.*);
        }
    }

    pub fn deinit(self: *GeneralAllocator) void {
        self.allocations.deinit();
    }

    pub fn allocator(self: *GeneralAllocator) heap.Allocator {
        return heap.Allocator{
            .ctx = self,
            .allocFn = allocFn,
            .reallocFn = reallocFn,
            .freeFn = freeFn,
        };
    }

    fn alloc(self: *GeneralAllocator, len: usize, alignment: usize) heap.AllocatorError![]u8 {
        const buf = try heap.page_allocator.allocFn(self, len, alignment);
        try self.allocations.put(@intFromPtr(buf.ptr), .{
            .size = len,
            .freed_size = null,
            .ret_addr = @returnAddress(),
        });
        return buf;
    }

    pub fn realloc(self: *GeneralAllocator, memory: []u8, alignment: usize, new_len: usize) heap.AllocatorError![]u8 {
        const buf = try heap.page_allocator.reallocFn(self, memory, alignment, new_len);
        try self.allocations.put(@intFromPtr(buf.ptr), .{
            .size = new_len,
            .freed_size = null,
            .ret_addr = @returnAddress(),
        });
        return buf;
    }

    pub fn free(self: *GeneralAllocator, memory: []u8) void {
        heap.page_allocator.free(memory);
        const result = self.allocations.getPtr(@intFromPtr(memory.ptr)) orelse return;
        result.freed_size = memory.len;
    }

    fn allocFn(ctx: *anyopaque, len: usize, alignment: usize) heap.AllocatorError![]u8 {
        const self: *GeneralAllocator = @ptrCast(@alignCast(ctx));
        return self.alloc(len, alignment);
    }

    fn reallocFn(ctx: *anyopaque, memory: []u8, alignment: usize, new_len: usize) heap.AllocatorError![]u8 {
        const self: *GeneralAllocator = @ptrCast(@alignCast(ctx));
        return self.realloc(memory, alignment, new_len);
    }

    fn freeFn(ctx: *anyopaque, memory: []u8) void {
        const self: *GeneralAllocator = @ptrCast(@alignCast(ctx));
        return self.free(memory);
    }
};

test "general allocator" {
    options.log_leaks = false;
    defer options.log_leaks = true;

    var general_allocator = GeneralAllocator.init();
    defer general_allocator.deinit();
    const allocator = general_allocator.allocator();

    const buf = try allocator.alloc(u8, 10);
    const buf2 = try allocator.alloc(u8, 10);
    const buf3 = try allocator.alloc(u8, 10);

    general_allocator.unwind();
    // Check if there are non-freed allocations
    try expect(general_allocator.detectLeaks()).toEqual(true);

    allocator.free(buf);
    allocator.free(buf2);
    allocator.free(buf3);

    try expect(general_allocator.detectLeaks()).toEqual(false);

    const buf4 = try allocator.alloc(u8, 10);
    try expect(general_allocator.detectLeaks()).toEqual(true);

    // Freeing a slice of different size is a leak
    allocator.free(buf4.ptr[0..5]);
    try expect(general_allocator.detectLeaks()).toEqual(true);
}
