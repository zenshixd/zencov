const std = @import("std");
const core = @import("../../core.zig");
const assert = std.debug.assert;
const builtin = @import("builtin");

pub const ReturnCode = enum(i32) { ok = 0, fail = -1, _ };
pub const PID = enum(i32) {
    current = 0,
    _,

    pub fn wait(self: PID, options: i32) !Status {
        var status: i32 = undefined;
        try errno(waitpid(self, &status, options));
        return @enumFromInt(status);
    }
};
pub const Status = enum(i32) {
    _,

    pub fn EXITSTATUS(s: Status) u8 {
        return @as(u8, @intCast((@intFromEnum(s) & 0xff00) >> 8));
    }
    pub fn TERMSIG(s: Status) u32 {
        return @intCast(@intFromEnum(s) & 0x7f);
    }
    pub fn STOPSIG(s: Status) u32 {
        return EXITSTATUS(s);
    }
    pub fn IFEXITED(s: Status) bool {
        return TERMSIG(s) == 0;
    }
    pub fn IFSTOPPED(s: Status) bool {
        return @as(u16, @truncate(((@intFromEnum(s) & 0xffff) *% 0x10001) >> 8)) > 0x7f00;
    }
    pub fn IFSIGNALED(s: Status) bool {
        return (@intFromEnum(s) & 0xffff) -% 1 < 0xff;
    }
};
pub const FD = enum(i32) { _ };
pub const Mode = switch (builtin.os.tag) {
    .linux => u32,
    .macos => u16,
    else => @compileError("Unsupported OS"),
};

pub const W = struct {
    pub const NOHANG = 1;
    pub const UNTRACED = 2;
    pub const STOPPED = 2;
    pub const EXITED = 4;
    pub const CONTINUED = 8;
    pub const NOWAIT = 0x1000000;
};
pub extern "c" fn waitpid(pid: PID, status: *i32, options: i32) ReturnCode;

pub const SigSet = [1024 / 32]u32;
const sigset_len = @typeInfo(SigSet).array.len;
pub const empty_sigset = [_]u32{0} ** sigset_len;
pub const filled_sigset = [_]u32{(1 << (31 & (@bitSizeOf(usize) - 1))) - 1} ++ [_]u32{0} ** (sigset_len - 1);
pub const SpawnFileActions = struct {
    pub const Ref = *opaque {};
    ref: Ref,
    pub fn init() !SpawnFileActions {
        var actions: SpawnFileActions = undefined;
        try errno(internal.posix_spawn_file_actions_init(&actions.ref));
        return actions;
    }

    pub fn destroy(self: *SpawnFileActions) !void {
        try errno(internal.posix_spawn_file_actions_destroy(self));
    }

    pub fn addOpen(self: *SpawnFileActions, fd: FD, path: [*:0]const u8, oflag: i32, mode: Mode) !void {
        try errno(internal.posix_spawn_file_actions_addopen(&self.ref, fd, path, oflag, mode));
    }

    pub fn addClose(self: *SpawnFileActions, fd: FD) !void {
        try errno(internal.posix_spawn_file_actions_addclose(&self.ref, fd));
    }

    pub fn addDup2(self: *SpawnFileActions, fd: FD, new_fd: FD) !void {
        try errno(internal.posix_spawn_file_actions_adddup2(&self.ref, fd, new_fd));
    }

    pub fn addInherit(self: *SpawnFileActions, fd: FD) !void {
        try errno(internal.posix_spawn_file_actions_addinherit_np(&self.ref, fd));
    }
};

pub const SPAWN_RESETIDS = 0x0001;
pub const SPAWN_SETPGROUP = 0x0002;
pub const SPAWN_SETSIGDEF = 0x0004;
pub const SPAWN_SETSIGMASK = 0x0008;
pub const SPAWN_START_SUSPENDED = 0x0080;

