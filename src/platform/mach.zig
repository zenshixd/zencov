const std = @import("std");
const core = @import("../core.zig");
const assert = std.debug.assert;
const builtin = @import("builtin");
const posix = @import("posix.zig");
const native_arch = builtin.target.cpu.arch;

pub const MachMsgOption = struct {
    pub const NONE = 0x00000000;
    pub const SEND = 0x00000001;
    pub const RCV = 0x00000002;
    pub const SEND_TIMEOUT = 0x00000010;
    pub const RCV_TIMEOUT = 0x00000100;
};
pub const MachPortRight = enum(u32) {
    SEND = 0,
    RECEIVE = 1,
    SEND_ONCE = 2,
    PORT_SET = 3,
    DEAD_NAME = 4,
    /// Obsolete right
    LABELH = 5,
    /// Right not implemented
    NUMBER = 6,
};
pub const MachMsgType = enum(u32) {
    /// Must hold receive right
    MOVE_RECEIVE = 16,
    /// Must hold send right(s)
    MOVE_SEND = 17,
    /// Must hold sendonce right
    MOVE_SEND_ONCE = 18,
    /// Must hold send right(s)
    COPY_SEND = 19,
    /// Must hold receive right
    MAKE_SEND = 20,
    /// Must hold receive right
    MAKE_SEND_ONCE = 21,
    /// NOT VALID
    COPY_RECEIVE = 22,
    /// Must hold receive right
    DISPOSE_RECEIVE = 24,
    /// Must hold send right(s)
    DISPOSE_SEND = 25,
    /// Must hold sendonce right
    DISPOSE_SEND_ONCE = 26,
};
pub const EXC = enum(i32) {
    NULL = 0,
    /// Could not access memory
    BAD_ACCESS = 1,
    /// Instruction failed
    BAD_INSTRUCTION = 2,
    /// Arithmetic exception
    ARITHMETIC = 3,
    /// Emulation instruction
    EMULATION = 4,
    /// Software generated exception
    SOFTWARE = 5,
    /// Trace, breakpoint, etc.
    BREAKPOINT = 6,
    /// System calls.
    SYSCALL = 7,
    /// Mach system calls.
    MACH_SYSCALL = 8,
    /// RPC alert
    RPC_ALERT = 9,
    /// Abnormal process exit
    CRASH = 10,
    /// Hit resource consumption limit
    RESOURCE = 11,
    /// Violated guarded resource protections
    GUARD = 12,
    /// Abnormal process exited to corpse state
    CORPSE_NOTIFY = 13,

    pub const TYPES_COUNT = @typeInfo(EXC).@"enum".fields.len;
    pub const SOFT_SIGNAL = 0x10003;

    pub const MASK = packed struct(u32) {
        _0: u1 = 0,
        BAD_ACCESS: bool = false,
        BAD_INSTRUCTION: bool = false,
        ARITHMETIC: bool = false,
        EMULATION: bool = false,
        SOFTWARE: bool = false,
        BREAKPOINT: bool = false,
        SYSCALL: bool = false,
        MACH_SYSCALL: bool = false,
        RPC_ALERT: bool = false,
        CRASH: bool = false,
        RESOURCE: bool = false,
        GUARD: bool = false,
        CORPSE_NOTIFY: bool = false,
        _14: u18 = 0,

        pub const MACHINE: MASK = @bitCast(@as(u32, 0));

        pub const ALL: MASK = .{
            .BAD_ACCESS = true,
            .BAD_INSTRUCTION = true,
            .ARITHMETIC = true,
            .EMULATION = true,
            .SOFTWARE = true,
            .BREAKPOINT = true,
            .SYSCALL = true,
            .MACH_SYSCALL = true,
            .RPC_ALERT = true,
            .CRASH = true,
            .RESOURCE = true,
            .GUARD = true,
            .CORPSE_NOTIFY = true,
        };
    };
};

pub const ExceptionType = enum(u32) {
    /// Send a catch_exception_raise message including the identity.
    default = 1,
    /// Send a catch_exception_raise_state message including the
    /// thread state.
    state = 2,
    /// Send a catch_exception_raise_state_identity message including
    /// the thread identity and state.
    state_identity = 3,
    /// Send a catch_exception_raise_identity_protected message including protected task
    /// and thread identity.
    identity_protected = 4,

    // Use 64bit exception codes
    exception_codes = 0x80000000,
};

