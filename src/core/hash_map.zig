const std = @import("std");
const debug = @import("debug.zig");
const meta = @import("meta.zig");
const math = @import("math.zig");
const mem = @import("mem.zig");
const heap = @import("heap.zig");

const expect = @import("../test/expect.zig").expect;

pub const DefaultContext = struct {
    pub fn hash(k: anytype) u64 {
        return std.hash.Wyhash.hash(0, mem.asBytes(&k));
    }

    pub fn eql(a: anytype, b: anytype) bool {
        return mem.eql(u8, mem.asBytes(&a), mem.asBytes(&b));
    }
};

pub fn HashMap(comptime K: type, comptime V: type, comptime Context: type) type {
    return struct {
        const Self = @This();

        pub const Metadata = packed struct {
            pub const Fingerprint = u7;
            fingerprint: Fingerprint = slot_free,
            used: bool = false,

            const slot_free = 0;
            const slot_tombstone = 1;

            pub fn takeFingerprint(hash: Hash) Fingerprint {
                const hash_bits = @typeInfo(Hash).int.bits;
                const fingerprint_bits = @typeInfo(Fingerprint).int.bits;
                // Using upper bits as fingerprint gives us better entropy
                return @truncate(hash >> (hash_bits - fingerprint_bits));
            }

            pub fn markUsed(self: *Metadata, hash: Hash) void {
                self.fingerprint = takeFingerprint(hash);
                self.used = true;
            }

            pub fn markTombstone(self: *Metadata) void {
                self.fingerprint = slot_tombstone;
                self.used = false;
            }

            pub fn isUsed(self: Metadata) bool {
                return self.used;
            }

            pub fn isTombstone(self: Metadata) bool {
                return !self.used and self.fingerprint == slot_tombstone;
            }

            pub fn isFree(self: Metadata) bool {
                return !self.used and self.fingerprint == slot_free;
            }
        };

        pub const Header = struct {
            keys: [*]K,
            values: [*]V,
            capacity: Size,
        };

        pub const Entry = struct {
            key: K,
            value: V,
        };

        pub const GetOrPutResult = struct {
            key_ptr: *K,
            value_ptr: *V,
            found_existing: bool,
        };

        pub const Iterator = struct {
            map: Self,
            index: Size,

            pub fn next(self: *Iterator) ?Entry {
                if (self.map.metadata == null) {
                    return null;
                }

                if (self.index >= self.map.capacity()) {
                    return null;
                }

                while (!self.map.metadata.?[self.index].isUsed()) : (self.index += 1) {}

                if (self.index >= self.map.capacity()) {
                    return null;
                }

                const entry = Entry{
                    .key = keys(self.map)[self.index],
                    .value = values(self.map)[self.index],
                };

                self.index += 1;
                return entry;
            }
        };

        const Hash = usize;
        const Size = usize;
        const context = Context{};
        const initial_capacity: Hash = 4;

        allocator: heap.Allocator,
        metadata: ?[*]Metadata,
        size: Size,

        pub fn init(allocator: heap.Allocator) @This() {
            return Self{
                .allocator = allocator,
                .metadata = null,
                .size = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.metadata) |metadata| {
                self.freeBuffer(metadata);
                self.metadata = null;
            }
        }

        pub fn capacity(self: Self) Size {
            return self.header().capacity;
        }

        pub fn iterator(self: Self) Iterator {
            return Iterator{ .map = self, .index = 0 };
        }

        pub fn get(self: Self, key: K) ?V {
            if (self.getIndex(key)) |index| {
                return self.values()[index];
            }

            return null;
        }

        pub fn getPtr(self: Self, key: K) ?*V {
            if (self.getIndex(key)) |index| {
                return &self.values()[index];
            }

            return null;
        }

        pub fn getIndex(self: Self, key: K) ?usize {
            const metadata = self.metadata orelse return null;

            const mask = self.header().capacity - 1;
            const hash = Context.hash(key);
            const fingerprint = Metadata.takeFingerprint(hash);
            var index = hash & mask;
            var slot = metadata[index];
            var limit = self.header().capacity;
            while (!slot.isFree() and limit > 0) {
                const cur_key = self.keys()[index];
                const cur_fingerprint = slot.fingerprint;
                // Checking fingerprint is faster than function call
                // If fingerprint is different, then key is also for sure different
                if (cur_fingerprint == fingerprint and Context.eql(key, cur_key)) {
                    return index;
                }

                index = (index + 1) & mask;
                slot = metadata[index];
                limit -= 1;
            }

            return null;
        }

        pub fn getOrPut(self: *Self, key: K) error{OutOfMemory}!GetOrPutResult {
            try self.ensureUnusedCapacity();
            return self.getOrPutAssumeCapacity(key);
        }

        pub fn getOrPutAssumeCapacity(self: *Self, key: K) GetOrPutResult {
            const mask = self.header().capacity - 1;
            const hash = Context.hash(key);
            const fingerprint = Metadata.takeFingerprint(hash);
            var index = hash & mask;
            var slot = &self.metadata.?[index];
            var limit = self.header().capacity;
            var tombstone_idx = self.capacity();

            while (!slot.isFree() and limit > 0) {
                if (slot.isUsed() and slot.fingerprint == fingerprint) {
                    if (Context.eql(key, self.keys()[index])) {
                        return GetOrPutResult{
                            .key_ptr = &self.keys()[index],
                            .value_ptr = &self.values()[index],
                            .found_existing = true,
                        };
                    }
                } else if (tombstone_idx == self.capacity() and slot.isTombstone()) {
                    tombstone_idx = index;
                }

                index = (index + 1) & mask;
                slot = &self.metadata.?[index];
                limit -= 1;
            }

            if (tombstone_idx < self.capacity()) {
                index = tombstone_idx;
                slot = &self.metadata.?[index];
            }

            slot.markUsed(hash);
            self.keys()[index] = key;
            self.size += 1;
            return GetOrPutResult{
                .key_ptr = &self.keys()[index],
                .value_ptr = &self.values()[index],
                .found_existing = false,
            };
        }

        pub fn put(self: *Self, key: K, value: V) error{OutOfMemory}!void {
            try self.ensureUnusedCapacity();
            self.putAssumeCapacity(key, value);
        }

        pub fn putAssumeCapacity(self: *Self, key: K, value: V) void {
            const gop = self.getOrPutAssumeCapacity(key);
            gop.value_ptr.* = value;
        }

        pub fn remove(self: *Self, key: K) void {
            const mask = self.header().capacity - 1;
            const hash = Context.hash(key);
            const fingerprint = Metadata.takeFingerprint(hash);
            var index = hash & mask;
            var slot = &self.metadata.?[index];
            var limit = self.header().capacity;
            while (!slot.isFree() and limit > 0) {
                if (slot.isUsed() and slot.fingerprint == fingerprint) {
                    const cur_key = self.keys()[index];
                    if (Context.eql(key, cur_key)) {
                        slot.markTombstone();
                        self.size -= 1;
                        return;
                    }
                }

                index = (index + 1) & mask;
                slot = &self.metadata.?[index];
                limit -= 1;
            }
        }

        fn ensureUnusedCapacity(self: *Self) error{OutOfMemory}!void {
            if (self.metadata == null) {
                self.metadata = try self.allocBuffer(initial_capacity);
            } else if (self.size >= self.header().capacity) {
                const old_header = self.header().*;
                const old_capacity = old_header.capacity;
                const new_capacity = old_header.capacity << 1;
                const old_metadata = self.metadata.?;

                self.metadata = try self.allocBuffer(new_capacity);
                self.size = 0;

                const old_keys = old_header.keys;
                const old_values = old_header.values;
                for (old_metadata[0..old_capacity], 0..) |slot, i| {
                    if (slot.isUsed()) {
                        self.putAssumeCapacity(old_keys[i], old_values[i]);
                    }
                }

                self.freeBuffer(old_metadata);
            }
        }

        fn allocBuffer(self: Self, size: Hash) error{OutOfMemory}![*]Metadata {
            debug.assert(math.isPowerOfTwo(size));
            const keys_start, const values_start, const values_end = getBufferLen(size);
            const new_buf = try self.allocator.allocAligned(u8, values_end, @alignOf(Header));
            const h: *Header = @ptrCast(@alignCast(new_buf.ptr));
            h.* = .{
                .keys = @ptrFromInt(@intFromPtr(new_buf.ptr) + keys_start),
                .values = @ptrFromInt(@intFromPtr(new_buf.ptr) + values_start),
                .capacity = size,
            };

            const m: [*]Metadata = @ptrFromInt(@intFromPtr(new_buf.ptr) + @sizeOf(Header));
            @memset(m[0..size], Metadata{});

            return m;
        }

        fn freeBuffer(self: Self, metadata: [*]Metadata) void {
            const ptr: [*]u8 = @ptrFromInt(@intFromPtr(metadata) - @sizeOf(Header));
            _, _, const buffer_len = getBufferLen(self.header().capacity);
            self.allocator.free(ptr[0..buffer_len]);
        }

        fn getBufferLen(size: Size) struct { usize, usize, usize } {
            const header_len = @sizeOf(Header);
            const metadata_end = header_len + size * @sizeOf(Metadata);

            const keys_start = mem.alignForward(metadata_end, @alignOf(K));
            const keys_end = keys_start + size * @sizeOf(K);

            const values_start = mem.alignForward(keys_end, @alignOf(V));
            const values_end = values_start + size * @sizeOf(V);

            return .{ keys_start, values_start, values_end };
        }

        fn header(self: Self) *Header {
            return @ptrFromInt(@intFromPtr(self.metadata.?) - @sizeOf(Header));
        }

        fn keys(self: Self) []K {
            return self.header().keys[0..self.header().capacity];
        }

        fn values(self: Self) []V {
            return self.header().values[0..self.header().capacity];
        }
    };
}

