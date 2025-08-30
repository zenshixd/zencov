const debug = @import("../debug.zig");
const heap = @import("../heap.zig");
const mem = @import("../mem.zig");
const math = @import("../math.zig");
const expect = @import("../../test/expect.zig").expect;

const region_size = heap.pageSize();

const child_allocator = heap.page_allocator;
pub const ArenaAllocator = struct {
    pub const Region = struct {
        prev: ?*Region,
        buf: []u8,
        pos: usize,
    };

    pub const Checkpoint = struct {
        arena: *ArenaAllocator,
        region: ?*Region,
        pos: usize,

        pub fn free(self: Checkpoint) void {
            while (self.arena.current != self.region) {
                const prev = self.arena.current.?.prev;
                self.arena.freeRegion(self.arena.current);
                self.arena.current = prev;
            }

            if (self.arena.current) |current| {
                current.pos = self.pos;
            }
        }
    };

    current: ?*Region = null,

    pub fn deinit(self: *ArenaAllocator) void {
        var current = self.current;
        while (current) |region| {
            current = region.prev;

            freeRegion(region);
        }
    }

    pub fn allocator(self: *ArenaAllocator) heap.Allocator {
        return heap.Allocator{
            .ctx = self,
            .allocFn = allocFn,
            .reallocFn = reallocFn,
            .freeFn = freeFn,
        };
    }

    pub fn alloc(self: *ArenaAllocator, len: usize, alignment: usize) heap.AllocatorError![]u8 {
        var current = self.current orelse {
            const new_region_buf = try allocRegion(len);
            _ = self.updateRegion(new_region_buf);
            return self.current.?.buf[0..len];
        };

        var cur_pos_aligned = mem.alignForward(current.pos, alignment);
        if (cur_pos_aligned + len > current.buf.len) {
            const new_region_buf = try allocRegion(len);
            if (current.buf.ptr + current.buf.len == new_region_buf.ptr) {
                // New region is adjacent to the current region, so we can expand current region
                current.buf.len += new_region_buf.len;
            } else {
                // New region is in Narnia, so make it the current region
                current = self.updateRegion(new_region_buf);
                cur_pos_aligned = 0;
            }
        }

        const ptr = current.buf[cur_pos_aligned..][0..len];
        current.pos = cur_pos_aligned + len;
        return ptr;
    }

    pub fn realloc(self: *ArenaAllocator, memory: []u8, alignment: usize, new_len: usize) heap.AllocatorError![]u8 {
        _ = self;
        _ = memory;
        _ = alignment;
        _ = new_len;
        debug.panic("not implemented", .{});
    }

    pub fn free(self: *ArenaAllocator, memory: []u8) void {
        if (self.current) |current| {
            if (memory.ptr == current.buf.ptr + current.pos - memory.len) {
                // Shrink arena if provided allocation is at the end of the current arena
                current.pos -= memory.len;
            }

            if (current.pos == 0) {
                const region = current;
                self.current = current.prev;
                freeRegion(region);
            }

            return;
        }

        debug.panic("invalid free, no arenas allocated", .{});
    }

    pub fn checkpoint(self: *ArenaAllocator) Checkpoint {
        const region = self.current orelse return Checkpoint{
            .region = null,
            .pos = 0,
        };

        return Checkpoint{
            .arena = self,
            .region = region,
            .pos = region.pos,
        };
    }

    fn allocRegion(min_size: usize) heap.AllocatorError![]u8 {
        const min_size_aligned = mem.alignForward(min_size + @sizeOf(Region), heap.pageSize());
        const size = math.max(region_size, min_size_aligned);
        return child_allocator.alloc(u8, size);
    }

    fn updateRegion(self: *ArenaAllocator, buf: []u8) *Region {
        const new_region: *Region = @ptrCast(@alignCast(buf.ptr));
        new_region.* = .{
            .prev = self.current,
            .buf = buf[@sizeOf(Region)..],
            .pos = 0,
        };
        self.current = new_region;
        return new_region;
    }

    fn freeRegion(region: *Region) void {
        const region_buf: []u8 = @as([*]u8, @ptrCast(region))[0 .. region.buf.len + @sizeOf(Region)];
        child_allocator.free(region_buf);
    }

    fn allocFn(ctx: *anyopaque, len: usize, alignment: usize) heap.AllocatorError![]u8 {
        const self: *ArenaAllocator = @ptrCast(@alignCast(ctx));
        return self.alloc(len, alignment);
    }

    fn reallocFn(ctx: *anyopaque, memory: []u8, alignment: usize, new_len: usize) heap.AllocatorError![]u8 {
        const self: *ArenaAllocator = @ptrCast(@alignCast(ctx));
        return self.realloc(memory, alignment, new_len);
    }

    fn freeFn(ctx: *anyopaque, memory: []u8) void {
        const self: *ArenaAllocator = @ptrCast(@alignCast(ctx));
        return self.free(memory);
    }
};

test "basic usage" {
    var arena_allocator = ArenaAllocator{};
    defer arena_allocator.deinit();
    const allocator = arena_allocator.allocator();

    var slice = try allocator.alloc(u8, 1024);
    defer allocator.free(slice);

    try expect(slice.len).toEqual(1024);
    for (0..slice.len) |i| {
        slice[i] = @truncate(i);
        try expect(slice[i]).toEqual(@truncate(i));
    }

    // make a dent in vpages
    const dent = child_allocator.alloc(u8, heap.pageSize()) catch unreachable;
    defer child_allocator.free(dent);

    // New region
    const slice2 = try allocator.alloc(u8, heap.pageSize());
    defer allocator.free(slice2);

    try expect(slice2.len).toEqual(heap.pageSize());
    try expect(arena_allocator.current.?.buf.len).toEqual(heap.pageSize() * 2 - @sizeOf(ArenaAllocator.Region));
    try expect(arena_allocator.current.?.prev != null).toEqual(true);

    // Extend region
    const current_region = arena_allocator.current.?;
    const slice4 = try allocator.alloc(u8, heap.pageSize() * 2);
    defer allocator.free(slice4);

    try expect(slice4.len).toEqual(heap.pageSize() * 2);
    try expect(arena_allocator.current).toEqual(current_region);
    try expect(arena_allocator.current.?.buf.len).toEqual(heap.pageSize() * 5 - @sizeOf(ArenaAllocator.Region));
}