pub const VmProt = enum(u8) {
    READ = 0x01,
    WRITE = 0x02,
    EXEC = 0x04,
    COPY = 0x10,

    pub const NONE = 0x00;
};

pub const MachKernelReturn = enum(i32) {
    Success = 0,

    /// Specified address is not currently valid.
    InvalidAddress = 1,

    /// Specified memory is valid, but does not permit the required forms of access.
    ProtectionFailure = 2,

    /// The address range specified is already in use, or no address range of the size specified could be found.
    NoSpace = 3,

    /// The function requested was not applicable to this type of argument, or an argument is invalid.
    InvalidArgument = 4,

    /// The function could not be performed. A catch-all.
    Failure = 5,

    /// A system resource could not be allocated to fulfill this request.
    ResourceShortage = 6,

    /// The task in question does not hold receive rights for the port argument.
    NotReceiver = 7,

    /// Bogus access restriction.
    NoAccess = 8,

    /// During a page fault, the target address refers to destroyed memory.
    MemoryFailure = 9,

    /// During a page fault, the memory object indicated that the data could not be returned.
    MemoryError = 10,

    /// The receive right is already a member of the portset.
    AlreadyInSet = 11,

    /// The receive right is not a member of a port set.
    NotInSet = 12,

    /// The name already denotes a right in the task.
    NameExists = 13,

    /// The operation was aborted.
    Aborted = 14,

    /// The name doesn't denote a right in the task.
    InvalidName = 15,

    /// Target task isn't an active task.
    InvalidTask = 16,

    /// The name denotes a right, but not an appropriate right.
    InvalidRight = 17,

    InvalidValue = 18,
    /// A blatant range error.
    UrefsOverflow = 19,
    /// Operation would overflow limit on user-references.
    /// The supplied (port) capability is improper.
    InvalidCapability = 20,

    /// The task already has send or receive rights for the port under another name.
    RightExists = 21,

    /// Target host isn't actually a host.
    InvalidHost = 22,

    /// Attempt to supply "precious" data for memory already present.
    MemoryPresent = 23,

    /// Page was requested but moved during copy (kernel internal).
    MemoryDataMoved = 24,

    /// Strategic copy attempted where quicker copy is now possible.
    MemoryRestartCopy = 25,

    /// Argument was not a processor set control port.
    InvalidProcessorSet = 26,

    /// Scheduling attributes exceed the thread's limits.
    PolicyLimit = 27,

    /// Specified scheduling policy is not currently enabled.
    InvalidPolicy = 28,

    /// External memory manager failed to initialize the memory object.
    InvalidObject = 29,

    /// Thread is attempting to wait for an event with existing waiter.
    AlreadyWaiting = 30,

    /// Attempt to destroy the default processor set.
    DefaultSet = 31,

    /// Attempt to fetch protected exception port or abort during protected exception.
    ExceptionProtected = 32,

    /// Ledger was required but not supplied.
    InvalidLedger = 33,

    /// Port was not a memory cache control port.
    InvalidMemoryControl = 34,

    /// Argument was not a host security port.
    InvalidSecurity = 35,

    /// thread_depress_abort called on non-depressed thread.
    NotDepressed = 36,

    /// Object has been terminated.
    Terminated = 37,

    /// Lock set has been destroyed.
    LockSetDestroyed = 38,

    /// Thread holding lock terminated before release.
    LockUnstable = 39,

    /// Lock is already owned by another thread.
    LockOwned = 40,

    /// Lock is already owned by the calling thread.
    LockOwnedSelf = 41,

    /// Semaphore has been destroyed.
    SemaphoreDestroyed = 42,

    /// RPC target server was terminated before reply.
    RpcServerTerminated = 43,

    /// Terminate an orphaned activation.
    RpcTerminateOrphan = 44,

    /// Allow an orphaned activation to continue executing.
    RpcContinueOrphan = 45,

    /// Empty thread activation (No thread linked to it).
    NotSupported = 46,

    /// Remote node down or inaccessible.
    NodeDown = 47,

    /// Signalled thread was not actually waiting.
    NotWaiting = 48,

    /// Thread-oriented operation (semaphore_wait) timed out.
    OperationTimedOut = 49,

    /// Page was rejected due to signature check.
    CodesignError = 50,

    /// Requested property cannot be changed at this time.
    PolicyStatic = 51,

    /// Provided buffer is too small for requested data.
    InsufficientBufferSize = 52,

    /// Denied by security policy.
    Denied = 53,

    /// The KC on which the function is operating is missing.
    MissingKc = 54,

    /// The KC on which the function is operating is invalid.
    InvalidKc = 55,

    /// Maximum return value allowable.
    ReturnMax = 0x100,

    // ===== General IPC/VM Space Errors =====
    /// No room in IPC name space for another capability name.
    MsgIpcSpace = 0x00002000,
    /// No room in VM address space for out-of-line memory.
    MsgVmSpace = 0x00001000,
    /// Kernel resource shortage handling an IPC capability.
    MsgIpcKernel = 0x00000800,
    /// Kernel resource shortage handling out-of-line memory.
    MsgVmKernel = 0x00000400,

    // ===== Send Errors =====
    /// Thread is waiting to send. (Internal use only.)
    SendInProgress = 0x10000001,
    /// Bogus in-line data.
    SendInvalidData = 0x10000002,
    /// Bogus destination port.
    SendInvalidDest = 0x10000003,
    /// Message not sent before timeout expired.
    SendTimedOut = 0x10000004,
    /// Bogus voucher port.
    SendInvalidVoucher = 0x10000005,
    /// Software interrupt.
    SendInterrupted = 0x10000007,
    /// Data doesn't contain a complete message.
    SendMsgTooSmall = 0x10000008,
    /// Bogus reply port.
    SendInvalidReply = 0x10000009,
    /// Bogus port rights in the message body.
    SendInvalidRight = 0x1000000a,
    /// Bogus notify port argument.
    SendInvalidNotify = 0x1000000b,
    /// Invalid out-of-line memory pointer.
    SendInvalidMemory = 0x1000000c,
    /// No message buffer is available.
    SendNoBuffer = 0x1000000d,
    /// Send is too large for port
    SendTooLarge = 0x1000000e,
    /// Invalid msg-type specification.
    SendInvalidType = 0x1000000f,
    /// A field in the header had a bad value.
    SendInvalidHeader = 0x10000010,
    /// The trailer to be sent does not match kernel format.
    SendInvalidTrailer = 0x10000011,
    /// The sending thread context did not match the context on the dest port
    SendInvalidContext = 0x10000012,
    /// compatibility: no longer a returned error
    SendInvalidRtOolSize = 0x10000015,
    /// The destination port doesn't accept ports in body
    SendNoGrantDest = 0x10000016,
    /// Message send was rejected by message filter
    SendMsgFiltered = 0x10000017,

    // ===== Receive Errors =====
    /// Thread is waiting for receive. (Internal use only.)
    RcvInProgress = 0x10004001,
    /// Bogus name for receive port/port-set.
    RcvInvalidName = 0x10004002,
    /// Didn't get a message within the timeout value.
    RcvTimedOut = 0x10004003,
    /// Message buffer is not large enough for inline data.
    RcvTooLarge = 0x10004004,
    /// Software interrupt.
    RcvInterrupted = 0x10004005,
    /// compatibility: no longer a returned error
    RcvPortChanged = 0x10004006,
    /// Bogus notify port argument.
    RcvInvalidNotify = 0x10004007,
    /// Bogus message buffer for inline data.
    RcvInvalidData = 0x10004008,
    /// Port/set was sent away/died during receive.
    RcvPortDied = 0x10004009,
    /// compatibility: no longer a returned error
    RcvInSet = 0x1000400a,
    /// Error receiving message header. See special bits.
    RcvHeaderError = 0x1000400b,
    /// Error receiving message body. See special bits.
    RcvBodyError = 0x1000400c,
    /// Invalid msg-type specification in scatter list.
    RcvInvalidType = 0x1000400d,
    /// Out-of-line overwrite region is not large enough
    RcvScatterSmall = 0x1000400e,
    /// trailer type or number of trailer elements not supported
    RcvInvalidTrailer = 0x1000400f,
    /// Waiting for receive with timeout. (Internal use only.)
    RcvInProgressTimed = 0x10004011,
    /// invalid reply port used in a STRICT_REPLY message
    RcvInvalidReply = 0x10004012,
    MigTypeError = -300,
    MigReplyMismatch = -301,
    MigRemoteError = -302,
    MigBadId = -303,
    MigBadArguments = -304,
    MigNoReply = -305,
    MigException = -306,
    MigArrayTooLarge = -307,
    MigServerDied = -308,
    MigTrailerError = -309,
};

