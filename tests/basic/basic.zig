const std = @import("std");

pub fn main() void {
    var slide = std.c._dyld_get_image_vmaddr_slide(0);
    if (slide <= 0) {
        slide = 0;
    }
    slide += 1;
}
