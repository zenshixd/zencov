const std = @import("std");
const other_file = @import("other.zig");

pub fn main() void {
    var slide = std.c._dyld_get_image_vmaddr_slide(0);
    if (slide <= 0) {
        slide = 0;
    }
    slide += 1;
    _ = other_file.testFn(slide);
}