pub const THREAD_STATE_MAX = 1296;

pub const ThreadStateFlavor = enum(u32) {
    ARM = 1,
    ARM64 = 6,
    ARM32 = 9,
    NONE = switch (native_arch) {
        .aarch64 => 5,
        .x86_64 => 13,
        else => @compileError("unsupported arch"),
    },

    pub fn count(self: ThreadStateFlavor) u32 {
        return switch (self) {
            .ARM => @sizeOf(ThreadStateArm) / @sizeOf(i32),
            .ARM64 => @sizeOf(ThreadStateArm64) / @sizeOf(i32),
            .NONE => 0,
            else => unreachable,
        };
    }
};

pub const ThreadState = extern union {
    arm: ThreadStateArm,
    arm64: ThreadStateArm64,

    __padding: [THREAD_STATE_MAX]u32,
};

pub const ThreadStateArm = extern struct {
    r: [13]u32, // General purpose registers r0-r12
    sp: u32, // Stack pointer r13
    lr: u32, // Link register r14
    pc: u32, // Program counter r15
    cpsr: u32, // Current program status register
};
pub const ThreadStateArm64 = extern struct {
    x: [29]u64, // General purpose registers x0-x28
    fp: u64, // Frame pointer x29
    lr: u64, // Link register x30
    sp: u64, // Stack pointer x31
    pc: u64, // Program counter
    cpsr: u32, // Current program status register
    flags: u32, // Flags

    pub fn format(self: ThreadStateArm64, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print(
            \\ThreadStateArm64{{
            \\    .fp = {x},
            \\    .lr = {x},
            \\    .sp = {x},
            \\    .pc = {x},
            \\    .cpsr = {b},
            \\    .flags = {b},
            \\}}
        , .{
            self.fp,
            self.lr,
            self.sp,
            self.pc,
            self.cpsr,
            self.flags,
        });
    }
};

