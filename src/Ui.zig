root: ?*Component = null,
keymap: Keymap = .{},
hid: struct {
    mods: u32 = 0,
} = .{},

const Ui = @This();

pub const Component = @import("ui/Component.zig");

pub const Event = union(enum) {
    key: Wayland.Keyboard.Event,
    pointer: Wayland.Pointer.Event,
};

pub fn init(ui: *Ui, comp: *Component) Ui {
    ui.root = comp;
}

pub fn raze(_: Ui) void {}

pub fn tick(ui: Ui, ptr: ?*anyopaque) void {
    if (ui.root) |root| {
        root.tick(ptr);
    }
}

pub fn event(ui: *Ui, evt: Event) void {
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
                const root = ui.root orelse return;
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
                log.debug("mods {}\n", .{k.modifiers});
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
    log.debug("newKeymap {} {}\n", .{ evt.keymap.fd, evt.keymap.size });
    if (Keymap.initFd(evt.keymap.fd, evt.keymap.size)) |km| {
        u.keymap = km;
    } else |_| {
        // TODO don't ignore error
    }
}

const log = @import("std").log.scoped(.charcoal_ui);
const charcoal = @import("charcoal.zig");
const Charcoal = charcoal.Charcoal;
const Wayland = @import("Wayland.zig");
pub const Keymap = @import("Keymap.zig");
