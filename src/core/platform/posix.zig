const core = @import("../../core.zig");
const mem = @import("../../core/mem.zig");
const builtin = @import("builtin");

pub const ReturnCode = enum(i32) { ok = 0, fail = -1, _ };

pub fn getcwd(buf: []u8) error{ AccessDenied, CurrentWorkingDirectoryUnlinked, NameTooLong, BufferIsZero, OutOfMemory }![]const u8 {
    const result = internal.getcwd(buf.ptr, buf.len);
    if (result) |r| {
        return mem.sliceTo(r, 0);
    }

    return switch (errno(ReturnCode.fail)) {
        ErrnoCodes.EACCES => error.AccessDenied,
        ErrnoCodes.ENOENT => error.CurrentWorkingDirectoryUnlinked,
        ErrnoCodes.ERANGE => error.NameTooLong,
        ErrnoCodes.EINVAL => error.BufferIsZero,
        ErrnoCodes.ENOMEM => error.OutOfMemory,
        else => unreachable,
    };
}

pub const MemProt = core.EnumMask(enum(i32) {
    read = 0x01,
    write = 0x02,
    exec = 0x04,

    pub const none = 0x00;
});
pub const MmapFlags = core.EnumMask(enum(i32) {
    shared = 0x01,
    private = 0x02,
    fixed = 0x10,
    anonymous = 0x20,
});

const MAP_FAILED = @as([*]u8, -1);

pub const MmapError = error{
    AccessDenied,
    BadFileDescriptor,
    AlreadyExists,
    InvalidArgument,
    OpenFileLimitReached,
    OutOfMemory,
    OffsetOutOfRange,
};

pub fn mmap(addr: ?[*]u8, len: usize, prot: MemProt, flags: MmapFlags, fd: i32, offset: usize) MmapError!void {
    const rc = internal.mmap(addr, len, @bitCast(prot), @bitCast(flags), fd, offset);
    switch (errno(rc)) {
        ErrnoCodes.OK => {},
        ErrnoCodes.EPERM => return error.AccessDenied,
        ErrnoCodes.EBADF => return error.BadFileDescriptor,
        ErrnoCodes.EEXIST => return error.AlreadyExists,
        ErrnoCodes.EINVAL => return error.InvalidArgument,
        ErrnoCodes.ENFILE => return error.OpenFileLimitReached,
        ErrnoCodes.ENOMEM => return error.OutOfMemory,
        ErrnoCodes.EOVERFLOW => return error.OffsetOutOfRange,
        else => unreachable,
    }
    return @as([*]u8, @ptrFromInt(@intFromEnum(rc)))[0..len];
}

pub fn munmap(addr: ?[*]u8, len: usize) MmapError!void {
    const rc = internal.munmap(addr, len);
    switch (errno(rc)) {
        ErrnoCodes.OK => {},
        ErrnoCodes.EPERM => return error.AccessDenied,
        ErrnoCodes.EBADF => return error.BadFileDescriptor,
        ErrnoCodes.EEXIST => return error.AlreadyExists,
        ErrnoCodes.EINVAL => return error.InvalidArgument,
        ErrnoCodes.ENFILE => return error.OpenFileLimitReached,
        ErrnoCodes.ENOMEM => return error.OutOfMemory,
        ErrnoCodes.EOVERFLOW => return error.OffsetOutOfRange,
        else => unreachable,
    }
}

pub const MremapFlags = core.EnumMask(enum(i32) {
    maymove = 0x1,
    fixed = 0x2,
    dont_unmap = 0x4,
});

pub const MremapError = error{
    RegionLocked,
    InvalidAddress,
    InvalidArgument,
    OutOfMemory,
};

pub fn mremap(old_addr: ?[*]u8, old_size: usize, new_size: usize, flags: MremapFlags, new_addr: ?*[*]u8) MremapError![]u8 {
    const rc = internal.mremap(old_addr, old_size, new_size, flags, new_addr);
    switch (errno(rc)) {
        ErrnoCodes.OK => {},
        ErrnoCodes.EAGAIN => return error.RegionLocked,
        ErrnoCodes.EFAULT => return error.InvalidAddress,
        ErrnoCodes.EINVAL => return error.InvalidArgument,
        ErrnoCodes.ENOMEM => return error.OutOfMemory,
        else => unreachable,
    }
    return @as([*]u8, @ptrFromInt(@intFromEnum(rc)))[0..new_size];
}

