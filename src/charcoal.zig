pub const Charcoal = struct {
    wayland: Wayland,
    ui: Ui,

    running: bool = true,

    pub fn init() !Charcoal {
        const waylnd: Wayland = try .init();
        return .{
            .wayland = waylnd,
            .ui = .{},
        };
    }

    pub fn connect(c: *Charcoal) !void {
        try c.wayland.handshake();
    }

    pub fn raze(c: *Charcoal) void {
        c.wayland.raze();
        //c.ui.raze();
    }

    pub fn iterate(c: Charcoal) !void {
        try c.iterateTick(null, null);
    }

    pub fn iterateTick(c: Charcoal, tik: ?usize) !void {
        if (!c.wayland.connected) return error.WaylandExited;
        try c.wayland.iterate();

        c.ui.tick(tik orelse maxInt(usize));
    }

    pub fn runRateLimit(c: *Charcoal, limit: FrameRate, io: std.Io) !void {
        const sleep: std.Io.Duration = limit.toDelay();
        var next: std.Io.Timestamp = std.Io.Clock.awake.now(io);
        next = next.addDuration(sleep);
        var i: usize = 0;
        var buffer = c.ui.active_buffer orelse return error.DrawBufferMissing;
        c.ui.background(buffer, .wh(buffer.width, buffer.height));
        c.ui.redraw(buffer, .wh(buffer.width, buffer.height));
        while (c.running and c.wayland.connected) : ({
            const sleep_ns = next.withClock(.awake).untilNow(io);
            try sleep_ns.sleep(io);
            next = std.Io.Clock.awake.now(io).addDuration(sleep);
            i +%= 1;
            try c.iterateTick(i);
        }) {
            buffer = c.ui.active_buffer orelse return error.DrawBufferMissing;
            const surface = c.wayland.surface orelse return error.WaylandNotReady;
            if (i % 100_000 == 0) {
                @branchHint(.unlikely);
                if (i % 1_000_000 == 0) c.ui.background(buffer, .wh(buffer.width, buffer.height));
                c.ui.redraw(buffer, .wh(buffer.width, buffer.height));
                surface.attach(buffer.buffer, 0, 0);
                surface.damage(0, 0, @intCast(buffer.width), @intCast(buffer.height));
                surface.commit();
            } else {
                c.ui.draw(buffer, .wh(buffer.width, buffer.height));
                const dmg = buffer.getDamage() orelse continue;
                surface.attach(buffer.buffer, 0, 0);
                surface.damage(@intCast(dmg.x), @intCast(dmg.y), @intCast(dmg.w), @intCast(dmg.h));
                surface.commit();
            }
            // if (i % 1000 == 0) log.debug("tick {d:10}", .{i / 1000});
        }
    }

    pub fn run(c: *Charcoal) !void {
        var i: usize = 0;
        var buffer = c.ui.active_buffer orelse return error.DrawBufferMissing;
        c.ui.background(buffer, .wh(buffer.width, buffer.height));
        c.ui.redraw(buffer, .wh(buffer.width, buffer.height));
        while (c.running and c.wayland.connected) : ({
            try c.iterateTick(i);
            i +%= 1;
        }) {
            buffer = c.ui.active_buffer orelse return error.DrawBufferMissing;
            const surface = c.wayland.surface orelse return error.WaylandNotReady;
            if (i % 100_000 == 0) {
                @branchHint(.unlikely);
                if (i % 1_000_000 == 0) c.ui.background(buffer, .wh(buffer.width, buffer.height));
                c.ui.redraw(buffer, .wh(buffer.width, buffer.height));
                surface.attach(buffer.buffer, 0, 0);
                surface.damage(0, 0, @intCast(buffer.width), @intCast(buffer.height));
                surface.commit();
            } else {
                c.ui.draw(buffer, .wh(buffer.width, buffer.height));
                const dmg = buffer.getDamage() orelse continue;
                surface.attach(buffer.buffer, 0, 0);
                surface.damage(@intCast(dmg.x), @intCast(dmg.y), @intCast(dmg.w), @intCast(dmg.h));
                surface.commit();
            }
            // if (i % 1000 == 0) log.debug("tick {d:10}", .{i / 1000});
        }
    }

    pub fn createBuffer(c: Charcoal, box: Buffer.Box) !Buffer {
        return try c.createBufferCapacity(box, box);
    }

    pub fn createBufferCapacity(c: Charcoal, box: Box, extra: Box) !Buffer {
        const shm = c.wayland.shm orelse return error.NoWlShm;
        return try .initCapacity(shm, box, extra, "charcoal-wlbuffer");
    }
};

pub const FrameRate = enum(usize) {
    unlimited = std.math.maxInt(usize),
    _,

    const scale = 1_000;

    pub fn fps(rate: anytype) FrameRate {
        return switch (@typeInfo(@TypeOf(rate))) {
            .comptime_int => @enumFromInt(rate * scale),
            .comptime_float => @enumFromInt(@as(usize, @intFromFloat(@trunc(rate * scale)))),
            .int => |int| switch (int.signedness) {
                .signed => @compileError("Signed Ints are not implemented FrameRate.fps()"),
                .unsigned => @enumFromInt(rate * scale),
            },
            .float => @enumFromInt(@as(usize, @intFromFloat(@trunc(@as(f64, rate) * scale)))),
            else => @compileError("Unimplemented type " ++ @typeName(@TypeOf(rate)) ++ " passed to FrameRate.fps()"),
        };
    }

    pub fn toDelay(rate: FrameRate) std.Io.Duration {
        return .{ .nanoseconds = -@as(i96, @intCast(@divFloor(1_000_000_000 * scale, @intFromEnum(rate)))) };
    }
};

test FrameRate {
    var fr: FrameRate = .fps(10);
    fr = .fps(10.0);
    fr = .fps(@as(usize, 10));
    fr = .fps(@as(f16, 10));
    const delay: std.Io.Duration = .{ .nanoseconds = -16666666 };
    fr = .fps(60);
    try std.testing.expectEqualDeep(delay, fr.toDelay());
}

pub const Buffer = @import("Buffer.zig");
pub const Ui = @import("Ui.zig");
pub const Wayland = @import("Wayland.zig");
pub const TrueType = @import("truetype.zig");

test {
    _ = &Buffer;
    _ = &Ui;
    _ = &Wayland;
    _ = &TrueType;
    _ = std.testing.refAllDecls(@This());
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.charcoal);
const Box = Buffer.Box;
const maxInt = std.math.maxInt;
