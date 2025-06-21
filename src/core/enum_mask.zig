const std = @import("std");
const expectEqual = std.testing.expectEqual;

fn getPaddingFieldsCount(comptime T: type) comptime_int {
    const BackingInt = @typeInfo(T).@"enum".tag_type;
    var required_paddings = 0;
    var next_value = 1;
    for (@typeInfo(T).@"enum".fields) |field| {
        if (field.value != next_value) {
            required_paddings += 1;
        }

        next_value = field.value * 2;
    }

    if (next_value < std.math.maxInt(BackingInt)) {
        required_paddings += 1;
    }

    return required_paddings;
}

fn getNumberOfBits(value: comptime_int) comptime_int {
    var cur_val = 1;
    var bits = 0;
    while (cur_val <= value) : (cur_val <<= 1) {
        if (value & cur_val != 0) {
            bits += 1;
        }
    }
    return bits;
}

const ZERO_VALUE: u64 = 0;
pub fn EnumMask(comptime T: type) type {
    if (@typeInfo(T) != .@"enum") {
        @compileError("EnumMask can only be used with enums");
    }

    const BackingInt = @typeInfo(T).@"enum".tag_type;
    const mask_len = @typeInfo(T).@"enum".fields.len + getPaddingFieldsCount(T);
    var fields: [mask_len]std.builtin.Type.StructField = .{
        std.builtin.Type.StructField{
            .name = "___padding0",
            .is_comptime = false,
            .type = @Type(std.builtin.Type{ .int = .{ .bits = 1, .signedness = .unsigned } }),
            .alignment = 0,
            .default_value_ptr = &ZERO_VALUE,
        },
    } ** mask_len;

    var bits_used = 0;
    var cur_value = 1;
    var i = 0;
    for (@typeInfo(T).@"enum".fields) |field| {
        if (field.value == 0) {
            @compileError("EnumMask can only be used with enums with non-zero values");
        }

        const padding_size = field.value - cur_value;
        if (padding_size > 0) {
            fields[i] = std.builtin.Type.StructField{
                .name = std.fmt.comptimePrint("___padding{d}", .{i}),
                .is_comptime = false,
                .type = @Type(std.builtin.Type{ .int = .{ .bits = getNumberOfBits(padding_size), .signedness = .unsigned } }),
                .alignment = 0,
                .default_value_ptr = &ZERO_VALUE,
            };
            bits_used += getNumberOfBits(padding_size);
            i += 1;
        }

        fields[i] = std.builtin.Type.StructField{
            .name = field.name,
            .is_comptime = false,
            .type = @Type(std.builtin.Type{ .int = .{ .bits = 1, .signedness = .unsigned } }),
            .alignment = 0,
            .default_value_ptr = &ZERO_VALUE,
        };
        bits_used += 1;
        cur_value <<= 1;
        i += 1;
    }

    const max_bits = @bitSizeOf(BackingInt);
    if (bits_used < max_bits) {
        fields[i] = std.builtin.Type.StructField{
            .name = "___paddinglast",
            .is_comptime = false,
            .type = @Type(std.builtin.Type{ .int = .{ .bits = max_bits - bits_used, .signedness = .unsigned } }),
            .alignment = 0,
            .default_value_ptr = &ZERO_VALUE,
        };
    }

    return @Type(std.builtin.Type{ .@"struct" = std.builtin.Type.Struct{
        .layout = .@"packed",
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
        .backing_integer = null,
    } });
}

test "EnumMask" {
    const Enum = enum(u8) {
        A = 1,
        B = 2,
        C = 4,
        D = 8,
        E = 16,
    };

    const Mask = EnumMask(Enum);
    const mask = Mask{ .A = 1, .B = 1, .C = 1, .D = 0, .E = 0, .___paddinglast = 0 };

    const sum: u8 = @intFromEnum(Enum.A) | @intFromEnum(Enum.B) | @intFromEnum(Enum.C);
    try expectEqual(sum, @as(u8, @bitCast(mask)));

    const Enum2 = enum(u8) {
        A = 1,
        B = 2,
        C = 8,
    };
    const Mask2 = EnumMask(Enum2);
    const mask2 = Mask2{ .A = 1, .B = 1, .___padding2 = 0, .C = 1, .___paddinglast = 0 };

    const sum2: u8 = @intFromEnum(Enum2.A) | @intFromEnum(Enum2.B) | @intFromEnum(Enum2.C);
    try expectEqual(sum2, @as(u8, @bitCast(mask2)));
}