pub const VMRegionRecurseResult = struct {
    address: usize = 0,
    size: u64 = 0,
    depth: u32 = 0,
    info: VMRegionSubmapInfo64 = undefined,
    cnt: u32 = VM_REGION_SUBMAP_INFO_COUNT_64,

    pub fn format(self: VMRegionRecurseResult, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print(
            \\VMRegionRecurseResult{{
            \\    .address = {x},
            \\    .size = {d},
            \\    .depth = {d},
            \\    .info = {},
            \\    .cnt = {d},
            \\}}
        , .{
            self.address,
            self.size,
            self.depth,
            self.info,
            self.cnt,
        });
    }
};
pub const VMRegionSubmapInfo64 = extern struct {
    // present across protection
    protection: i32,
    // max avail through vm_prot
    max_protection: i32,
    // behavior of map/obj on fork
    inheritance: u32,
    // offset into object/map
    offset: u64 align(4),
    // user tag on map entry
    user_tag: u32,
    // only valid for objects
    pages_resident: u32,
    // only for objects
    pages_shared_now_private: u32,
    // only for objects
    pages_swapped_out: u32,
    // only for objects
    pages_dirtied: u32,
    // obj/map mappers, etc.
    ref_count: u32,
    // only for obj
    shadow_depth: u16,
    // only for obj
    external_pager: u8,
    // see enumeration
    share_mode: u8,
    // submap vs obj
    is_submap: i32,
    // access behavior hint
    behavior: i32,
    // obj/map name, not a handle
    object_id: u32,
    user_wired_count: u16,
    pages_reusable: u32,
    object_id_full: u64 align(4),

    pub fn format(self: VMRegionSubmapInfo64, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print(
            \\VMRegionSubmapInfo64{{
            \\    .protection = {b},
            \\    .max_protection = {b},
            \\    .inheritance = {d},
            \\    .offset = {d},
            \\    .user_tag = {d},
            \\    .pages_resident = {d},
            \\    .pages_shared_now_private = {d},
            \\    .pages_swapped_out = {d},
            \\    .pages_dirtied = {d},
            \\    .ref_count = {d},
            \\    .shadow_depth = {d},
            \\    .external_pager = {d},
            \\    .share_mode = {d},
            \\    .is_submap = {d},
            \\    .behavior = {d},
            \\    .object_id = {d},
            \\    .user_wired_count = {d},
            \\    .pages_reusable = {d},
            \\    .object_id_full = {d},
            \\}}
        , .{
            self.protection,
            self.max_protection,
            self.inheritance,
            self.offset,
            self.user_tag,
            self.pages_resident,
            self.pages_shared_now_private,
            self.pages_swapped_out,
            self.pages_dirtied,
            self.ref_count,
            self.shadow_depth,
            self.external_pager,
            self.share_mode,
            self.is_submap,
            self.behavior,
            self.object_id,
            self.user_wired_count,
            self.pages_reusable,
            self.object_id_full,
        });
    }
};
pub const VM_REGION_SUBMAP_INFO_COUNT_64 = 16;

