display: *Display,
registry: *Registry,
connected: bool = false,

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
    cursor_manager: ?*CursorShapeManager = null,
    cursor_shape: ?*CursorShapeDevice = null,
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
pub const CursorShapeManager = client.wp.CursorShapeManagerV1;
pub const CursorShapeDevice = client.wp.CursorShapeDeviceV1;

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
    try w.roundtrip();
    w.connected = true;
}

pub fn raze(w: *Wayland) void {
    w.connected = false;
    if (w.toplevel) |tl| tl.destroy();
    if (w.xdgsurface) |s| s.destroy();
    if (w.surface) |s| s.destroy();
}

pub fn roundtrip(w: *Wayland) !void {
    switch (w.display.roundtrip()) {
        .SUCCESS => {},
        else => |wut| {
            log.err("Wayland Roundtrip failed {}", .{wut});
            return error.WaylandRoundtripError;
        },
    }
}

pub fn iterate(w: Wayland) !void {
    switch (w.display.dispatch()) {
        .SUCCESS => {},
        else => |wut| {
            log.err("Wayland Dispatch failed {}", .{wut});
            return error.WaylandDispatchError;
        },
    }
}

pub fn attach(w: *Wayland, b: Buffer) !void {
    const surface = w.surface orelse return error.NoSurface;
    surface.attach(b.buffer, 0, 0);
    surface.commit();
    try w.roundtrip();
}

pub fn rename(w: *Wayland, name: []const u8) !void {
    var buffer: [2048]u8 = undefined;
    const nameZ = try std.fmt.bufPrintZ(&buffer, "{s}", .{name});
    if (w.toplevel) |tl| {
        tl.setTitle(nameZ);
    }
}

pub fn resize(w: *Wayland, box: Buffer.Box) !void {
    if (w.toplevel) |tl| {
        tl.setMaxSize(@intCast(box.w), @intCast(box.h));
        tl.setMinSize(@intCast(box.w), @intCast(box.h));
    }
    if (w.xdgsurface) |xs| {
        xs.setWindowGeometry(@intCast(box.x), @intCast(box.y), @intCast(box.w), @intCast(box.h));
    }
    if (w.surface) |s| s.commit();
    try w.roundtrip();
}

pub fn configure(_: *Wayland, evt: Toplevel.Event) void {
    switch (evt) {
        .configure => |c| log.debug("xdg_toplvl   conf {}", .{c}),
        .configure_bounds => |b| log.debug("xdg_toplvl bounds {}", .{b}),
        .wm_capabilities => |c| log.debug("xdg_toplvl   caps {}", .{c}),
        .close => unreachable,
    }
}

pub fn quit(wl: *Wayland) void {
    wl.connected = false;
}

pub fn getUi(wl: *Wayland) *Ui {
    const char: *Charcoal = @fieldParentPtr("wayland", wl);
    return &char.ui;
}

pub fn initDmabuf(wl: *Wayland) !void {
    const dmabuf = wl.dmabuf orelse return error.NoDMABUF;
    if (wl.surface) |surface| {
        const feedback = try dmabuf.getSurfaceFeedback(surface);
        log.debug("dma feedback {}", .{feedback});
    } else {
        const feedback = try dmabuf.getDefaultFeedback();
        log.debug("dma feedback {}", .{feedback});
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
const listeners = @import("listeners.zig");
