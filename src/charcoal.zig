pub const Charcoal = struct {
    wayland: Wayland,
    ui: Ui,

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
        c.ui.raze();
    }

    pub fn iterate(c: *Charcoal) !void {
        if (!c.wayland.running) return error.WaylandExited;
        try c.wayland.iterate();

        c.ui.tick(null);
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
