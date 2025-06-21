const std = @import("std");

pub fn main() void {
    const slide = std.c._dyld_get_image_vmaddr_slide(0);
    std.log.info("slide: {x}", .{slide});
    if (slide <= 0) {
        std.log.info("slide is not set", .{});
    }
    std.log.info("base addr: {x}", .{0x10000000 + std.c._dyld_get_image_vmaddr_slide(0)});
    std.log.info("Hello, World! {x}", .{&main});
}
