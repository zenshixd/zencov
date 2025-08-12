const std = @import("std");

pub const File = std.fs.File;

pub fn getStdin() File {
    return std.io.getStdIn();
}

pub fn getStdout() File {
    return std.io.getStdOut();
}

pub fn getStderr() File {
    return std.io.getStdErr();
}
