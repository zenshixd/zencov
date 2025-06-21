const std = @import("std");

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
