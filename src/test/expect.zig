const std = @import("std");
const debug = @import("../core/debug.zig");
const meta = @import("../core/meta.zig");

pub fn expect(actual: anytype) Expect(@TypeOf(actual)) {
    return Expect(@TypeOf(actual)){ .value = actual };
}

pub fn Expect(comptime T: type) type {
    return struct {
        const Self = @This();
        value: T,
        negated: bool = false,

        pub fn toEqual(self: Self, expected: T) error{TestExpectedEqual}!void {
            const info = @typeInfo(T);
            if (info == meta.Type.pointer and info.pointer.size == meta.Type.Pointer.Size.slice) {
                return try self.sliceEqual(expected);
            }
            return std.testing.expectEqual(expected, self.value);
        }

        pub fn not(self: Self) Self {
            return Expect(T){ .value = self.value, .negated = true };
        }

        fn sliceEqual(self: Self, expected: T) error{TestExpectedEqual}!void {
            var equals = true;
            for (self.value, 0..) |a, i| {
                const other = expected[i];
                if (a != other) {
                    equals = false;
                    break;
                }
            }

            if (equals == self.negated) {
                debug.print("expected slice {}, found {}\n", .{ expected, self.value });
                return error.TestExpectedEqual;
            }
        }
    };
}
