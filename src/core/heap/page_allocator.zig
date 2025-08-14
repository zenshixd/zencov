const std = @import("std");
const AtomicOrder = std.builtin.AtomicOrder;

const debug = @import("../debug.zig");
const mem = @import("../mem.zig");

const PageAllocator = @This();

var global_page_addr_hint: ?[*]align(std.heap.page_size_min) u8 = null;

pub fn alloc(len: usize, alignment: u29) mem.AllocatorError![]u8 {
    debug.assert(alignment <= std.heap.page_size_min);
    const page_addr_hint = @atomicLoad(@TypeOf(global_page_addr_hint), &global_page_addr_hint, AtomicOrder.acquire);
    const ptr = try std.posix.mmap(
        page_addr_hint,
        len,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        std.posix.MAP{ .TYPE = .PRIVATE, .ANONYMOUS = 1 },
        -1,
        0,
    );

    _ = @cmpxchgStrong(@TypeOf(global_page_addr_hint), &global_page_addr_hint, page_addr_hint, ptr, AtomicOrder.monotonic, AtomicOrder.monotonic);
    return ptr[0..len];
}

pub fn main() void {}
