root: ?*Component = null,
keymap: Keymap = .{},
hid: struct {
    mods: u32 = 0,
} = .{},
active_buffer: ?*Buffer = null,
frame_rate: usize = 60,

const Ui = @This();

pub const Component = @import("ui/Component.zig");

pub const Event = union(enum) {
    key: Wayland.Keyboard.Event,
    pointer: Wayland.Pointer.Event,

    pub const Key = Keyboard.Event;
    pub const MMove = Pointer.Motion;
    pub const Click = Pointer.Click;
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

pub fn tick(ui: Ui, tik: usize, ptr: ?*anyopaque) void {
    if (ui.root) |root| {
        root.tick(tik, ptr);
    }
}

pub fn background(ui: Ui, buffer: *Buffer, box: Buffer.Box) void {
    const root = ui.root orelse return;
    root.background(buffer, box);
}

pub fn draw(ui: Ui, buffer: *Buffer, box: Buffer.Box) void {
    const root = ui.root orelse return;
    if (root.draw_needed) {
        root.draw(buffer, box);
    }
}

fn setDraw(cm: *Ui.Component) void {
    for (cm.children) |*c| c.draw_needed = true;
    cm.draw_needed = true;
}

pub fn redraw(ui: Ui, buffer: *Buffer, box: Buffer.Box) void {
    const root = ui.root orelse return;
    setDraw(root);
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
                    .pressed => {
                        log.debug("keyboard key pressed {}", .{key.key});
                    },
                    .released => {
                        log.debug("keyboard key released {}", .{key.key});
                    },
                    else => |unk| {
                        log.debug("unexpected keyboard key state {}", .{unk});
                    },
                }
                const mods: KMod = .init(ui.hid.mods);
                _ = root.keyPress(.{
                    .up = key.state == .released,
                    .key = if (ui.keymap.ascii(key.key, mods)) |asc|
                        .{ .char = asc }
                    else
                        .{ .ctrl = ui.keymap.ctrl(key.key, mods) },
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
            .motion => |mot| {
                root.mMove(.fromFixed(
                    @intFromEnum(mot.surface_x),
                    @intFromEnum(mot.surface_y),
                    false,
                    .init(ui.hid.mods),
                ), root.box);
            },
            else => {},
        },
    }
}

pub const Keyboard = struct {
    pub const Event = struct {
        up: bool,
        key: union(enum) {
            char: u8,
            ctrl: Keymap.Control,
        },
        mods: KMod,
    };
};

pub const Pointer = struct {
    pub const Motion = struct {
        up: bool,
        x: i24,
        y: i24,
        mods: KMod,
        /// base 2 fractional. Divide by 0xff to get dec fraction
        fractional: struct {
            x: u8,
            y: u8,
        },

        pub fn fromFixed(x: i32, y: i32, up: bool, mods: KMod) Motion {
            return .{
                .up = up,
                .x = @as(i24, @intCast(x >> 8)),
                .y = @as(i24, @intCast(y >> 8)),
                .mods = mods,
                .fractional = .{
                    .x = @intCast(x & 0xff),
                    .y = @intCast(y & 0xff),
                },
            };
        }

        pub fn addOffset(m: Motion, x: i24, y: i24) Motion {
            return .{
                .up = m.up,
                .x = m.x + x,
                .y = m.y + y,
                .mods = m.mods,
                .fractional = m.fractional,
            };
        }

        pub fn format(m: Motion, _: []const u8, _: anytype, w: anytype) !void {
            return w.print("Motion: x: {d:5} y: {d:5}{s}{s}{s} ({d}.{d:02.2}|{d}.{d:02.2})", .{
                m.x, m.y,
                if (m.mods.ctrl) " ctrl" else "", if (m.mods.shift) " shift" else "", //
                if (m.mods.alt) " alt" else "", //
                m.x, @as(usize, m.fractional.x) * 100 / 265, //
                m.y, @as(usize, m.fractional.y) * 100 / 265,
            });
        }
    };

    pub const Click = struct {
        up: bool,
        button: Button,
        x: f32,
        y: f32,
        mods: KMod,
    };

    pub const Button = u8;
};

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
const KMod = Keymap.KMod;
const Buffer = @import("Buffer.zig");