pub extern "c" var mach_task_self_: MachPort;
pub fn taskSelf() MachPort {
    return mach_task_self_;
}

pub extern "c" fn task_for_pid(port: MachPort, pid: i32, output: *MachPort) MachKernelReturn;
pub extern "c" fn mach_vm_region_recurse(task: MachPort, address: *u64, size: *u64, nesting_depth: *u32, info: *VMRegionSubmapInfo64, cnt: *u32) MachKernelReturn;
pub extern "c" fn mach_vm_read(task: MachPort, address: [*]const u8, size: u64, data: *[*]u8, cnt: *u32) MachKernelReturn;
pub extern "c" fn mach_vm_read_overwrite(task: MachPort, address: [*]const u8, size: u64, buf: [*]u8, buf_size: *u32) MachKernelReturn;
pub extern "c" fn mach_vm_write(task: MachPort, address: [*]const u8, data: [*]const u8, cnt: u32) MachKernelReturn;
pub extern "c" fn mach_vm_protect(task: MachPort, address: [*]const u8, size: u64, set_maximum: bool, new_protection: u32) MachKernelReturn;
pub extern "c" fn mach_vm_allocate(task: MachPort, address: *usize, size: u64, flags: u32) MachKernelReturn;
pub extern "c" fn mach_port_allocate(task: MachPort, right: MachPortRight, name: *MachPort) MachKernelReturn;
pub extern "c" fn mach_port_insert_right(task: MachPort, name: MachPort, poly: MachPort, poly_poly: MachMsgType) MachKernelReturn;
pub extern "c" fn task_set_exception_ports(task: MachPort, exception_mask: u32, new_port: MachPort, behavior: u32, thread_state_flavor: ThreadStateFlavor) MachKernelReturn;
pub extern "c" fn task_suspend(target_task: MachPort) MachKernelReturn;
pub extern "c" fn task_resume(target_task: MachPort) MachKernelReturn;
pub extern "c" fn thread_get_state(
    thread: MachPort,
    flavor: ThreadStateFlavor,
    state: *ThreadState,
    count: *u32,
) MachKernelReturn;
pub extern "c" fn thread_set_state(
    thread: MachPort,
    flavor: ThreadStateFlavor,
    new_state: *ThreadState,
    count: u32,
) MachKernelReturn;
pub extern "c" fn thread_resume(thread: MachPort) MachKernelReturn;
pub extern "c" fn mach_msg(
    msg: ?*anyopaque,
    option: u32,
    send_size: u32,
    rcv_size: u32,
    rcv_name: MachPort,
    timeout: u32,
    notify: MachPort,
) MachKernelReturn;

