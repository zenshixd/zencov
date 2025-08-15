const std = @import("std");
const assert = std.debug.assert;
const panic = std.debug.panic;

const builtin = @import("builtin");
const native_arch = builtin.target.cpu.arch;

const core = @import("../core.zig");
const platform = @import("../core/platform.zig");
const posix = platform.posix;
const mach = platform.mach;

const inst_base = @import("base.zig");

pub fn spawnForTracing(ctx: *core.Context, args: []const []const u8) *PID {
    var scratch_arena = std.heap.ArenaAllocator.init(ctx.gpa);
    defer scratch_arena.deinit();
    const scratch = scratch_arena.allocator();

    var argsZ = std.ArrayList(?[*:0]const u8).initCapacity(scratch, args.len + 1) catch unreachable;
    for (args) |arg| {
        argsZ.append(scratch.dupeZ(u8, arg) catch unreachable) catch unreachable;
    }

    var attrp = posix.SpawnAttr.init() catch |err| panic("posix_spawnattr_init failed: {}", .{err});
    attrp.setSigMask(posix.empty_sigset) catch |err| panic("posix_spawnattr_setsigmask failed: {}", .{err});
    attrp.setSigDefault(posix.filled_sigset) catch |err| panic("posix_spawnattr_setsigdefault failed: {}", .{err});
    attrp.setFlags(posix.SPAWN_SETSIGDEF | posix.SPAWN_SETSIGMASK | posix.SPAWN_SETPGROUP | posix.SPAWN_START_SUSPENDED) catch |err|
        panic("posix_spawnattr_setflags failed: {}", .{err});

    const pid = posix.spawn(argsZ.toOwnedSliceSentinel(null) catch unreachable, null, attrp, &.{null}) catch |err|
        panic("posix_spawn failed: {}", .{err});

    const handle = ctx.arena.create(PID) catch unreachable;
    handle.* = PID{
        .ctx = ctx,
        .pid = pid,
        .process_port = null,
        .exception_port = null,
        .breakpoint_handler = null,
    };
    return @ptrCast(handle);
}

