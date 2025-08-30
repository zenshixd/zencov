const std = @import("std");
const mem = @import("../core/mem.zig");
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
            if (!mem.compare(T, self.value, expected)) {
                debug.print("expected {}, found {}\n", .{ expected, self.value });
                return error.TestExpectedEqual;
            }
        }

        pub fn toEqualBytes(self: Self, expected: anytype) error{TestExpectedEqual}!void {
            return self.sliceEqual(expected);
        }

        pub fn startsWith(self: Self, expected: T) error{TestExpectedEqual}!void {
            const info = @typeInfo(T);
            if (info != meta.Type.pointer or info.pointer.size != meta.Type.Pointer.Size.slice) {
                @compileError("startsWith only works on slices");
            }
            return std.testing.expectStringStartsWith(self.value, expected) catch |err| switch (err) {
                error.TestExpectedStartsWith => return error.TestExpectedEqual,
            };
        }

        pub fn not(self: Self) Self {
            return Expect(T){ .value = self.value, .negated = true };
        }

        fn sliceEqual(self: Self, expected: anytype) error{TestExpectedEqual}!void {
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