pub const MachPort = enum(u32) {
    none = 0,
    _,

    pub fn taskForPid(self: MachPort, pid: posix.PosixPID) !MachPort {
        var port: MachPort = undefined;
        try checkKern(task_for_pid(self, @intFromEnum(pid), &port));
        return port;
    }

    pub fn vmRegionRecurse(self: MachPort, address: usize, depth: u32) !VMRegionRecurseResult {
        var result: VMRegionRecurseResult = .{
            .address = address,
            .size = 0,
            .depth = depth,
            .info = undefined,
            .cnt = VM_REGION_SUBMAP_INFO_COUNT_64,
        };
        try checkKern(mach_vm_region_recurse(self, &result.address, &result.size, &result.depth, &result.info, &result.cnt));
        return result;
    }

    pub fn readMem(self: MachPort, address: [*]const u8, size: usize) ![]const u8 {
        var out: [*]u8 = undefined;
        var bytes_read: u32 = 0;
        try checkKern(mach_vm_read(self, address, size, &out, &bytes_read));
        return out[0..bytes_read];
    }

    pub fn readMemOverwrite(self: MachPort, address: [*]const u8, size: usize, out: []u8) ![]const u8 {
        var bytes_read: u32 = 0;
        try checkKern(mach_vm_read_overwrite(self, address, size, out.ptr, &bytes_read));
        assert(bytes_read == size);
        return out;
    }

    pub fn writeMem(self: MachPort, address: [*]const u8, data: []const u8) !void {
        try checkKern(mach_vm_write(self, address, data.ptr, @intCast(data.len)));
    }

    pub fn protect(self: MachPort, buf: []const u8, set_maximum: bool, new_protection: u8) !void {
        try checkKern(mach_vm_protect(self, buf.ptr, buf.len, set_maximum, new_protection));
    }

    pub fn portAllocate(self: MachPort, right: MachPortRight) !MachPort {
        var port: MachPort = undefined;
        try checkKern(mach_port_allocate(self, right, &port));
        return port;
    }

    pub fn portInsertRight(self: MachPort, port_name: MachPort, port: MachPort, right: MachMsgType) !void {
        try checkKern(mach_port_insert_right(self, port_name, port, right));
    }

    pub fn setExceptionPorts(self: MachPort, exception_mask: EXC.MASK, new_port: MachPort, behavior: u32, thread_state_flavor: ThreadStateFlavor) !void {
        try checkKern(task_set_exception_ports(self, @bitCast(exception_mask), new_port, behavior, thread_state_flavor));
    }

    pub fn @"suspend"(self: MachPort) !void {
        try checkKern(task_suspend(self));
    }

    pub fn @"resume"(self: MachPort) !void {
        try checkKern(task_resume(self));
    }

    pub fn threadGetState(self: MachPort, flavor: ThreadStateFlavor) !ThreadState {
        var state: ThreadState = undefined;
        var count: u32 = flavor.count();
        try checkKern(thread_get_state(self, flavor, &state, &count));
        if (count != flavor.count()) {
            std.log.debug("threadGetState: count: {} != flavor.count(): {}", .{ count, flavor.count() });
        }
        return state;
    }

    pub fn threadSetState(self: MachPort, flavor: ThreadStateFlavor, new_state: *ThreadState) !void {
        try checkKern(thread_set_state(self, flavor, new_state, flavor.count()));
    }

    pub fn receiveMessage(dest: MachPort, timeout: u32, notify: MachPort) !MachMsgRequest {
        var options: u32 = MachMsgOption.RCV;
        if (timeout != 0) {
            options |= MachMsgOption.RCV_TIMEOUT;
        }
        var msg: MachMsgRequest = undefined;
        try checkKern(mach_msg(&msg, options, 0, @sizeOf(MachMsgRequest), dest, timeout, notify));
        return msg;
    }

    pub fn sendMessage(dest: MachPort, msg: *MachMsgReply, timeout: u32, notify: MachPort) !void {
        var options: u32 = MachMsgOption.SEND;
        if (timeout != 0) {
            options |= MachMsgOption.SEND_TIMEOUT;
        }
        try checkKern(mach_msg(@ptrCast(msg), options, msg.header.size, 0, dest, timeout, notify));
    }
};

pub const MachKernelError = core.ErrorSetFromEnum(MachKernelReturn);
const kernReturnToErrorMap = core.createEnumToErrorSetTable(MachKernelReturn, MachKernelError);

pub fn checkKern(ret: MachKernelReturn) !void {
    switch (ret) {
        .Success => {},
        inline else => |tag| {
            // HUH ? why do i need to change quota here ????
            @setEvalBranchQuota(6000);
            inline for (kernReturnToErrorMap) |entry| {
                if (entry.value == tag) {
                    return entry.error_set;
                }
            }
            unreachable;
        },
    }
}

// MIG supported protocols for Network Data Representation
pub const NDR_PROTOCOL_2_0: u8 = 0;

