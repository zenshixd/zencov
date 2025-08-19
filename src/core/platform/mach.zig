const core = @import("../../core.zig");
const meta = @import("../../core/meta.zig");
const debug = @import("../../core/debug.zig");
const builtin = @import("builtin");
const posix = @import("posix.zig");
const native_arch = builtin.target.cpu.arch;

pub const MsgOption = struct {
    pub const NONE = 0x00000000;
    pub const SEND = 0x00000001;
    pub const RCV = 0x00000002;
    pub const SEND_TIMEOUT = 0x00000010;
    pub const RCV_TIMEOUT = 0x00000100;
};
pub const PortRight = enum(u32) {
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
pub const MsgType = enum(u32) {
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

pub const KernelReturn = enum(i32) {
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
};

pub const VMRegionRecurseResult = struct {
    address: usize = 0,
    size: u64 = 0,
    depth: u32 = 0,
    info: VMRegionSubmapInfo64 = undefined,
    cnt: u32 = VM_REGION_SUBMAP_INFO_COUNT_64,
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
};
pub const VM_REGION_SUBMAP_INFO_COUNT_64 = 16;

pub fn taskSelf() Port {
    return internal.mach_task_self_;
}

pub const AllocateFlags = core.EnumMask(enum(i32) {
    anywhere = 1,
    purgable = 2,
    chunk_4gb = 4,
    random_addr = 8,
    no_cache = 16,
    resilient_codesign = 32,
    resilient_media = 64,
    permanent = 128,
    overwrite = 0x4000,
});

pub const Port = enum(u32) {
    none = 0,
    _,

    pub fn taskForPid(self: Port, pid: posix.PID) !Port {
        var port: Port = undefined;
        try checkKern(internal.task_for_pid(self, @intFromEnum(pid), &port));
        return port;
    }

    pub fn vmAllocate(self: Port, size: usize, flags: AllocateFlags) ![]u8 {
        var address: usize = undefined;
        try checkKern(internal.mach_vm_allocate(self, &address, size, @bitCast(flags)));
        return @as([*]u8, @ptrFromInt(address))[0..size];
    }

    pub fn vmDeallocate(self: Port, address: []const u8) KernelError!void {
        try checkKern(internal.mach_vm_deallocate(self, @intFromPtr(address.ptr), address.len));
    }

    pub fn vmRegionRecurse(self: Port, address: usize, depth: u32) !VMRegionRecurseResult {
        var result: VMRegionRecurseResult = .{
            .address = address,
            .size = 0,
            .depth = depth,
            .info = undefined,
            .cnt = VM_REGION_SUBMAP_INFO_COUNT_64,
        };
        try checkKern(internal.mach_vm_region_recurse(self, &result.address, &result.size, &result.depth, &result.info, &result.cnt));
        return result;
    }

    pub fn readMem(self: Port, address: [*]const u8, size: usize) ![]const u8 {
        var out: [*]u8 = undefined;
        var bytes_read: u32 = 0;
        try checkKern(internal.mach_vm_read(self, address, size, &out, &bytes_read));
        return out[0..bytes_read];
    }

    pub fn readMemOverwrite(self: Port, address: [*]const u8, size: usize, out: []u8) ![]const u8 {
        var bytes_read: u32 = 0;
        try checkKern(internal.mach_vm_read_overwrite(self, address, size, out.ptr, &bytes_read));
        debug.assert(bytes_read == size);
        return out;
    }

    pub fn writeMem(self: Port, address: [*]const u8, data: []const u8) !void {
        try checkKern(internal.mach_vm_write(self, address, data.ptr, @intCast(data.len)));
    }

    pub fn protect(self: Port, buf: []const u8, set_maximum: bool, new_protection: u8) !void {
        try checkKern(internal.mach_vm_protect(self, buf.ptr, buf.len, set_maximum, new_protection));
    }

    pub fn portAllocate(self: Port, right: PortRight) !Port {
        var port: Port = undefined;
        try checkKern(internal.mach_port_allocate(self, right, &port));
        return port;
    }

    pub fn portInsertRight(self: Port, port_name: Port, port: Port, right: MsgType) !void {
        try checkKern(internal.mach_port_insert_right(self, port_name, port, right));
    }

    pub fn setExceptionPorts(self: Port, exception_mask: EXC.MASK, new_port: Port, behavior: u32, thread_state_flavor: ThreadStateFlavor) !void {
        try checkKern(internal.task_set_exception_ports(self, @bitCast(exception_mask), new_port, behavior, thread_state_flavor));
    }

    pub fn @"suspend"(self: Port) !void {
        try checkKern(internal.task_suspend(self));
    }

    pub fn @"resume"(self: Port) !void {
        try checkKern(internal.task_resume(self));
    }

    pub fn threadGetState(self: Port, flavor: ThreadStateFlavor) !ThreadState {
        var state: ThreadState = undefined;
        var count: u32 = flavor.count();
        try checkKern(internal.thread_get_state(self, flavor, &state, &count));
        if (count != flavor.count()) {
            debug.panic("threadGetState: count: {} != flavor.count(): {}", .{ count, flavor.count() });
        }
        return state;
    }

    pub fn threadSetState(self: Port, flavor: ThreadStateFlavor, new_state: *ThreadState) !void {
        try checkKern(internal.thread_set_state(self, flavor, new_state, flavor.count()));
    }

    pub fn receiveMessage(dest: Port, timeout: u32, notify: Port) !MessageRequest {
        var options: u32 = MsgOption.RCV;
        if (timeout != 0) {
            options |= MsgOption.RCV_TIMEOUT;
        }
        var msg: MessageRequest = undefined;
        try checkKern(internal.mach_msg(&msg, options, 0, @sizeOf(MessageRequest), dest, timeout, notify));
        return msg;
    }

    pub fn sendMessage(dest: Port, msg: *MessageReply, timeout: u32, notify: Port) !void {
        var options: u32 = MsgOption.SEND;
        if (timeout != 0) {
            options |= MsgOption.SEND_TIMEOUT;
        }
        try checkKern(internal.mach_msg(@ptrCast(msg), options, msg.header.size, 0, dest, timeout, notify));
    }
};

pub const KernelError = meta.ErrorSetFromEnum(KernelReturn);
const kernReturnToErrorMap = meta.createEnumToErrorSetTable(KernelReturn, KernelError);

pub fn checkKern(ret: KernelReturn) KernelError!void {
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

pub const MSGH_BITS_REMOTE_MASK = 0x0000001f;
pub fn messageRemoteBits(bits: u32) u32 {
    return bits & MSGH_BITS_REMOTE_MASK;
}

pub fn messageReplyBits(bits: u32) u32 {
    return messageRemoteBits(bits);
}

// Only one for now, not sure if we will need more
pub const MessageId = enum(u32) {
    exception_raise = 2405,
    _,
};

pub const MessageRequest = extern union {
    header: MessageHeader,
    exception_raise: MessageRequestExceptionRaise,
    __padding: [128]u8,
};

pub const MessageReply = extern union {
    header: MessageHeader,
    @"error": MessageReplyError,
    exception_raise: MessageReplyExceptionRaise,
};

pub const MessageHeader = extern struct {
    bits: u32,
    size: u32,
    remote_port: Port,
    local_port: Port,
    voucher_port: Port,
    id: MessageId,
};

pub const MessageBody = extern struct {
    descriptor_count: u32,
};

pub const MessagePortDescriptor = extern struct {
    name: Port,
    __pad1: u8,
    __pad2: u16,
    disposition: u8,
    type: u8,
};

pub const MessageRequestExceptionRaise = extern struct {
    hdr: MessageHeader,
    body: MessageBody,
    thread: MessagePortDescriptor,
    task: MessagePortDescriptor,
    ndr: NDR_record,
    exception: EXC,
    codeCount: u32,
    code: [2]i64 align(4),
};

pub const MessageReplyExceptionRaise = extern struct {
    hdr: MessageHeader,
    NDR: NDR_record,
    RetCode: KernelReturn,
};

pub const MessageReplyError = extern struct {
    hdr: MessageHeader,
    NDR: NDR_record,
    RetCode: KernelReturn,
};

const internal = struct {
    pub extern "c" var mach_task_self_: Port;
    pub extern "c" fn task_for_pid(port: Port, pid: i32, output: *Port) KernelReturn;
    pub extern "c" fn mach_vm_allocate(task: Port, address: *usize, size: usize, flags: u32) KernelReturn;
    pub extern "c" fn mach_vm_deallocate(task: Port, address: usize, size: usize) KernelReturn;
    pub extern "c" fn mach_vm_region_recurse(task: Port, address: *u64, size: *u64, nesting_depth: *u32, info: *VMRegionSubmapInfo64, cnt: *u32) KernelReturn;
    pub extern "c" fn mach_vm_read(task: Port, address: [*]const u8, size: u64, data: *[*]u8, cnt: *u32) KernelReturn;
    pub extern "c" fn mach_vm_read_overwrite(task: Port, address: [*]const u8, size: u64, buf: [*]u8, buf_size: *u32) KernelReturn;
    pub extern "c" fn mach_vm_write(task: Port, address: [*]const u8, data: [*]const u8, cnt: u32) KernelReturn;
    pub extern "c" fn mach_vm_protect(task: Port, address: [*]const u8, size: u64, set_maximum: bool, new_protection: u32) KernelReturn;
    pub extern "c" fn mach_port_allocate(task: Port, right: PortRight, name: *Port) KernelReturn;
    pub extern "c" fn mach_port_insert_right(task: Port, name: Port, poly: Port, poly_poly: MsgType) KernelReturn;
    pub extern "c" fn task_set_exception_ports(task: Port, exception_mask: u32, new_port: Port, behavior: u32, thread_state_flavor: ThreadStateFlavor) KernelReturn;
    pub extern "c" fn task_suspend(target_task: Port) KernelReturn;
    pub extern "c" fn task_resume(target_task: Port) KernelReturn;
    pub extern "c" fn thread_get_state(
        thread: Port,
        flavor: ThreadStateFlavor,
        state: *ThreadState,
        count: *u32,
    ) KernelReturn;
    pub extern "c" fn thread_set_state(
        thread: Port,
        flavor: ThreadStateFlavor,
        new_state: *ThreadState,
        count: u32,
    ) KernelReturn;
    pub extern "c" fn thread_resume(thread: Port) KernelReturn;
    pub extern "c" fn mach_msg(
        msg: ?*anyopaque,
        option: u32,
        send_size: u32,
        rcv_size: u32,
        rcv_name: Port,
        timeout: u32,
        notify: Port,
    ) KernelReturn;
};