pub const PID = struct {
    ctx: *core.Context,
    pid: posix.PID,
    process_port: ?mach.Port,
    exception_port: ?mach.Port,
    breakpoint_handler: ?*const fn (pid: *anyopaque, pc: usize) bool,

    pub fn getContext(pid: *PID) *core.Context {
        return @ptrCast(pid.ctx);
    }

    fn getPortForPid(pid: *PID) mach.Port {
        if (pid.pid == posix.PID.current) {
            return mach.taskSelf();
        }

        if (pid.process_port) |port| {
            return port;
        }

        const port = mach.taskSelf().taskForPid(pid.pid) catch |err| panic("Cannot get child task for pid {}: {}", .{ pid.pid, err });
        pid.process_port = port;
        return port;
    }

    pub fn processResume(pid: *PID) void {
        const child_task: mach.Port = pid.getPortForPid();
        child_task.@"resume"() catch |err| panic("Cannot resume task: {}", .{err});
    }

    pub fn processSuspend(pid: *PID) void {
        const child_task: mach.Port = pid.getPortForPid();
        child_task.@"suspend"() catch |err| panic("Cannot suspend task: {}", .{err});
    }

    pub fn getMemoryRegion(pid: *PID, address: usize) []const u8 {
        const task = pid.getPortForPid();
        const result = task.vmRegionRecurse(address, 1024) catch |err| panic("Cannot get vm region for pid {}: {}", .{ pid, err });

        return @as([*]const u8, @ptrFromInt(result.address))[0..result.size];
    }

    pub fn setupBreakpointHandler(pid: *PID, handler: *const fn (pid: *anyopaque, pc: usize) bool) void {
        if (pid.exception_port) |_| {
            return;
        }

        const child_task: mach.Port = pid.getPortForPid();
        pid.exception_port = mach.taskSelf().portAllocate(mach.PortRight.RECEIVE) catch |err| panic("Cannot allocate exception port: {}", .{err});
        mach.taskSelf().portInsertRight(pid.exception_port.?, pid.exception_port.?, mach.MsgType.MAKE_SEND) catch |err| panic("Cannot insert exception port: {}", .{err});
        child_task.setExceptionPorts(
            mach.EXC.MASK.ALL,
            pid.exception_port.?,
            @intFromEnum(mach.ExceptionType.default) | @intFromEnum(mach.ExceptionType.exception_codes),
            .NONE,
        ) catch |err|
            panic("Cannot set exception ports: {}", .{err});

        pid.breakpoint_handler = handler;
        std.log.debug("setupBreakpointHandler: pid: {}, child_task: {}, exc_port: {}", .{ pid.pid, child_task, pid.exception_port.? });
    }

    pub fn setMemoryProtection(pid: *PID, addr: []const u8, prot: core.EnumMask(inst_base.MemoryProtection)) void {
        std.log.debug("setMemoryWritable: pid: {}, addr: {*}, size: {}, prot: {b}", .{ pid.pid, addr, addr.len, @as(u8, @bitCast(prot)) });

        var prot_mask: u8 = @bitCast(prot);
        if (prot.write == 1) {
            prot_mask |= @intFromEnum(mach.VmProt.COPY);
        }
        const child_task = pid.getPortForPid();
        child_task.protect(addr, false, prot_mask) catch |err| panic("Cannot set memory protection: {*}, len: {}, prot: {b}, err: {}", .{ addr, addr.len, prot_mask, err });
    }

    pub fn readMemory(pid: *PID, T: type, at: [*]const u8) T {
        var out: T = undefined;
        const child_task = pid.getPortForPid();
        _ = child_task.readMemOverwrite(at, @sizeOf(T), std.mem.asBytes(&out)) catch |err| panic("Cannot read memory {*}, len: {}: {}", .{ at, @sizeOf(T), err });
        return out;
    }

    pub fn writeMemory(pid: *PID, addr: []const u8, data: []const u8) void {
        const child_task = pid.getPortForPid();
        child_task.writeMem(addr.ptr, data) catch |err| panic("Cannot write memory {*}, len: {}: {}", .{ addr, data.len, err });
    }

    pub fn waitForPid(pid: *PID) void {
        while (true) {
            std.log.debug("waitForPid: {}", .{pid.pid});
            const status = pid.pid.wait(posix.W.NOHANG) catch |err| panic("Cannot wait for pid {}: {}", .{ pid.pid, err });
            if (status.IFEXITED()) {
                break;
            }

            const request = pid.exception_port.?.receiveMessage(100, mach.Port.none) catch |err| switch (err) {
                error.RcvTimedOut => continue,
                else => panic("Cannot receive message: {}", .{err}),
            };
            std.log.debug("[mach] received message: {}", .{request.header});

            var reply = machMsgHandler(pid, request);

            std.log.debug("[mach] message handled, responding with: {}", .{reply.header});
            pid.exception_port.?.sendMessage(&reply, 0, mach.Port.none) catch |err|
                panic("Cannot send message: {}", .{err});
        }
    }

    fn machMsgHandler(pid: *PID, msg: mach.MessageRequest) mach.MessageReply {
        std.log.debug("machMsgHandler: msg.header.id: {d}", .{@intFromEnum(msg.header.id)});
        var reply = mach.MessageReply{
            .header = .{
                .bits = mach.messageReplyBits(msg.header.bits),
                .remote_port = msg.header.remote_port,
                .local_port = mach.Port.none,
                .voucher_port = mach.Port.none,
                .id = @enumFromInt(@intFromEnum(msg.header.id) + 100),
                .size = @sizeOf(mach.MessageHeader),
            },
        };

        return switch (msg.header.id) {
            .exception_raise => reply: {
                std.log.debug("exception_raise: {}", .{msg.exception_raise});
                const req = msg.exception_raise;
                const ts = req.thread.name.threadGetState(.ARM64) catch |err| panic("Cannot get thread state: {}", .{err});
                std.log.debug("Thread state: {}", .{ts.arm64});

                reply.exception_raise.RetCode = if (pid.breakpoint_handler.?(@ptrCast(pid), ts.arm64.pc)) mach.KernelReturn.Success else mach.KernelReturn.Failure;
                reply.exception_raise.NDR = mach.NDR_record.default;
                reply.header.size = @sizeOf(@TypeOf(reply.exception_raise));

                std.log.debug("Exception_handled: {}", .{reply.exception_raise});
                break :reply reply;
            },
            else => badId(reply.header),
        };
    }

    fn badId(hdr: mach.MessageHeader) mach.MessageReply {
        std.log.debug("badId: {}", .{hdr.id});
        var reply = mach.MessageReply{ .@"error" = .{
            .hdr = hdr,
            .NDR = .default,
            .RetCode = .MigBadId,
        } };
        reply.header.size = @sizeOf(@TypeOf(reply.@"error"));
        return reply;
    }
};
