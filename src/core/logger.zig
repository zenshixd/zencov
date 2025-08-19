const std = @import("std");
const io = @import("./io.zig");

pub const LogLevel = enum {
    err,
    warn,
    info,
    debug,
};

const Logger = struct {
    scope: @Type(.enum_literal) = .default,

    pub fn err(self: Logger, comptime format: []const u8, args: anytype) void {
        self.logExtra(.err, format, args);
    }

    pub fn warn(self: Logger, comptime format: []const u8, args: anytype) void {
        self.logExtra(.warn, format, args);
    }

    pub fn info(self: Logger, comptime format: []const u8, args: anytype) void {
        self.logExtra(.info, format, args);
    }

    pub fn debug(self: Logger, comptime format: []const u8, args: anytype) void {
        self.logExtra(.debug, format, args);
    }

    pub fn scoped(_: Logger, comptime scope: @Type(.enum_literal)) Logger {
        return Logger{
            .scope = scope,
        };
    }

    pub fn logExtra(
        self: Logger,
        comptime level: LogLevel,
        comptime format: []const u8,
        args: anytype,
    ) void {
        const prefix1 = if (self.scope == .default) "" else "[" ++ @tagName(self.scope) ++ "] ";
        const prefix2 = switch (level) {
            .err => "error: ",
            .warn => "warning: ",
            .info => "",
            .debug => "debug: ",
        };
        var stream = stream: {
            if (level == .err) {
                break :stream io.getStderr();
            }

            break :stream io.getStdout();
        };

        stream.print(prefix1 ++ prefix2 ++ format ++ "\n", args) catch return;
        stream.flush() catch return;
    }
};

const default_logger = Logger{};

pub fn err(comptime format: []const u8, args: anytype) void {
    default_logger.logExtra(.err, format, args);
}

pub fn warn(comptime format: []const u8, args: anytype) void {
    default_logger.logExtra(.warn, format, args);
}

pub fn info(comptime format: []const u8, args: anytype) void {
    default_logger.logExtra(.info, format, args);
}

pub fn debug(comptime format: []const u8, args: anytype) void {
    default_logger.logExtra(.debug, format, args);
}

pub fn scoped(_: *Logger, comptime scope: @Type(.enum_literal)) Logger {
    return default_logger.scoped(scope);
}
