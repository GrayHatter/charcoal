wayland: Wayland,
ui: Ui,
running: bool = true,

const Charcoal = @This();

pub const Box = @import("Box.zig");
pub const Buffer = @import("Buffer.zig");
pub const TrueType = @import("truetype.zig");
pub const Ui = @import("Ui.zig");
pub const Wayland = @import("Wayland.zig");

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
}

pub fn tickWithEvents(c: *const Charcoal, tik: usize) !void {
    if (!c.wayland.connected) return error.WaylandExited;
    try c.wayland.iterate();
    c.ui.tick(tik);
}

inline fn redraw(tick: usize, ui: *const Ui, buffer: *Buffer, srfc: *Wayland.Surface) void {
    if (tick % 100_000 == 0) {
        @branchHint(.unlikely);
        if (tick % 1_000_000 == 0) ui.background(buffer, .wh(buffer.width, buffer.height));
        ui.redraw(buffer, .wh(buffer.width, buffer.height));
        srfc.attach(buffer.buffer, 0, 0);
        srfc.damage(0, 0, @intCast(buffer.width), @intCast(buffer.height));
        srfc.commit();
        return;
    }

    ui.draw(buffer, .wh(buffer.width, buffer.height));
    const dmg = buffer.getDamage() orelse return;
    // We're required to reattach the buffer every time :/
    srfc.attach(buffer.buffer, 0, 0);
    srfc.damage(@intCast(dmg.x), @intCast(dmg.y), @intCast(dmg.w2()), @intCast(dmg.h2()));
    srfc.commit();
}

pub fn runRateLimit(c: *const Charcoal, limit: FrameRate, io: std.Io) !void {
    const surface = c.wayland.surface orelse return error.WaylandNotReady;
    const sleep: std.Io.Duration = limit.toDelay();
    var next: std.Io.Timestamp = std.Io.Clock.awake.now(io);
    var i: usize = 0;
    // Damage the whole buffer on the first draw
    if (c.ui.active_buffer) |buf| buf.damageAll();
    while (c.running and c.wayland.connected) {
        defer i +%= 1;
        next = std.Io.Clock.awake.now(io).addDuration(sleep);
        try c.tickWithEvents(i);
        if (c.ui.active_buffer) |buf| redraw(i, &c.ui, buf, surface);
        const sleep_ns = next.withClock(.awake).untilNow(io);
        try sleep_ns.sleep(io);
    }
}

pub fn run(c: *Charcoal) !void {
    const surface = c.wayland.surface orelse return error.WaylandNotReady;
    var i: usize = 0;
    if (c.ui.active_buffer) |buf| buf.damageAll();
    while (c.running and c.wayland.connected) {
        defer i +%= 1;
        try c.tickWithEvents(i);
        if (c.ui.active_buffer) |*buf| redraw(i, &c.ui, buf, surface);
    }
}

/// This can be used to create a single buffer with name `charcoal-wlbuffer`. For additional
/// buffers, call `createBufferCapacity` or `Wayland.createBuffer` directly.
pub fn createBuffer(c: *const Charcoal, box: Box) !Buffer {
    const buffer = try c.createBufferCapacity(box, box, "charcoal-wlbuffer");
    try c.wayland.resize(box);
    try c.wayland.attach(&buffer);
    return buffer;
}

pub fn createBufferCapacity(c: *const Charcoal, box: Box, extra: Box, name: [:0]const u8) !Buffer {
    return try c.wayland.createBufferCapacity(box, extra, name);
}

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

test {
    _ = &Box;
    _ = &Buffer;
    _ = &TrueType;
    _ = &Ui;
    _ = &Wayland;
    _ = std.testing.refAllDecls(@This());
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.charcoal);
const maxInt = std.math.maxInt;
