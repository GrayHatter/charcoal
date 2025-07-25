root: ?*Component = null,
keymap: Keymap = .{},
hid: struct {
    mods: u32 = 0,
} = .{},
active_buffer: ?*Buffer = null,

const Ui = @This();

pub const Component = @import("ui/Component.zig");

pub const Event = union(enum) {
    key: Wayland.Keyboard.Event,
    pointer: Wayland.Pointer.Event,

    pub const Key = Component.KeyEvent;
    pub const MMove = Component.Pointer.Movement;
    pub const Click = Component.Pointer.Click;
};

pub fn init(ui: *Ui, comp: *Component, a: Allocator, b: Buffer.Box) Component.InitError!void {
    ui.root = comp;

    try ui.root.?.init(a, b);
}

pub fn raze(ui: *Ui, a: Allocator) void {
    if (ui.root) |root| {
        root.raze(a);
    }
    ui.root = null;
}

pub fn tick(ui: Ui, ptr: ?*anyopaque) void {
    if (ui.root) |root| {
        root.tick(ptr);
    }
}

pub fn background(ui: Ui, buffer: *const Buffer, box: Buffer.Box) void {
    const root = ui.root orelse return;
    root.background(buffer, box);
}

pub fn draw(ui: Ui, buffer: *const Buffer, box: Buffer.Box) void {
    const root = ui.root orelse return;
    if (root.damaged) {
        root.draw(buffer, box);
    }
}

pub fn redraw(ui: Ui, buffer: *const Buffer, box: Buffer.Box) void {
    const root = ui.root orelse return;
    root.draw(buffer, box);
}

pub fn event(ui: *Ui, evt: Event) void {
    const root = ui.root orelse {
        log.warn("UI not ready for event {}", .{evt});
        return;
    };
    switch (evt) {
        .key => |k| switch (k) {
            .key => |key| {
                switch (key.state) {
                    .pressed => {},
                    .released => {},
                    else => |unk| {
                        log.debug("unexpected keyboard key state {}", .{unk});
                    },
                }
                const mods: Keymap.Modifiers = .init(ui.hid.mods);
                _ = root.keyPress(.{
                    .up = key.state == .released,
                    .key = if (ui.keymap.ascii(key.key, mods)) |asc|
                        .{ .char = asc }
                    else
                        .{ .ctrl = ui.keymap.ctrl(key.key) },
                    .mods = mods,
                });
            },
            .modifiers => {
                ui.hid.mods = k.modifiers.mods_depressed;
                log.debug("mods {}", .{k.modifiers});
            },
            else => {},
        },
        .pointer => |point| switch (point) {
            .button => |btn| {
                const chr: *Charcoal = @fieldParentPtr("ui", ui);
                chr.wayland.toplevel.?.move(chr.wayland.seat.?, btn.serial);
            },
            else => {},
        },
    }
}

pub fn newKeymap(u: *Ui, evt: Wayland.Keyboard.Event) void {
    log.debug("newKeymap {} {}", .{ evt.keymap.fd, evt.keymap.size });
    if (Keymap.initFd(evt.keymap.fd, evt.keymap.size)) |km| {
        u.keymap = km;
    } else |_| {
        // TODO don't ignore error
    }
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.charcoal_ui);
const charcoal = @import("charcoal.zig");
const Charcoal = charcoal.Charcoal;
const Wayland = @import("Wayland.zig");
const Keymap = @import("Keymap.zig");
const Buffer = @import("Buffer.zig");