// NDR 2.0 format flag type definition and values
pub const NDR_INT_BIG_ENDIAN: u8 = 0;
pub const NDR_INT_LITTLE_ENDIAN: u8 = 1;
pub const NDR_FLOAT_IEEE: u8 = 0;
pub const NDR_FLOAT_VAX: u8 = 1;
pub const NDR_FLOAT_CRAY: u8 = 2;
pub const NDR_FLOAT_IBM: u8 = 3;
pub const NDR_CHAR_ASCII: u8 = 0;
pub const NDR_CHAR_EBCDIC: u8 = 1;

pub const NDR_record = extern struct {
    pub const default = NDR_record{
        .mig_vers = 0,
        .if_vers = 0,
        .reserved1 = 0,
        .mig_encoding = NDR_PROTOCOL_2_0,
        .int_rep = NDR_INT_LITTLE_ENDIAN,
        .char_rep = NDR_CHAR_ASCII,
        .float_rep = NDR_FLOAT_IEEE,
        .reserved2 = 0,
    };
    mig_vers: u8,
    if_vers: u8,
    reserved1: u8,
    mig_encoding: u8,
    int_rep: u8,
    char_rep: u8,
    float_rep: u8,
    reserved2: u8,
};

pub const MACH_MSGH_BITS_REMOTE_MASK = 0x0000001f;
pub fn machMsgRemoteBits(bits: u32) u32 {
    return bits & MACH_MSGH_BITS_REMOTE_MASK;
}

pub fn machMsgReplyBits(bits: u32) u32 {
    return machMsgRemoteBits(bits);
}

// Only one for now, not sure if we will need more
pub const MachMsgId = enum(u32) {
    exception_raise = 2405,
    _,
};

pub const MachMsgRequest = extern union {
    header: MachMsgHeader,
    exception_raise: MachMsgRequestExceptionRaise,
    __padding: [128]u8,
};

pub const MachMsgReply = extern union {
    header: MachMsgHeader,
    @"error": MachMsgReplyError,
    exception_raise: MachMsgReplyExceptionRaise,
};

pub const MachMsgHeader = extern struct {
    bits: u32,
    size: u32,
    remote_port: MachPort,
    local_port: MachPort,
    voucher_port: MachPort,
    id: MachMsgId,

    pub fn format(self: MachMsgHeader, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print(
            \\MachMsgHeader{{
            \\    .bits = {b},
            \\    .size = {},
            \\    .remote_port = {},
            \\    .local_port = {},
            \\    .voucher_port = {},
            \\    .id = {},
            \\}}
        , .{
            self.bits,
            self.size,
            self.remote_port,
            self.local_port,
            self.voucher_port,
            self.id,
        });
    }
};

pub const MachMsgBody = extern struct {
    descriptor_count: u32,
};

pub const MachMsgPortDescriptor = extern struct {
    name: MachPort,
    __pad1: u8,
    __pad2: u16,
    disposition: u8,
    type: u8,
};

pub const MachMsgRequestExceptionRaise = extern struct {
    hdr: MachMsgHeader,
    body: MachMsgBody,
    thread: MachMsgPortDescriptor,
    task: MachMsgPortDescriptor,
    ndr: NDR_record,
    exception: EXC,
    codeCount: u32,
    code: [2]i64 align(4),

    pub fn format(self: MachMsgRequestExceptionRaise, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print(
            \\MachMsgRequestExceptionRaise{{
            \\    .thread = {},
            \\    .task = {},
            \\    .exception = {},
            \\    .codeCount = {},
            \\    .code = {{
            \\        {d},
            \\        {d},
            \\    }},
            \\}}
        , .{
            self.thread.name,
            self.task.name,
            self.exception,
            self.codeCount,
            self.code[0],
            self.code[1],
        });
    }
};

pub const MachMsgReplyExceptionRaise = extern struct {
    hdr: MachMsgHeader,
    NDR: NDR_record,
    RetCode: MachKernelReturn,

    pub fn format(self: MachMsgReplyExceptionRaise, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print(
            \\MachMsgReplyExceptionRaise{{
            \\    .RetCode = {},
            \\}}
        , .{
            self.RetCode,
        });
    }
};

pub const MachMsgReplyError = extern struct {
    hdr: MachMsgHeader,
    NDR: NDR_record,
    RetCode: MachKernelReturn,
};