pub const SpawnAttr = struct {
    pub const Ref = *opaque {};
    ref: Ref,
    pub fn init() !SpawnAttr {
        var attr: SpawnAttr = undefined;
        try errno(internal.posix_spawnattr_init(&attr.ref));
        return attr;
    }

    pub fn destroy(self: *SpawnAttr) !void {
        try errno(internal.posix_spawnattr_destroy(&self.ref));
    }

    pub fn getFlags(self: *const SpawnAttr) !i16 {
        var flags: i16 = undefined;
        try errno(internal.posix_spawnattr_getflags(&self.ref, &flags));
        return flags;
    }

    pub fn setFlags(self: *SpawnAttr, flags: i16) !void {
        try errno(internal.posix_spawnattr_setflags(&self.ref, flags));
    }

    pub fn getSigDefault(self: *const SpawnAttr) !SigSet {
        var sigdef: u32 = undefined;
        try errno(internal.posix_spawnattr_getsigdefault(&self.ref, &sigdef));
        return sigdef;
    }

    pub fn setSigDefault(self: *SpawnAttr, sigdef: SigSet) !void {
        try errno(internal.posix_spawnattr_setsigdefault(&self.ref, &sigdef));
    }

    pub fn getSigMask(self: *const SpawnAttr) !SigSet {
        var sigmask: u32 = undefined;
        try errno(internal.posix_spawnattr_getsigmask(&self.ref, &sigmask));
        return sigmask;
    }

    pub fn setSigMask(self: *SpawnAttr, sigmask: SigSet) !void {
        try errno(internal.posix_spawnattr_setsigmask(&self.ref, &sigmask));
    }

    pub fn getProcessGroup(self: *const SpawnAttr) !PID {
        var pid: PID = undefined;
        try errno(internal.posix_spawnattr_getpgroup(&self.ref, &pid));
        return pid;
    }

    pub fn setProcessGroup(self: *SpawnAttr, pid: *const PID) !void {
        try errno(internal.posix_spawnattr_setpgroup(&self.ref, pid));
    }
};

pub fn spawn(argv: [*:null]const ?[*:0]const u8, file_actions: ?SpawnFileActions, attrp: ?SpawnAttr, envp: [*:null]const ?[*:0]const u8) !PID {
    var pid: PID = undefined;
    const file_actions_ref = if (file_actions) |fa| &fa.ref else null;
    const attrp_ref = if (attrp) |a| &a.ref else null;
    const exec = argv[0] orelse return error.ArgvNotProvided;
    try errno(internal.posix_spawn(&pid, exec, file_actions_ref, attrp_ref, argv[1..], envp));
    return pid;
}

