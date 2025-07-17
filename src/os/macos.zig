const std = @import("std");
const assert = std.debug.assert;
const panic = std.debug.panic;

const platform = @import("../platform.zig");
const builtin = @import("builtin");
const native_arch = builtin.target.cpu.arch;
const core = @import("../core.zig");
const LineInfoHashMap = @import("../file/debug_info.zig").LineInfoHashMap;

pub const PID = platform.PosixPID;
pub const Breakpoint = core.Breakpoint;

pub fn getPortForPid(ctx: *core.Context, pid: PID) platform.MachPort {
    if (pid == PID.current) {
        return platform.taskSelf();
    }

    if (ctx.process_port_map.get(pid)) |port| {
        return port;
    }

    const port = platform.taskSelf().taskForPid(pid) catch |err| panic("Cannot get child task for pid {}: {}", .{ pid, err });
    ctx.process_port_map.put(pid, port) catch unreachable;
    return port;
}

pub fn spawnForTracing(ctx: *core.Context, args: []const []const u8) PID {
    var scratch_arena = std.heap.ArenaAllocator.init(ctx.gpa);
    defer scratch_arena.deinit();
    const scratch = scratch_arena.allocator();

    var argsZ = std.ArrayList(?[*:0]const u8).initCapacity(scratch, args.len + 1) catch unreachable;
    for (args) |arg| {
        argsZ.append(scratch.dupeZ(u8, arg) catch unreachable) catch unreachable;
    }

    var attrp = platform.PosixSpawnAttr.init() catch |err| panic("posix_spawnattr_init failed: {}", .{err});
    attrp.setSigMask(platform.empty_sigset) catch |err| panic("posix_spawnattr_setsigmask failed: {}", .{err});
    attrp.setSigDefault(platform.filled_sigset) catch |err| panic("posix_spawnattr_setsigdefault failed: {}", .{err});
    attrp.setFlags(platform.POSIX_SPAWN_SETSIGDEF | platform.POSIX_SPAWN_SETSIGMASK | platform.POSIX_SPAWN_SETPGROUP | platform.POSIX_SPAWN_START_SUSPENDED) catch |err|
        panic("posix_spawnattr_setflags failed: {}", .{err});

    return platform.posixSpawn(argsZ.toOwnedSliceSentinel(null) catch unreachable, null, attrp, &.{null}) catch |err|
        panic("posix_spawn failed: {}", .{err});
}

pub fn processResume(ctx: *core.Context, pid: PID) void {
    const child_task: platform.MachPort = getPortForPid(ctx, pid);
    child_task.@"resume"() catch |err| panic("Cannot resume task: {}", .{err});
}

pub fn processSuspend(ctx: *core.Context, pid: PID) void {
    const child_task: platform.MachPort = getPortForPid(ctx, pid);
    child_task.@"suspend"() catch |err| panic("Cannot suspend task: {}", .{err});
}

pub fn getMemoryRegion(ctx: *core.Context, pid: PID, address: usize) []const u8 {
    const task = getPortForPid(ctx, pid);
    const result = task.vmRegionRecurse(address, 1024) catch |err| panic("Cannot get vm region for pid {}: {}", .{ pid, err });

    return @as([*]const u8, @ptrFromInt(result.address))[0..result.size];
}

pub fn setupBreakpointHandler(ctx: *core.Context, pid: PID, handler: *const fn (ctx: *core.Context, pc: usize) bool) void {
    const exception_port = ctx.exception_port_map.getOrPut(pid) catch unreachable;
    if (exception_port.found_existing) {
        return;
    }

    const child_task: platform.MachPort = getPortForPid(ctx, pid);
    exception_port.value_ptr.* = platform.taskSelf().portAllocate(platform.MachPortRight.RECEIVE) catch |err| panic("Cannot allocate exception port: {}", .{err});
    platform.taskSelf().portInsertRight(exception_port.value_ptr.*, exception_port.value_ptr.*, platform.MachMsgType.MAKE_SEND) catch |err| panic("Cannot insert exception port: {}", .{err});
    child_task.setExceptionPorts(
        platform.EXC.MASK.ALL,
        exception_port.value_ptr.*,
        @intFromEnum(platform.ExceptionType.default) | @intFromEnum(platform.ExceptionType.exception_codes),
        .NONE,
    ) catch |err|
        panic("Cannot set exception ports: {}", .{err});

    ctx.breakpoint_handler_map.put(pid, handler) catch unreachable;
    std.log.debug("setupBreakpointHandler: pid: {}, child_task: {}, exc_port: {}", .{ pid, child_task, exception_port.value_ptr.* });
}