test "basic usage" {
    const Key = struct {
        value: u32,

        pub fn eql(a: @This(), b: @This()) bool {
            return a.value == b.value;
        }

        pub fn hash(a: @This()) usize {
            return std.hash.Wyhash.hash(0, mem.asBytes(&a.value));
        }
    };

    var map = HashMap(Key, u32, DefaultContext).init(heap.page_allocator);
    defer map.deinit();

    try map.put(Key{ .value = 1 }, 1);
    try map.put(Key{ .value = 2 }, 2);
    try map.put(Key{ .value = 3 }, 3);
    try map.put(Key{ .value = 4 }, 4);
    try expect(map.get(Key{ .value = 1 })).toEqual(1);
    try expect(map.get(Key{ .value = 2 })).toEqual(2);
    try expect(map.get(Key{ .value = 3 })).toEqual(3);
    try expect(map.get(Key{ .value = 4 })).toEqual(4);
    try expect(map.size).toEqual(4);

    // Expands initial capacity
    try map.put(Key{ .value = 5 }, 5);

    try expect(map.get(Key{ .value = 1 })).toEqual(1);
    try expect(map.get(Key{ .value = 2 })).toEqual(2);
    try expect(map.get(Key{ .value = 3 })).toEqual(3);
    try expect(map.get(Key{ .value = 4 })).toEqual(4);
    try expect(map.get(Key{ .value = 5 })).toEqual(5);
    try expect(map.size).toEqual(5);

    // Overwrite existing
    try map.put(Key{ .value = 1 }, 10);
    try expect(map.get(Key{ .value = 1 })).toEqual(10);
    try expect(map.size).toEqual(5);

    // Delete a key
    map.remove(Key{ .value = 1 });
    try expect(map.get(Key{ .value = 1 })).toEqual(null);
    try expect(map.size).toEqual(4);

    // Set it back
    try map.put(Key{ .value = 1 }, 20);
    try expect(map.get(Key{ .value = 1 })).toEqual(20);
    try expect(map.size).toEqual(5);
}