const internal = struct {
    pub extern "c" fn posix_spawnattr_init(attr: *SpawnAttr.Ref) ReturnCode;
    pub extern "c" fn posix_spawnattr_destroy(attr: *SpawnAttr.Ref) ReturnCode;
    pub extern "c" fn posix_spawnattr_setflags(attr: *SpawnAttr.Ref, flags: i16) ReturnCode;
    pub extern "c" fn posix_spawnattr_getflags(attr: *const SpawnAttr.Ref, flags: *i16) ReturnCode;
    pub extern "c" fn posix_spawnattr_getsigdefault(attr: *const SpawnAttr.Ref, sigdef: *u32) ReturnCode;
    pub extern "c" fn posix_spawnattr_setsigdefault(attr: *SpawnAttr.Ref, sig: *const SigSet) ReturnCode;
    pub extern "c" fn posix_spawnattr_getsigmask(attr: *const SpawnAttr.Ref, sigmask: *u32) ReturnCode;
    pub extern "c" fn posix_spawnattr_setsigmask(attr: *SpawnAttr.Ref, sigmask: *const SigSet) ReturnCode;
    pub extern "c" fn posix_spawnattr_getpgroup(attr: *const SpawnAttr.Ref, pid: *PID) ReturnCode;
    pub extern "c" fn posix_spawnattr_setpgroup(attr: *SpawnAttr.Ref, pid: *const PID) ReturnCode;
    pub extern "c" fn posix_spawn_file_actions_init(actions: *SpawnFileActions.Ref) ReturnCode;
    pub extern "c" fn posix_spawn_file_actions_destroy(actions: *SpawnFileActions.Ref) ReturnCode;
    pub extern "c" fn posix_spawn_file_actions_addclose(actions: *SpawnFileActions.Ref, fd: FD) ReturnCode;
    pub extern "c" fn posix_spawn_file_actions_addopen(
        actions: *SpawnFileActions.Ref,
        filedes: FD,
        path: [*:0]const u8,
        oflag: i32,
        mode: Mode,
    ) ReturnCode;
    pub extern "c" fn posix_spawn_file_actions_adddup2(
        actions: *SpawnFileActions.Ref,
        fd: FD,
        new_fd: FD,
    ) ReturnCode;
    pub extern "c" fn posix_spawn_file_actions_addinherit_np(actions: *SpawnFileActions.Ref, filedes: FD) ReturnCode;
    pub extern "c" fn posix_spawn(
        pid: *PID,
        path: [*:0]const u8,
        file_actions: ?*const SpawnFileActions.Ref,
        attrp: ?*const SpawnAttr.Ref,
        argv: [*:null]const ?[*:0]const u8,
        envp: [*:null]const ?[*:0]const u8,
    ) ReturnCode;

    extern "c" fn __error() *ErrnoCodes;

    pub const errno_internal = switch (builtin.os.tag) {
        .macos => __error,
        else => @compileError("Unsupported OS"),
    };
};
pub fn errno(rc: ReturnCode) ErrnoError!void {
    if (rc != .fail) {
        return;
    }

    const code = internal.errno_internal();
    assert(@intFromEnum(code.*) > 0);
    return switch (code.*) {
        .OK => {},
        inline else => |tag| {
            // HUH ? why do i need to change quota here ???? there isnt that many values
            @setEvalBranchQuota(6000);
            inline for (errnoToErrorMap) |entry| {
                if (entry.value == tag) {
                    return entry.error_set;
                }
            }
            unreachable;
        },
    };
}

