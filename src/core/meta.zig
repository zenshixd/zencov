const std = @import("std");
const builtin = @import("builtin");

const mem = @import("mem.zig");
const math = @import("math.zig");

pub const Type = std.builtin.Type;

pub fn ErrorSetFromEnum(comptime T: type) type {
    const info = @typeInfo(T);
    var names: [info.@"enum".fields.len]std.builtin.Type.Error = undefined;
    for (info.@"enum".fields, 0..) |field, i| {
        names[i].name = field.name;
    }

    return @Type(std.builtin.Type{
        .error_set = &names,
    });
}

pub fn ErrorSetEntry(comptime Enum: type, comptime ErrorSet: type) type {
    return struct {
        value: Enum,
        error_set: ErrorSet,
    };
}

pub fn createEnumToErrorSetTable(comptime Enum: type, comptime ErrorSet: type) [@typeInfo(Enum).@"enum".fields.len]ErrorSetEntry(Enum, ErrorSet) {
    const fields = @typeInfo(Enum).@"enum".fields;
    var map: [fields.len]ErrorSetEntry(Enum, ErrorSet) = undefined;
    for (fields, 0..) |field, i| {
        map[i] = .{
            .value = @enumFromInt(field.value),
            .error_set = @field(ErrorSet, field.name),
        };
    }
    return map;
}

/// Returns smallest int type that can hold `value`
/// Ints are rounded to multiples of 8
pub fn getIntType(value: anytype) type {
    const info = @typeInfo(@TypeOf(value));
    switch (info) {
        Type.int => return @TypeOf(value),
        Type.comptime_int => {
            comptime var bit_count = mem.BYTE_SIZE;
            inline while (true) : (bit_count += mem.BYTE_SIZE) {
                const int_type = @Type(Type{
                    .int = Type.Int{
                        .signedness = if (value > 0) std.builtin.Signedness.unsigned else std.builtin.Signedness.signed,
                        .bits = bit_count,
                    },
                });
                const truncated_value: int_type = @truncate(value);
                if (truncated_value == value) {
                    return int_type;
                }

                if (bit_count >= 65_535) {
                    @compileError("Integer type too large");
                }
            }
        },
        else => @compileError("Expected int, found " ++ @typeName(value)),
    }
}

pub fn Elem(comptime T: type) type {
    const info: Type = @typeInfo(T);
    switch (info) {
        Type.pointer => |ptr_info| {
            switch (ptr_info.size) {
                Type.Pointer.Size.one => {
                    const child_info = @typeInfo(ptr_info.child);
                    switch (child_info) {
                        Type.array => |arr_info| return arr_info.child,
                        else => @compileError("Invalid type passed to Elem: " ++ @typeName(T)),
                    }
                },
                Type.Pointer.Size.many, Type.Pointer.Size.slice, Type.Pointer.Size.c => return ptr_info.child,
            }
        },
        Type.array => |arr_info| return arr_info.child,
        Type.vector => |vec_info| return vec_info.child,
        else => @compileError("Invalid type passed to Elem: " ++ @typeName(T)),
    }
}

///
pub fn SliceTo(comptime T: type, comptime sentinel: Elem(T)) type {
    const info: Type = @typeInfo(T);
    var new_ptr_type = Type{
        .pointer = Type.Pointer{
            .size = Type.Pointer.Size.slice,
            .is_const = info.pointer.is_const,
            .is_volatile = info.pointer.is_volatile,
            .alignment = info.pointer.alignment,
            .is_allowzero = info.pointer.is_allowzero,
            .address_space = info.pointer.address_space,
            .child = Elem(T),
            .sentinel_ptr = null,
        },
    };

    if (info.pointer.sentinel()) |s| {
        if (s == sentinel) {
            new_ptr_type.pointer.sentinel_ptr = &sentinel;
        }
    }
    return @Type(new_ptr_type);
}
