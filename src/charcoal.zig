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
        try c.iterateTick(null);
    }

    pub fn iterateTick(c: Charcoal, tick_ptr: ?*anyopaque) !void {
        if (!c.wayland.connected) return error.WaylandExited;
        try c.wayland.iterate();

        c.ui.tick(tick_ptr);
    }

    pub fn run(c: Charcoal) !void {
        var i: usize = 0;
        while (c.running and c.wayland.connected) : (i +%= 1) {
            const buffer = c.ui.active_buffer orelse return error.DrawBufferMissing;
            const surface = c.wayland.surface orelse return error.WaylandNotReady;
            try c.iterate();

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
        }
    }
};

pub const Buffer = @import("Buffer.zig");
pub const Ui = @import("Ui.zig");
pub const Wayland = @import("Wayland.zig");

test {
    _ = &Buffer;
    _ = &Ui;
    _ = &Wayland;
    _ = std.testing.refAllDecls(@This());
}

const std = @import("std");
const Allocator = std.mem.Allocator;
