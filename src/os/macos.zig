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

var pid_port_map: std.AutoArrayHashMap(PID, platform.MachPort) = .init(core.arena);
var exception_port: platform.MachPort = undefined;
var breakpoint_handler: *const fn (pc: usize) bool = undefined;

pub fn getPortForPid(pid: PID) platform.MachPort {
    if (pid == PID.current) {
        return platform.taskSelf();
    }

    const result = pid_port_map.getOrPut(pid) catch unreachable;
    if (result.found_existing) {
        return result.value_ptr.*;
    }

    const port = platform.taskSelf().taskForPid(pid) catch |err| panic("Cannot get child task for pid {}: {}", .{ pid, err });
    result.value_ptr.* = port;
    return port;
}

pub fn spawnForTracing(args: []const []const u8) PID {
    var temp_arena = std.heap.ArenaAllocator.init(core.gpa);
    defer temp_arena.deinit();
    const temp = temp_arena.allocator();

    var argsZ = std.ArrayList(?[*:0]const u8).initCapacity(temp, args.len + 1) catch unreachable;
    for (args) |arg| {
        argsZ.append(temp.dupeZ(u8, arg) catch unreachable) catch unreachable;
    }

    var attrp = platform.PosixSpawnAttr.init() catch |err| panic("posix_spawnattr_init failed: {}", .{err});
    attrp.setSigMask(platform.empty_sigset) catch |err| panic("posix_spawnattr_setsigmask failed: {}", .{err});
    attrp.setSigDefault(platform.filled_sigset) catch |err| panic("posix_spawnattr_setsigdefault failed: {}", .{err});
    attrp.setFlags(platform.POSIX_SPAWN_SETSIGDEF | platform.POSIX_SPAWN_SETSIGMASK | platform.POSIX_SPAWN_SETPGROUP | platform.POSIX_SPAWN_START_SUSPENDED) catch |err|
        panic("posix_spawnattr_setflags failed: {}", .{err});

    return platform.posixSpawn(argsZ.toOwnedSliceSentinel(null) catch unreachable, null, attrp, &.{null}) catch |err|
        panic("posix_spawn failed: {}", .{err});
}

pub fn processResume(pid: PID) void {
    const child_task: platform.MachPort = getPortForPid(pid);
    child_task.@"resume"() catch |err| panic("Cannot resume task: {}", .{err});
}

pub fn processSuspend(pid: PID) void {
    const child_task: platform.MachPort = getPortForPid(pid);
    child_task.@"suspend"() catch |err| panic("Cannot suspend task: {}", .{err});
}

pub fn getMemoryRegion(pid: PID, address: usize) []const u8 {
    const task = getPortForPid(pid);
    const result = task.vmRegionRecurse(address, 1024) catch |err| panic("Cannot get vm region for pid {}: {}", .{ pid, err });

    return @as([*]const u8, @ptrFromInt(result.address))[0..result.size];
}

pub fn setupBreakpointHandler(pid: PID, handler: *const fn (pc: usize) bool) void {
    const child_task: platform.MachPort = getPortForPid(pid);
    exception_port = platform.taskSelf().portAllocate(platform.MachPortRight.RECEIVE) catch |err| panic("Cannot allocate exception port: {}", .{err});
    platform.taskSelf().portInsertRight(exception_port, exception_port, platform.MachMsgType.MAKE_SEND) catch |err| panic("Cannot insert exception port: {}", .{err});
    child_task.setExceptionPorts(platform.EXC.MASK.ALL, exception_port, @intFromEnum(platform.ExceptionType.default) | @intFromEnum(platform.ExceptionType.exception_codes), .NONE) catch |err|
        panic("Cannot set exception ports: {}", .{err});
    breakpoint_handler = handler;
    std.log.debug("setupBreakpointHandler: pid: {}, child_task: {}, exc_port: {}", .{ pid, child_task, exception_port });
}

pub fn setMemoryProtection(pid: PID, addr: []const u8, prot: core.EnumMask(platform.VmProt)) void {
    std.log.debug("setMemoryWritable: pid: {}, addr: {*}, size: {}, prot: {b}", .{ pid, addr, addr.len, @as(u8, @bitCast(prot)) });
    const child_task = getPortForPid(pid);
    child_task.protect(addr, false, @bitCast(prot)) catch |err| panic("Cannot set memory protection: {*}, len: {}, prot: {b}, err: {}", .{ addr, addr.len, @as(u8, @bitCast(prot)), err });
}

pub fn readMemory(pid: PID, T: type, at: [*]u8) T {
    var out: T = undefined;
    const child_task = getPortForPid(pid);
    _ = child_task.readMemOverwrite(at, @sizeOf(T), std.mem.asBytes(&out)) catch |err| panic("Cannot read memory {*}, len: {}: {}", .{ at, @sizeOf(T), err });
    return out;
}

pub fn writeMemory(pid: PID, addr: []const u8, data: []const u8) void {
    const child_task = getPortForPid(pid);
    child_task.writeMem(addr.ptr, data) catch |err| panic("Cannot write memory {*}, len: {}: {}", .{ addr, data.len, err });
}

pub fn waitForPid(pid: PID) void {
    while (true) {
        std.log.debug("waitForPid: {}", .{pid});
        const status = pid.wait(platform.W.NOHANG) catch |err| panic("Cannot wait for pid {}: {}", .{ pid, err });
        if (status.IFEXITED()) {
            break;
        }

        const request = exception_port.receiveMessage(100, platform.MachPort.none) catch |err| switch (err) {
            error.RcvTimedOut => continue,
            else => panic("Cannot receive message: {}", .{err}),
        };
        std.log.debug("[mach] received message: {}", .{request.header});

        var reply = machMsgHandler(request);

        std.log.debug("[mach] message handled, responding with: {}", .{reply.header});
        exception_port.sendMessage(&reply, 0, platform.MachPort.none) catch |err|
            panic("Cannot send message: {}", .{err});
    }
}

fn machMsgHandler(msg: platform.MachMsgRequest) platform.MachMsgReply {
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

            reply.exception_raise.RetCode = if (breakpoint_handler(ts.arm64.pc)) platform.MachKernelReturn.Success else platform.MachKernelReturn.Failure;
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
