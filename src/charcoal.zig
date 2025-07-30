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

    pub fn iterateTick(c: Charcoal, tik: ?usize, tick_ptr: ?*anyopaque) !void {
        if (!c.wayland.connected) return error.WaylandExited;
        try c.wayland.iterate();

        c.ui.tick(tik orelse maxInt(usize), tick_ptr);
    }

    pub fn run(c: *Charcoal) !void {
        return try c.runTick(null);
    }

    pub fn runTick(c: *Charcoal, tick_ptr: ?*anyopaque) !void {
        var i: usize = 0;
        const buffer = c.ui.active_buffer orelse return error.DrawBufferMissing;
        while (c.running and c.wayland.connected) : (i +%= 1) {
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
                surface.attach(buffer.buffer, 0, 0);
                surface.damage(0, 0, @intCast(buffer.width), @intCast(buffer.height));
                surface.commit();
            }
            // if (i % 1000 == 0) log.debug("tick {d:10}", .{i / 1000});
            try c.iterateTick(i, tick_ptr);
            std.Thread.sleep(16_000_000);
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