pub const PID = enum(i32) {
    current = 0,
    _,

    pub fn wait(self: PID, options: i32) error{ NoChildProcesses, Interrupted, InvalidArgument }!Status {
        var status: i32 = undefined;
        const rc = internal.waitpid(self, &status, options);
        switch (errno(rc)) {
            ErrnoCodes.OK => {},
            ErrnoCodes.ECHILD => return error.NoChildProcesses,
            ErrnoCodes.EINTR => return error.Interrupted,
            ErrnoCodes.EINVAL => return error.InvalidArgument,
            else => unreachable,
        }
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

pub const SigSet = [1024 / 32]u32;
const sigset_len = @typeInfo(SigSet).array.len;
pub const empty_sigset = [_]u32{0} ** sigset_len;
pub const filled_sigset = [_]u32{(1 << (31 & (@bitSizeOf(usize) - 1))) - 1} ++ [_]u32{0} ** (sigset_len - 1);
pub const SpawnFileActions = struct {
    pub const Ref = *opaque {};
    ref: Ref,
    pub fn init() error{OutOfMemory}!SpawnFileActions {
        var actions: SpawnFileActions = undefined;
        const rc = internal.posix_spawn_file_actions_init(&actions.ref);
        switch (errno(rc)) {
            ErrnoCodes.OK => {},
            ErrnoCodes.ENOMEM => return error.OutOfMemory,
            else => unreachable,
        }
        return actions;
    }

    pub fn destroy(self: *SpawnFileActions) error{InvalidArgument}!void {
        const rc = internal.posix_spawn_file_actions_destroy(self);
        switch (errno(rc)) {
            ErrnoCodes.OK => {},
            ErrnoCodes.EINVAL => return error.InvalidArgument,
            else => unreachable,
        }
    }

    pub fn addOpen(self: *SpawnFileActions, fd: FD, path: [*:0]const u8, oflag: i32, mode: Mode) error{ InvalidArgument, OutOfMemory, InvalidDescriptor }!void {
        const rc = internal.posix_spawn_file_actions_addopen(&self.ref, fd, path, oflag, mode);
        switch (errno(rc)) {
            ErrnoCodes.OK => {},
            ErrnoCodes.EINVAL => return error.InvalidArgument,
            ErrnoCodes.ENOMEM => return error.OutOfMemory,
            ErrnoCodes.EBADF => return error.InvalidDescriptor,
            else => unreachable,
        }
    }

    pub fn addClose(self: *SpawnFileActions, fd: FD) error{ InvalidArgument, OutOfMemory, InvalidDescriptor }!void {
        const rc = internal.posix_spawn_file_actions_addclose(&self.ref, fd);
        switch (errno(rc)) {
            ErrnoCodes.OK => {},
            ErrnoCodes.EINVAL => return error.InvalidArgument,
            ErrnoCodes.ENOMEM => return error.OutOfMemory,
            ErrnoCodes.EBADF => return error.InvalidDescriptor,
            else => unreachable,
        }
    }

    pub fn addDup2(self: *SpawnFileActions, fd: FD, new_fd: FD) error{ InvalidArgument, OutOfMemory, InvalidDescriptor }!void {
        const rc = internal.posix_spawn_file_actions_adddup2(&self.ref, fd, new_fd);
        switch (errno(rc)) {
            ErrnoCodes.OK => {},
            ErrnoCodes.EINVAL => return error.InvalidArgument,
            ErrnoCodes.ENOMEM => return error.OutOfMemory,
            ErrnoCodes.EBADF => return error.InvalidDescriptor,
            else => unreachable,
        }
    }

    pub fn addInherit(self: *SpawnFileActions, fd: FD) error{ InvalidArgument, OutOfMemory, InvalidDescriptor }!void {
        const rc = internal.posix_spawn_file_actions_addinherit_np(&self.ref, fd);
        switch (errno(rc)) {
            ErrnoCodes.OK => {},
            ErrnoCodes.EINVAL => return error.InvalidArgument,
            ErrnoCodes.ENOMEM => return error.OutOfMemory,
            ErrnoCodes.EBADF => return error.InvalidDescriptor,
            else => unreachable,
        }
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
    pub fn init() error{ OutOfMemory, InvalidArgument }!SpawnAttr {
        var attr: SpawnAttr = undefined;
        const rc = internal.posix_spawnattr_init(&attr.ref);
        switch (errno(rc)) {
            ErrnoCodes.OK => {},
            ErrnoCodes.ENOMEM => return error.OutOfMemory,
            ErrnoCodes.EINVAL => return error.InvalidArgument,
            else => unreachable,
        }
        return attr;
    }

    pub fn destroy(self: *SpawnAttr) error{InvalidArgument}!void {
        const rc = internal.posix_spawnattr_destroy(&self.ref);
        switch (errno(rc)) {
            ErrnoCodes.OK => {},
            ErrnoCodes.EINVAL => return error.InvalidArgument,
            else => unreachable,
        }
    }

    pub fn getFlags(self: *const SpawnAttr) error{InvalidArgument}!i16 {
        var flags: i16 = undefined;
        const rc = internal.posix_spawnattr_getflags(&self.ref, &flags);
        switch (errno(rc)) {
            ErrnoCodes.OK => {},
            ErrnoCodes.EINVAL => return error.InvalidArgument,
            else => unreachable,
        }
        return flags;
    }

    pub fn setFlags(self: *SpawnAttr, flags: i16) error{InvalidArgument}!void {
        const rc = internal.posix_spawnattr_setflags(&self.ref, flags);
        switch (errno(rc)) {
            ErrnoCodes.OK => {},
            ErrnoCodes.EINVAL => return error.InvalidArgument,
            else => unreachable,
        }
    }

    pub fn getSigDefault(self: *const SpawnAttr) error{InvalidArgument}!SigSet {
        var sigdef: u32 = undefined;
        const rc = internal.posix_spawnattr_getsigdefault(&self.ref, &sigdef);
        switch (errno(rc)) {
            ErrnoCodes.OK => {},
            ErrnoCodes.EINVAL => return error.InvalidArgument,
            else => unreachable,
        }
        return sigdef;
    }

    pub fn setSigDefault(self: *SpawnAttr, sigdef: SigSet) error{InvalidArgument}!void {
        const rc = internal.posix_spawnattr_setsigdefault(&self.ref, &sigdef);
        switch (errno(rc)) {
            ErrnoCodes.OK => {},
            ErrnoCodes.EINVAL => return error.InvalidArgument,
            else => unreachable,
        }
    }

    pub fn getSigMask(self: *const SpawnAttr) error{InvalidArgument}!SigSet {
        var sigmask: u32 = undefined;
        const rc = internal.posix_spawnattr_getsigmask(&self.ref, &sigmask);
        switch (errno(rc)) {
            ErrnoCodes.OK => {},
            ErrnoCodes.EINVAL => return error.InvalidArgument,
            else => unreachable,
        }
        return sigmask;
    }

    pub fn setSigMask(self: *SpawnAttr, sigmask: SigSet) error{InvalidArgument}!void {
        const rc = internal.posix_spawnattr_setsigmask(&self.ref, &sigmask);
        switch (errno(rc)) {
            ErrnoCodes.OK => {},
            ErrnoCodes.EINVAL => return error.InvalidArgument,
            else => unreachable,
        }
    }

    pub fn getProcessGroup(self: *const SpawnAttr) error{InvalidArgument}!PID {
        var pid: PID = undefined;
        const rc = internal.posix_spawnattr_getpgroup(&self.ref, &pid);
        switch (errno(rc)) {
            ErrnoCodes.OK => {},
            ErrnoCodes.EINVAL => return error.InvalidArgument,
            else => unreachable,
        }
        return pid;
    }

    pub fn setProcessGroup(self: *SpawnAttr, pid: *const PID) error{InvalidArgument}!void {
        const rc = internal.posix_spawnattr_setpgroup(&self.ref, pid);
        switch (errno(rc)) {
            ErrnoCodes.OK => {},
            ErrnoCodes.EINVAL => return error.InvalidArgument,
            else => unreachable,
        }
    }
};

pub const SpawnError = error{
    ArgvNotProvided,
    ProcessLimitReached,
    OutOfMemory,
    Unsupported,
    PidExists,
    InvalidArgument,
    PidNestingLimitReached,
    PermissionDenied,
};

pub fn spawn(argv: [*:null]const ?[*:0]const u8, file_actions: ?SpawnFileActions, attrp: ?SpawnAttr, envp: [*:null]const ?[*:0]const u8) SpawnError!PID {
    var pid: PID = undefined;
    const file_actions_ref = if (file_actions) |fa| &fa.ref else null;
    const attrp_ref = if (attrp) |a| &a.ref else null;
    const exec = argv[0] orelse return error.ArgvNotProvided;
    const rc = internal.posix_spawn(&pid, exec, file_actions_ref, attrp_ref, argv[1..], envp);
    switch (errno(rc)) {
        ErrnoCodes.OK => {},
        ErrnoCodes.EAGAIN => return error.ProcessLimitReached,
        ErrnoCodes.ENOMEM => return error.OutOfMemory,
        ErrnoCodes.ENOSYS => return error.Unsupported,
        ErrnoCodes.EEXIST => return error.PidExists,
        ErrnoCodes.EINVAL => return error.InvalidArgument,
        ErrnoCodes.ENOSPC => return error.PidNestingLimitReached,
        ErrnoCodes.EPERM => return error.PermissionDenied,
        else => unreachable,
    }
    return pid;
}

const internal = struct {
    pub extern "c" fn getcwd(buf: [*]u8, size: usize) ?[*:0]u8;
    pub extern "c" fn mmap(addr: ?[*]u8, len: usize, prot: i32, flags: i32, fd: i32, offset: usize) ReturnCode;
    pub extern "c" fn munmap(addr: ?[*]u8, len: usize) ReturnCode;
    pub extern "c" fn mremap(old_addr: ?[*]u8, old_size: usize, new_size: usize, flags: i32, new_addr: ?[*]u8) ReturnCode;
    pub extern "c" fn waitpid(pid: PID, status: *i32, options: i32) ReturnCode;
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

    // Linux
    pub extern "c" fn __errno_location() *c_int;
    // Macos
    pub extern "c" fn __error() *c_int;
};

pub fn errno(rc: ReturnCode) ErrnoCodes {
    if (rc == ReturnCode.fail) {
        return @enumFromInt(switch (builtin.os.tag) {
            .linux => internal.__errno_location().*,
            .macos => internal.__error().*,
            else => @compileError("Unsupported OS"),
        });
    }

    return ErrnoCodes.OK;
}

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
