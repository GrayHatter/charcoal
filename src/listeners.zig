const Wayland = @import("charcoal.zig").Wayland;
const Ui = @import("charcoal.zig").Ui;

pub fn registry(r: *wl.Registry, event: wl.Registry.Event, ptr: *Wayland) void {
    switch (event) {
        .global => |global| {
            if (orderZ(u8, global.interface, wl.Compositor.interface.name) == .eq) {
                ptr.compositor = r.bind(global.name, wl.Compositor, @min(global.version, wl.Compositor.generated_version)) catch return;
            } else if (orderZ(u8, global.interface, wl.Output.interface.name) == .eq) {
                ptr.output = r.bind(global.name, wl.Output, @min(global.version, wl.Output.generated_version)) catch return;
                ptr.output.?.setListener(*Wayland, outputEvent, ptr);
            } else if (orderZ(u8, global.interface, wl.Shm.interface.name) == .eq) {
                ptr.shm = r.bind(global.name, wl.Shm, @min(global.version, wl.Shm.generated_version)) catch return;
            } else if (orderZ(u8, global.interface, Xdg.WmBase.interface.name) == .eq) {
                ptr.wm_base = r.bind(global.name, Xdg.WmBase, @min(global.version, Xdg.WmBase.generated_version)) catch return;
            } else if (orderZ(u8, global.interface, wl.Seat.interface.name) == .eq) {
                ptr.seat = r.bind(global.name, wl.Seat, @min(global.version, wl.Seat.generated_version)) catch return;
                ptr.seat.?.setListener(*Wayland, seatEvent, ptr);
            } else if (orderZ(u8, global.interface, Zwp.LinuxDmabufV1.interface.name) == .eq) {
                ptr.dmabuf = r.bind(global.name, Zwp.LinuxDmabufV1, @min(global.version, Zwp.LinuxDmabufV1.generated_version)) catch return;
                ptr.dmabuf.?.setListener(*Wayland, dmabufEvent, ptr);
            } else if (orderZ(u8, global.interface, Wp.CursorShapeManagerV1.interface.name) == .eq) {
                log.debug("cursor shape global {s}", .{global.interface});
                ptr.hid.cursor_manager = r.bind(
                    global.name,
                    Wp.CursorShapeManagerV1,
                    @min(global.version, Wp.CursorShapeManagerV1.generated_version),
                ) catch return;
            } else {
                log.debug("extra global {s}", .{global.interface});
            }
        },
        .global_remove => {},
    }
}

fn outputEvent(_: *wl.Output, event: wl.Output.Event, _: *Wayland) void {
    switch (event) {
        .geometry => |geo| {
            log.debug("geo {}", .{geo});
            log.debug("    make {s}", .{std.mem.span(geo.make)});
            log.debug("    model {s}", .{std.mem.span(geo.model)});
        },
        .mode => |mode| {
            log.debug("    mode {}", .{mode.flags});
            log.debug("    width {}", .{mode.width});
            log.debug("    height {}", .{mode.height});
            log.debug("    refresh {}", .{mode.refresh});
        },
        .scale => |scale| log.debug("    scale {}", .{scale.factor}),
        .name => |nameZ| log.debug("    name {s}", .{std.mem.span(nameZ.name)}),
        .description => |descZ| log.debug("    description {s}", .{std.mem.span(descZ.description)}),
        .done => log.debug("done", .{}),
    }
}

pub fn xdgSurfaceEvent(xdg_surface: *Xdg.Surface, event: Xdg.Surface.Event, _: *Wayland) void {
    switch (event) {
        .configure => |configure| {
            log.debug("surface configure event {}", .{configure});
            xdg_surface.ackConfigure(configure.serial);
        },
    }
}

pub fn xdgToplevelEvent(_: *Xdg.Toplevel, event: Xdg.Toplevel.Event, ptr: *Wayland) void {
    switch (event) {
        .close => ptr.quit(),
        .configure_bounds, .wm_capabilities, .configure => {
            log.debug("xdg toplevel event {}", .{event});
            ptr.configure(event);
        },
    }
}

