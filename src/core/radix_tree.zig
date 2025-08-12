const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;

const expectEqual = std.testing.expectEqual;

pub const Prefix = struct {
    pos: u32,
    len: u32,

    pub fn format(self: Prefix, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Prefix{{ .pos = {d}, .len = {d} }}", .{ self.pos, self.len });
    }
};

const PrefixFormatter = struct {
    prefix: Prefix,
    string_bytes: []const u8,

    pub fn format(self: PrefixFormatter, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}", .{self.string_bytes[self.prefix.pos..][0..self.prefix.len]});
    }
};

pub const PrefixId = enum(u32) { _ };

pub fn RadixTree(comptime Data: type) type {
    return struct {
        const Self = @This();

        pub const Node = struct {
            key: PrefixId,
            next: ?*Node,
            child: ?*Node,
            // Sometimes during split, we create nodes not requested by user,
            // those nodes have null value
            value: ?Data,
        };

        gpa: mem.Allocator,
        string_table: std.ArrayListUnmanaged(Prefix),
        string_bytes: std.ArrayListUnmanaged(u8),
        nodes: std.SegmentedList(Node, 2),

        // Initializes a new tree.
        pub fn init(gpa: mem.Allocator) error{OutOfMemory}!Self {
            var tree = Self{
                .gpa = gpa,
                .string_table = .empty,
                .string_bytes = .empty,
                .nodes = .{},
            };
            const prefix = try tree.pushPrefix("");
            _ = try tree.newNode(prefix);
            return tree;
        }

        // Frees all memory used by the tree.
        pub fn deinit(self: *Self) void {
            self.string_table.deinit(self.gpa);
            self.string_bytes.deinit(self.gpa);
            self.nodes.deinit(self.gpa);
        }

        // When searching - we want `key` to always be bigger than `prefix`
        pub fn get(self: Self, key: []const u8) ?Data {
            var key_index: usize = 0;
            var node: ?*const Node = self.nodes.at(0);
            while (node) |n| {
                const cur_prefix = self.getPrefix(n.key);
                // When finding match index there are few options:
                // 1. prefix is bigger than key - no match, go next
                // 2. prefix is smaller or equal than key:
                //  3. if match_index == prefix.len:
                //      3a. If prefix.len == key.len - key_index - match, return value
                //      3b. If prefix.len < key.len - key_index - partial match, go to child
                //  4. If match_index < prefix.len - no match, go to next
                if (cur_prefix.len > key.len - key_index) {
                    node = n.next;
                    continue;
                }

                const match_index = findMatchIndex(key[key_index..], cur_prefix);
                if (match_index == cur_prefix.len) {
                    if (cur_prefix.len == key.len - key_index) {
                        return n.value;
                    }

                    key_index += cur_prefix.len;
                    node = n.child;
                    continue;
                }

                node = n.next;
            }

            return null;
        }

        // Puts new value into the tree
        // Scnarios:
        // 1. Its brand new prefix - new node at root level is added
        // 2. Its a prefix to some other nodes in tree
        //    - add key to string_bytes
        //    - add new node
        //    - redo keys for existing nodes <- is there ever a case when there is more than 1 node with the same prefix ???
        //    - what do i do with existing keys ??? i could just abandon the prefix ??? rehashing???
        // 3. Prefix of new node is already in tree
        //    - cut prefix out
        //    - add remaining to string_bytes
        //    - add new node
        // 4. There is a node which shares the prefix - but prefix itself is not a separate node
        //    - create prefix node first
        //    - rehash prefix for existing node <- in this step we only have one node ??? or more
        //    - add new node
        pub fn put(self: *Self, new_prefix: []const u8, value: Data) error{OutOfMemory}!*Node {
            var new_prefix_offset: usize = 0;
            var node: ?*Node = self.nodes.at(0);

            while (node) |n| {
                const cur_prefix = self.getPrefix(n.key);
                const match_index = findMatchIndex(new_prefix[new_prefix_offset..], cur_prefix);

                if (match_index == cur_prefix.len) {
                    // Entire cur_prefix is matched
                    // We have 2 options:
                    // - cur_node is the one we search for
                    // - we go deeper into the tree if possible
                    // - otherwise set new_node as child
                    if (cur_prefix.len == new_prefix.len - new_prefix_offset) {
                        // Node exists, just change value
                        n.value = value;
                        return n;
                    }

                    if (cur_prefix.len < new_prefix.len - new_prefix_offset) {
                        if (n.child) |child| {
                            new_prefix_offset += cur_prefix.len;
                            node = child;
                            continue;
                        }

                        const new_prefix_id = try self.pushPrefix(new_prefix[new_prefix_offset + match_index ..]);
                        const new_node = try self.newNode(new_prefix_id);
                        new_node.value = value;

                        n.child = new_node;
                        return new_node;
                    }
                }

                if (match_index == new_prefix.len - new_prefix_offset) {
                    // Split cur_prefix into shared prefix and remaining prefix
                    // adjust current node becomes our "new" node
                    // Add new node for remaining part of prefix
                    const shared_prefix_id = try self.splitPrefix(n.key, match_index);

                    const remaining_node = try self.newNode(shared_prefix_id);
                    remaining_node.child = n.child;
                    remaining_node.value = n.value;
                    remaining_node.next = n.next;

                    n.next = null;
                    n.child = remaining_node;
                    n.value = value;

                    return n;
                }

                if (match_index > 0) {
                    // Split cur_prefix
                    // New shared prefix is parent for both cur node and new node
                    const new_prefix_id = try self.pushPrefix(new_prefix[new_prefix_offset + match_index ..]);
                    const new_node = try self.newNode(new_prefix_id);
                    new_node.next = n.next;
                    new_node.value = value;

                    const remaining_prefix_id = try self.splitPrefix(n.key, match_index);
                    const remaining_prefix_node = try self.newNode(remaining_prefix_id);
                    remaining_prefix_node.next = new_node;
                    remaining_prefix_node.child = n.child;
                    remaining_prefix_node.value = n.value;

                    n.child = remaining_prefix_node;
                    n.next = null;
                    n.value = null;

                    return new_node;
                }

                node = n.next orelse break;
            }

            // No split needed, just add new node next to the current one
            const new_prefix_id = try self.pushPrefix(new_prefix[new_prefix_offset..]);
            const new_node = try self.newNode(new_prefix_id);
            new_node.value = value;

            node.?.next = new_node;
            return new_node;
        }

        fn newNode(self: *Self, prefix: PrefixId) error{OutOfMemory}!*Node {
            const node = try self.nodes.addOne(self.gpa);
            node.* = .{
                .key = prefix,
                .next = null,
                .child = null,
                .value = null,
            };
            return node;
        }

        fn getPrefix(self: Self, prefix_id: PrefixId) []const u8 {
            const prefix = self.string_table.items[@intFromEnum(prefix_id)];
            return self.string_bytes.items[prefix.pos..][0..prefix.len];
        }

        fn pushPrefix(self: *Self, prefix: []const u8) error{OutOfMemory}!PrefixId {
            const id = self.string_table.items.len;
            const pos = self.string_bytes.items.len;
            try self.string_table.append(self.gpa, .{
                .pos = @intCast(pos),
                .len = @intCast(prefix.len),
            });
            try self.string_bytes.appendSlice(self.gpa, prefix);
            return @enumFromInt(id);
        }

        // Splits old_prefix_id at `at`
        // `old_prefix_id` is adjusted to left side of split
        // Returns right side of prefix
        fn splitPrefix(self: *Self, old_prefix_id: PrefixId, at: usize) error{OutOfMemory}!PrefixId {
            const old_prefix = &self.string_table.items[@intFromEnum(old_prefix_id)];
            assert(at < old_prefix.len);

            const new_prefix_id = self.string_table.items.len;
            try self.string_table.append(self.gpa, .{
                .pos = @intCast(old_prefix.pos + at),
                .len = @intCast(old_prefix.len - at),
            });

            old_prefix.len = @intCast(at);
            return @enumFromInt(new_prefix_id);
        }

        // Is b contained in a ?
        fn findMatchIndex(a: []const u8, b: []const u8) usize {
            var i: usize = 0;
            const len = if (a.len < b.len) a.len else b.len;
            while (i < len) : (i += 1) {
                if (a[i] != b[i]) {
                    break;
                }
            }
            return i;
        }
    };
}