test "hash collisions" {
    const Key = struct {
        value: u32,
    };
    const SimpleContext = struct {
        pub fn eql(a: Key, b: Key) bool {
            return a.value == b.value;
        }

        pub fn hash(a: Key) usize {
            // Just for testing for easier index manipulation
            return a.value;
        }
    };
    const SimpleHashMap = HashMap(Key, u32, SimpleContext);

    var map = SimpleHashMap.init(heap.page_allocator);
    defer map.deinit();

    // All those keys will be put sequentially because they result in the same hash
    try map.put(Key{ .value = 1 }, 1);
    try map.put(Key{ .value = 5 }, 5);
    try map.put(Key{ .value = 9 }, 9);

    try expect(map.metadata.?[0]).toEqual(SimpleHashMap.Metadata{ .fingerprint = 0, .used = false });
    try expect(map.metadata.?[1]).toEqual(SimpleHashMap.Metadata{ .fingerprint = 0, .used = true });
    try expect(map.metadata.?[2]).toEqual(SimpleHashMap.Metadata{ .fingerprint = 0, .used = true });
    try expect(map.metadata.?[3]).toEqual(SimpleHashMap.Metadata{ .fingerprint = 0, .used = true });
    try expect(map.get(Key{ .value = 1 })).toEqual(1);
    try expect(map.get(Key{ .value = 5 })).toEqual(5);
    try expect(map.get(Key{ .value = 9 })).toEqual(9);

    // Remove middle item
    // Now there is a gap between first and last item
    // Check if we can retrieve them anyway
    map.remove(Key{ .value = 5 });
    try expect(map.metadata.?[0]).toEqual(SimpleHashMap.Metadata{ .fingerprint = 0, .used = false });
    try expect(map.metadata.?[1]).toEqual(SimpleHashMap.Metadata{ .fingerprint = 0, .used = true });
    try expect(map.metadata.?[2]).toEqual(SimpleHashMap.Metadata{ .fingerprint = 1, .used = false });
    try expect(map.metadata.?[3]).toEqual(SimpleHashMap.Metadata{ .fingerprint = 0, .used = true });
    try expect(map.get(Key{ .value = 1 })).toEqual(1);
    try expect(map.get(Key{ .value = 5 })).toEqual(null);
    try expect(map.get(Key{ .value = 9 })).toEqual(9);

    // Tombstone should not prevent from updating last item
    try map.put(Key{ .value = 9 }, 19);
    try expect(map.metadata.?[0]).toEqual(SimpleHashMap.Metadata{ .fingerprint = 0, .used = false });
    try expect(map.metadata.?[1]).toEqual(SimpleHashMap.Metadata{ .fingerprint = 0, .used = true });
    try expect(map.metadata.?[2]).toEqual(SimpleHashMap.Metadata{ .fingerprint = 1, .used = false });
    try expect(map.metadata.?[3]).toEqual(SimpleHashMap.Metadata{ .fingerprint = 0, .used = true });
    try expect(map.get(Key{ .value = 1 })).toEqual(1);
    try expect(map.get(Key{ .value = 5 })).toEqual(null);
    try expect(map.get(Key{ .value = 9 })).toEqual(19);

    // Putting it back should also put it in the same spot
    try map.put(Key{ .value = 5 }, 15);
    try expect(map.metadata.?[0]).toEqual(SimpleHashMap.Metadata{ .fingerprint = 0, .used = false });
    try expect(map.metadata.?[1]).toEqual(SimpleHashMap.Metadata{ .fingerprint = 0, .used = true });
    try expect(map.metadata.?[2]).toEqual(SimpleHashMap.Metadata{ .fingerprint = 0, .used = true });
    try expect(map.metadata.?[3]).toEqual(SimpleHashMap.Metadata{ .fingerprint = 0, .used = true });
    try expect(map.get(Key{ .value = 1 })).toEqual(1);
    try expect(map.get(Key{ .value = 5 })).toEqual(15);
    try expect(map.get(Key{ .value = 9 })).toEqual(19);
}
