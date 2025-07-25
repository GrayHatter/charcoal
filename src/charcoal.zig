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

    pub fn raze(c: Charcoal) void {
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

pub const Wayland = struct {
    running: bool = true,
    display: *Display,
    registry: *Registry,

    compositor: ?*Compositor = null,
    shm: ?*Shm = null,
    output: ?*Output = null,
    surface: ?*Surface = null,

    toplevel: ?*Toplevel = null,
    wm_base: ?*WmBase = null,
    xdgsurface: ?*XdgSurface = null,

    seat: ?*Seat = null,
    hid: struct {
        pointer: ?*Pointer = null,
        keyboard: ?*Keyboard = null,
    } = .{},

    dmabuf: ?*LinuxDmabufV1 = null,

    const wayland_ = @import("wayland");
    pub const client = wayland_.client;
    pub const Compositor = client.wl.Compositor;
    pub const Shm = client.wl.Shm;
    pub const Output = client.wl.Output;
    pub const Display = client.wl.Display;
    pub const Registry = client.wl.Registry;
    pub const Surface = client.wl.Surface;
    pub const Seat = client.wl.Seat;
    pub const Pointer = client.wl.Pointer;
    pub const Keyboard = client.wl.Keyboard;

    pub const Toplevel = client.xdg.Toplevel;
    pub const WmBase = client.xdg.WmBase;
    pub const XdgSurface = client.xdg.Surface;

    pub const LinuxDmabufV1 = client.zwp.LinuxDmabufV1;

    pub fn init() !Wayland {
        const display: *Display = try .connect(null);
        return .{
            .display = display,
            .registry = try display.getRegistry(),
        };
    }

    pub fn handshake(w: *Wayland) !void {
        w.registry.setListener(*Wayland, listeners.registry, w);
        try w.roundtrip();

        const compositor = w.compositor orelse return error.NoWlCompositor;
        const wm_base = w.wm_base orelse return error.NoXdgWmBase;

        w.surface = try compositor.createSurface();
        w.xdgsurface = try wm_base.getXdgSurface(w.surface.?);
        w.toplevel = try w.xdgsurface.?.getToplevel(); //  orelse return error.NoToplevel;
        w.xdgsurface.?.setListener(*Wayland, listeners.xdgSurfaceEvent, w);
        w.toplevel.?.setListener(*Wayland, listeners.xdgToplevelEvent, w);
    }

    pub fn raze(w: Wayland) void {
        if (w.toplevel) |tl| tl.destroy();
        if (w.xdgsurface) |s| s.destroy();
        if (w.surface) |s| s.destroy();
    }

    pub fn roundtrip(w: *Wayland) !void {
        if (w.display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
    }

    pub fn iterate(w: *Wayland) !void {
        switch (w.display.dispatch()) {
            .SUCCESS => {},
            else => |wut| {
                std.debug.print("Wayland Dispatch failed {}\n", .{wut});
            },
        }
    }

    pub fn resize(w: *Wayland, box: Buffer.Box) !void {
        if (w.toplevel) |tl| {
            tl.setMaxSize(@intCast(box.w), @intCast(box.h));
            tl.setMinSize(@intCast(box.w), @intCast(box.h));
        }
        if (w.surface) |s| s.commit();
        try w.roundtrip();
    }

    pub fn configure(_: *Wayland, evt: Toplevel.Event) void {
        const debug = false;
        switch (evt) {
            .configure => |conf| if (debug) std.debug.print("toplevel conf {}\n", .{conf}),
            .configure_bounds => |bounds| if (debug) std.debug.print("toplevel bounds {}\n", .{bounds}),
            .wm_capabilities => |caps| if (debug) std.debug.print("toplevel caps {}\n", .{caps}),
            .close => unreachable,
        }
    }

    pub fn quit(wl: *Wayland) void {
        wl.running = false;
    }

    pub fn getUi(wl: *Wayland) *Ui {
        const char: *Charcoal = @fieldParentPtr("wayland", wl);
        return &char.ui;
    }

    pub fn initDmabuf(wl: *Wayland) !void {
        const dmabuf = wl.dmabuf orelse return error.NoDMABUF;
        if (wl.surface) |surface| {
            const feedback = try dmabuf.getSurfaceFeedback(surface);
            std.debug.print("dma feedback {}\n", .{feedback});
        } else {
            const feedback = try dmabuf.getDefaultFeedback();
            std.debug.print("dma feedback {}\n", .{feedback});
        }
        // TODO implement listener/processor

        try wl.roundtrip();
    }
};

test {
    _ = &listeners;
    _ = &Buffer;
    _ = &Ui;
    _ = std.testing.refAllDecls(@This());
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const listeners = @import("listeners.zig").Listeners;
