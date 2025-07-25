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

const Wayland = @This();

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

pub fn raze(w: *Wayland) void {
    if (w.toplevel) |tl| tl.destroy();
    if (w.xdgsurface) |s| s.destroy();
    if (w.surface) |s| s.destroy();
    w.running = false;
}

pub fn roundtrip(w: *Wayland) !void {
    switch (w.display.roundtrip()) {
        .SUCCESS => {},
        else => |wut| {
            log.err("Wayland Roundtrip failed {}\n", .{wut});
            return error.WaylandRoundtripError;
        },
    }
}

pub fn iterate(w: *Wayland) !void {
    switch (w.display.dispatch()) {
        .SUCCESS => {},
        else => |wut| {
            log.err("Wayland Dispatch failed {}\n", .{wut});
            return error.WaylandDispatchError;
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
    switch (evt) {
        .configure => |conf| log.debug("toplevel conf {}", .{conf}),
        .configure_bounds => |bounds| log.debug("toplevel bounds {}", .{bounds}),
        .wm_capabilities => |caps| log.debug("toplevel caps {}", .{caps}),
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
        log.debug("dma feedback {}\n", .{feedback});
    } else {
        const feedback = try dmabuf.getDefaultFeedback();
        log.debug("dma feedback {}\n", .{feedback});
    }
    // TODO implement listener/processor

    try wl.roundtrip();
}

test {
    _ = &listeners;
    _ = &Keymap;
}

const std = @import("std");
const log = std.log.scoped(.charcoal_wayland);

const wayland_ = @import("wayland");

const Charcoal = @import("charcoal.zig").Charcoal;
const Keymap = @import("Keymap.zig");
const Buffer = @import("Buffer.zig");
const Ui = @import("Ui.zig");
const listeners = @import("listeners.zig").Listeners;