test "basic usage, no splitting existing nodes" {
    var tree = try RadixTree(i32).init(std.testing.allocator);
    defer tree.deinit();

    _ = try tree.put("foo", 1);
    _ = try tree.put("bar", 2);
    _ = try tree.put("foobar", 3);
    _ = try tree.put("foobarbaz", 4);

    try expectEqual(1, tree.get("foo"));
    try expectEqual(2, tree.get("bar"));
    try expectEqual(3, tree.get("foobar"));
    try expectEqual(4, tree.get("foobarbaz"));
}

test "split existing node" {
    var tree = try RadixTree(i32).init(std.testing.allocator);
    defer tree.deinit();

    _ = try tree.put("aaa", 1);
    _ = try tree.put("aab", 2);
    _ = try tree.put("aac", 3);
    _ = try tree.put("aad", 4);

    try expectEqual(1, tree.get("aaa"));
    try expectEqual(2, tree.get("aab"));
    try expectEqual(3, tree.get("aac"));
    try expectEqual(4, tree.get("aad"));
}

test "split long node" {
    var tree = try RadixTree(i32).init(std.testing.allocator);
    defer tree.deinit();

    _ = try tree.put("abcde", 1);
    _ = try tree.put("ab", 2);

    try expectEqual(1, tree.get("abcde"));
    try expectEqual(2, tree.get("ab"));
}

test "change value for existing node" {
    var tree = try RadixTree(i32).init(std.testing.allocator);
    defer tree.deinit();

    _ = try tree.put("abc", 1);
    _ = try tree.put("abc", 2);

    try expectEqual(2, tree.get("abc"));
    try expectEqual(null, tree.get("ab"));
}
