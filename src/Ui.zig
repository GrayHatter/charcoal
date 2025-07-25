root: ?*Component = null,
keymap: Keymap = .{},
hid: struct {
    mods: u32 = 0,
} = .{},

const Ui = @This();

pub const Keymap = @import("Keymap.zig");
pub const Component = @import("ui/Component.zig").Component;

pub const Event = union(enum) {
    key: Wayland.Keyboard.Event,
    pointer: Wayland.Pointer.Event,
};

pub fn init(u: *Component) Ui {
    return .{
        .root = u,
    };
}

pub fn raze(_: Ui) void {}

pub fn tick(u: Ui, ptr: ?*anyopaque) void {
    if (u.root) |root| {
        root.tick(ptr);
    }
}

pub fn event(u: *Ui, evt: Event) void {
    const debug_events = false;
    switch (evt) {
        .key => |k| switch (k) {
            .key => |key| {
                switch (key.state) {
                    .pressed => {},
                    .released => {},
                    else => |unk| {
                        if (debug_events) std.debug.print("unexpected keyboard key state {} \n", .{unk});
                    },
                }
                const uiroot = u.root orelse return;
                const mods: Keymap.Modifiers = .init(u.hid.mods);
                _ = uiroot.keyPress(.{
                    .up = key.state == .released,
                    .key = if (u.keymap.ascii(key.key, mods)) |asc|
                        .{ .char = asc }
                    else
                        .{ .ctrl = u.keymap.ctrl(key.key) },
                    .mods = mods,
                });
            },
            .modifiers => {
                u.hid.mods = k.modifiers.mods_depressed;
                if (debug_events) std.debug.print("mods {}\n", .{k.modifiers});
            },
            else => {},
        },
        .pointer => |point| switch (point) {
            .button => |btn| {
                const chr: *Charcoal = @fieldParentPtr("ui", u);
                chr.wayland.toplevel.?.move(chr.wayland.seat.?, btn.serial);
            },
            else => {},
        },
    }
}

pub fn newKeymap(u: *Ui, evt: Wayland.Keyboard.Event) void {
    if (false) std.debug.print("newKeymap {} {}\n", .{ evt.keymap.fd, evt.keymap.size });
    if (Keymap.initFd(evt.keymap.fd, evt.keymap.size)) |km| {
        u.keymap = km;
    } else |_| {
        // TODO don't ignore error
    }
}

const std = @import("std");
pub const charcoal = @import("charcoal.zig");
pub const Wayland = charcoal.Wayland;
pub const Charcoal = charcoal.Charcoal;