const errnoToErrorMap = core.createEnumToErrorSetTable(ErrnoCodes, ErrnoError);
pub const ErrnoError = core.ErrorSetFromEnum(ErrnoCodes);
pub const ErrnoCodes = enum(i32) {
    OK = 0,
    // Basic error codes
    EPERM = 1, // Operation not permitted
    ENOENT = 2, // No such file or directory
    ESRCH = 3, // No such process
    EINTR = 4, // Interrupted system call
    EIO = 5, // Input/output error
    ENXIO = 6, // Device not configured
    E2BIG = 7, // Argument list too long
    ENOEXEC = 8, // Exec format error
    EBADF = 9, // Bad file descriptor
    ECHILD = 10, // No child processes
    EDEADLK = 11, // Resource deadlock avoided
    ENOMEM = 12, // Cannot allocate memory
    EACCES = 13, // Permission denied
    EFAULT = 14, // Bad address
    ENOTBLK = 15, // Block device required
    EBUSY = 16, // Device / Resource busy
    EEXIST = 17, // File exists
    EXDEV = 18, // Cross-device link
    ENODEV = 19, // Operation not supported by device
    ENOTDIR = 20, // Not a directory
    EISDIR = 21, // Is a directory
    EINVAL = 22, // Invalid argument
    ENFILE = 23, // Too many open files in system
    EMFILE = 24, // Too many open files
    ENOTTY = 25, // Inappropriate ioctl for device
    ETXTBSY = 26, // Text file busy
    EFBIG = 27, // File too large
    ENOSPC = 28, // No space left on device
    ESPIPE = 29, // Illegal seek
    EROFS = 30, // Read-only file system
    EMLINK = 31, // Too many links
    EPIPE = 32, // Broken pipe

    // Math software
    EDOM = 33, // Numerical argument out of domain
    ERANGE = 34, // Result too large

    // Non-blocking and interrupt I/O
    EAGAIN = 35, // Resource temporarily unavailable
    EINPROGRESS = 36, // Operation now in progress
    EALREADY = 37, // Operation already in progress

    // IPC/network software - argument errors
    ENOTSOCK = 38, // Socket operation on non-socket
    EDESTADDRREQ = 39, // Destination address required
    EMSGSIZE = 40, // Message too long
    EPROTOTYPE = 41, // Protocol wrong type for socket
    ENOPROTOOPT = 42, // Protocol not available
    EPROTONOSUPPORT = 43, // Protocol not supported
    ESOCKTNOSUPPORT = 44, // Socket type not supported
    EOPNOTSUPP = 45, // Operation not supported on socket
    EPFNOSUPPORT = 46, // Protocol family not supported
    EAFNOSUPPORT = 47, // Address family not supported by protocol family
    EADDRINUSE = 48, // Address already in use
    EADDRNOTAVAIL = 49, // Can't assign requested address

    // IPC/network software - operational errors
    ENETDOWN = 50, // Network is down
    ENETUNREACH = 51, // Network is unreachable
    ENETRESET = 52, // Network dropped connection on reset
    ECONNABORTED = 53, // Software caused connection abort
    ECONNRESET = 54, // Connection reset by peer
    ENOBUFS = 55, // No buffer space available
    EISCONN = 56, // Socket is already connected
    ENOTCONN = 57, // Socket is not connected
    ESHUTDOWN = 58, // Can't send after socket shutdown
    ETOOMANYREFS = 59, // Too many references: can't splice
    ETIMEDOUT = 60, // Operation timed out
    ECONNREFUSED = 61, // Connection refused

    // Filesystem errors
    ELOOP = 62, // Too many levels of symbolic links
    ENAMETOOLONG = 63, // File name too long
    EHOSTDOWN = 64, // Host is down
    EHOSTUNREACH = 65, // No route to host
    ENOTEMPTY = 66, // Directory not empty

    // Quotas & resource limits
    EPROCLIM = 67, // Too many processes
    EUSERS = 68, // Too many users
    EDQUOT = 69, // Disc quota exceeded

    // Network File System
    ESTALE = 70, // Stale NFS file handle
    EREMOTE = 71, // Too many levels of remote in path
    EBADRPC = 72, // RPC struct is bad
    ERPCMISMATCH = 73, // RPC version wrong
    EPROGUNAVAIL = 74, // RPC prog. not avail
    EPROGMISMATCH = 75, // Program version wrong
    EPROCUNAVAIL = 76, // Bad procedure for program

    // Other
    ENOLCK = 77, // No locks available
    ENOSYS = 78, // Function not implemented
    EFTYPE = 79, // Inappropriate file type or format
    EAUTH = 80, // Authentication error
    ENEEDAUTH = 81, // Need authenticator

    // Device errors
    EPWROFF = 82, // Device power is off
    EDEVERR = 83, // Device error, e.g. paper out
    EOVERFLOW = 84, // Value too large to be stored in data type

    // Program loading errors
    EBADEXEC = 85, // Bad executable
    EBADARCH = 86, // Bad CPU type in executable
    ESHLIBVERS = 87, // Shared library version mismatch
    EBADMACHO = 88, // Malformed Macho file

    // Operation control
    ECANCELED = 89, // Operation canceled

    // IPC errors
    EIDRM = 90, // Identifier removed
    ENOMSG = 91, // No message of desired type
    EILSEQ = 92, // Illegal byte sequence
    ENOATTR = 93, // Attribute not found
    EBADMSG = 94, // Bad message
    EMULTIHOP = 95, // Reserved
    ENODATA = 96, // No message available on STREAM
    ENOLINK = 97, // Reserved
    ENOSR = 98, // No STREAM resources
    ENOSTR = 99, // Not a STREAM
    EPROTO = 100, // Protocol error
    ETIME = 101, // STREAM ioctl timeout
    ENOPOLICY = 103, // No such policy registered
    ENOTRECOVERABLE = 104, // State not recoverable
    EOWNERDEAD = 105, // Previous owner died
    EQFULL = 106, // Interface output queue is full
};