pub fn setMemoryProtection(ctx: *core.Context, pid: PID, addr: []const u8, prot: core.EnumMask(platform.VmProt)) void {
    std.log.debug("setMemoryWritable: pid: {}, addr: {*}, size: {}, prot: {b}", .{ pid, addr, addr.len, @as(u8, @bitCast(prot)) });
    const child_task = getPortForPid(ctx, pid);
    child_task.protect(addr, false, @bitCast(prot)) catch |err| panic("Cannot set memory protection: {*}, len: {}, prot: {b}, err: {}", .{ addr, addr.len, @as(u8, @bitCast(prot)), err });
}

pub fn readMemory(ctx: *core.Context, pid: PID, T: type, at: [*]const u8) T {
    var out: T = undefined;
    const child_task = getPortForPid(ctx, pid);
    _ = child_task.readMemOverwrite(at, @sizeOf(T), std.mem.asBytes(&out)) catch |err| panic("Cannot read memory {*}, len: {}: {}", .{ at, @sizeOf(T), err });
    return out;
}

pub fn writeMemory(ctx: *core.Context, pid: PID, addr: []const u8, data: []const u8) void {
    const child_task = getPortForPid(ctx, pid);
    child_task.writeMem(addr.ptr, data) catch |err| panic("Cannot write memory {*}, len: {}: {}", .{ addr, data.len, err });
}

pub fn waitForPid(ctx: *core.Context) void {
    while (true) {
        std.log.debug("waitForPid: {}", .{ctx.pid});
        const status = ctx.pid.wait(platform.W.NOHANG) catch |err| panic("Cannot wait for pid {}: {}", .{ ctx.pid, err });
        if (status.IFEXITED()) {
            break;
        }

        const exception_port = ctx.exception_port_map.get(ctx.pid) orelse panic("Cannot get exception port for pid {}", .{ctx.pid});
        const request = exception_port.receiveMessage(100, platform.MachPort.none) catch |err| switch (err) {
            error.RcvTimedOut => continue,
            else => panic("Cannot receive message: {}", .{err}),
        };
        std.log.debug("[mach] received message: {}", .{request.header});

        var reply = machMsgHandler(ctx, request);

        std.log.debug("[mach] message handled, responding with: {}", .{reply.header});
        exception_port.sendMessage(&reply, 0, platform.MachPort.none) catch |err|
            panic("Cannot send message: {}", .{err});
    }
}

fn machMsgHandler(ctx: *core.Context, msg: platform.MachMsgRequest) platform.MachMsgReply {
    std.log.debug("machMsgHandler: msg.header.id: {d}", .{@intFromEnum(msg.header.id)});
    var reply = platform.MachMsgReply{
        .header = .{
            .bits = platform.machMsgReplyBits(msg.header.bits),
            .remote_port = msg.header.remote_port,
            .local_port = platform.MachPort.none,
            .voucher_port = platform.MachPort.none,
            .id = @enumFromInt(@intFromEnum(msg.header.id) + 100),
            .size = @sizeOf(platform.MachMsgHeader),
        },
    };

    return switch (msg.header.id) {
        .exception_raise => reply: {
            std.log.debug("exception_raise: {}", .{msg.exception_raise});
            const req = msg.exception_raise;
            const ts = req.thread.name.threadGetState(.ARM64) catch |err| panic("Cannot get thread state: {}", .{err});
            std.log.debug("Thread state: {}", .{ts.arm64});

            const breakpoint_handler = ctx.breakpoint_handler_map.get(ctx.pid) orelse panic("Cannot get breakpoint handler for pid {}", .{ctx.pid});
            reply.exception_raise.RetCode = if (breakpoint_handler(ctx, ts.arm64.pc)) platform.MachKernelReturn.Success else platform.MachKernelReturn.Failure;
            reply.exception_raise.NDR = platform.NDR_record.default;
            reply.header.size = @sizeOf(@TypeOf(reply.exception_raise));

            std.log.debug("Exception_handled: {}", .{reply.exception_raise});
            break :reply reply;
        },
        else => badId(reply.header),
    };
}

fn badId(hdr: platform.MachMsgHeader) platform.MachMsgReply {
    std.log.debug("badId: {}", .{hdr.id});
    var reply = platform.MachMsgReply{ .@"error" = .{
        .hdr = hdr,
        .NDR = .default,
        .RetCode = .MigBadId,
    } };
    reply.header.size = @sizeOf(@TypeOf(reply.@"error"));
    return reply;
}