fn dmabufEvent(_: *Zwp.LinuxDmabufV1, evt: Zwp.LinuxDmabufV1.Event, _: *Wayland) void {
    // Only sent in version 1
    switch (evt) {
        .format => |format| {
            // /include/uapi/drm/drm_fourcc.h
            const a: u8 = @truncate(format.format & 0xff);
            const b: u8 = @truncate((format.format >> 8) & 0xff);
            const c: u8 = @truncate((format.format >> 16) & 0xff);
            const d: u8 = @truncate((format.format >> 24) & 0xff);
            log.debug("dma format {} '{c}:{c}:{c}:{c}'", .{ format.format, a, b, c, d });
        },
        .modifier => |mod| {
            log.debug("dma modifier {}", .{mod});
        },
    }
}

fn seatEvent(s: *wl.Seat, evt: wl.Seat.Event, c_wl: *Wayland) void {
    switch (evt) {
        .capabilities => |cap| {
            if (cap.capabilities.pointer) {
                c_wl.hid.pointer = s.getPointer() catch return;
                c_wl.hid.cursor_shape = c_wl.hid.cursor_manager.?.getPointer(c_wl.hid.pointer.?) catch unreachable;
                c_wl.hid.pointer.?.setListener(*Ui, pointerEvent, c_wl.getUi());
            }
            if (cap.capabilities.keyboard) {
                c_wl.hid.keyboard = s.getKeyboard() catch return;
                c_wl.hid.keyboard.?.setListener(*Ui, keyEvent, c_wl.getUi());
            }
        },
        .name => |name| log.debug("name {s}", .{std.mem.span(name.name)}),
    }
}

fn keyEvent(_: *wl.Keyboard, evt: wl.Keyboard.Event, ui: *Ui) void {
    switch (evt) {
        .key => ui.event(.{ .key = evt }),
        .modifiers => ui.event(.{
            .key_mods = evt,
        }),
        .enter => |enter| {
            log.debug("keyboard focus gained {}", .{evt});
            ui.event(.{ .focus = .{
                .from = .{ .keyboard = evt },
                .focus = .enter,
                .serial = enter.serial,
            } });
        },
        .leave => |leave| {
            log.debug("keyboard focus lost {}", .{evt});
            ui.event(.{ .focus = .{
                .from = .{ .keyboard = evt },
                .focus = .leave,
                .serial = leave.serial,
            } });
        },
        .keymap => ui.newKeymap(evt),
        //.repeat_info => {},
        else => {
            log.debug("keyevent other {}", .{evt});
        },
    }
}

fn pointerEvent(_: *wl.Pointer, evt: wl.Pointer.Event, ptr: *Ui) void {
    switch (evt) {
        .enter => |enter| {
            log.debug(
                "ptr enter x {d: <8} y {d: <8}",
                .{ enter.surface_x.toInt(), enter.surface_y.toInt() },
            );
            ptr.event(.{ .focus = .{
                .from = .{ .mouse = evt },
                .focus = .enter,
                .serial = enter.serial,
            } });
        },
        .leave => |leave| {
            log.debug("ptr leave {}", .{leave});
            ptr.event(.{ .focus = .{
                .from = .{ .mouse = evt },
                .focus = .leave,
                .serial = leave.serial,
            } });
        },
        .motion => |motion| {
            log.debug(
                "mm        x {d: <8} y {d: <8}",
                .{ motion.surface_x.toInt(), motion.surface_y.toInt() },
            );
            ptr.event(.{ .pointer = evt });
        }, //log.debug("pointer {}", .{t}),{},
        .button => |button| {
            log.debug("pointer press {}", .{button});
            ptr.event(.{ .pointer = evt });
        },
        .axis => |axis| {
            switch (axis.axis) {
                .vertical_scroll => {},
                .horizontal_scroll => {},
                else => {
                    log.debug("pointer axis {}", .{axis});
                },
            }
            ptr.event(.{ .pointer = evt });
        },
    }
}

const std = @import("std");
const orderZ = std.mem.orderZ;
const log = std.log.scoped(.charcoal_wayland);
const wayland = @import("wayland");
const wl = wayland.client.wl;
const Xdg = wayland.client.xdg;
const Zwp = wayland.client.zwp;
const Wp = wayland.client.wp;
