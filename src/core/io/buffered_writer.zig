const ArrayList = @import("../array_list.zig").ArrayList;
const io = @import("../io.zig");

pub const BufferedWriter = struct {
    const Self = @This();

    pub fn init(comptime buffer_size: usize, file: io.File) Self {
        return .{
            .buffer = core.ArrayList(u8).init(file.allocator),
            .file = file,
            .buffer_size = buffer_size,
        };
    }
};
