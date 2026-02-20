root: ?*Component = null,
keymap: Keymap = .{},
hid: struct {
    pointer_pos: Pointer.Position = .zero,
    mods: u32 = 0,
} = .{},
active_buffer: ?*Buffer = null,

const Ui = @This();

pub const Component = @import("ui/Component.zig");

pub const Event = union(enum) {
    focus: Focus,
    key: Wayland.Keyboard.Event,
    key_mods: Wayland.Keyboard.Event,
    pointer: Wayland.Pointer.Event,

    pub const Focus = struct {
        from: union(enum) {
            mouse: Wayland.Pointer.Event,
            keyboard: Wayland.Keyboard.Event,
        },
        focus: enum { enter, leave },
        serial: u32,
    };
    pub const Key = Keyboard.Event;
    pub const MMove = Pointer.Motion;
    pub const Click = Pointer.Click;
};

pub fn init(ui: *Ui, comp: *Component, alloc: Allocator, box: Box) Component.InitError!void {
    ui.root = comp;
    try ui.root.?.init(alloc, box);
}

pub fn raze(ui: *Ui, a: Allocator) void {
    if (ui.root) |root| {
        root.raze(a);
    }
    ui.root = null;
}

pub fn tick(ui: Ui, tik: usize) void {
    if (ui.root) |root| {
        root.tick(tik);
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

pub fn moveFrame(ui: *Ui, evt: Pointer.Click) void {
    const chr: *Charcoal = @fieldParentPtr("ui", ui);
    chr.wayland.toplevel.?.move(chr.wayland.seat.?, evt.serial);
}

pub fn event(ui: *Ui, evt: Event) void {
    const root = ui.root orelse {
        log.warn("UI not ready for event {}", .{evt});
        return;
    };
    switch (evt) {
        .key_mods, .key => |k| switch (k) {
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
                log.debug("modifers changed {}", .{k.modifiers});
            },
            else => {},
        },
        .pointer => |point| switch (point) {
            .button => |btn| {
                _ = root.mClick(.{
                    .pos = ui.hid.pointer_pos,
                    .button = @enumFromInt(btn.button),
                    .up = btn.state == .released,
                    .serial = btn.serial,
                    .mods = .init(ui.hid.mods),
                });
            },
            .motion => |mot| {
                ui.hid.pointer_pos = .fromFixed(
                    @intFromEnum(mot.surface_x),
                    @intFromEnum(mot.surface_y),
                );
                root.mMove(.fromFixed(
                    @intFromEnum(mot.surface_x),
                    @intFromEnum(mot.surface_y),
                    false,
                    .init(ui.hid.mods),
                ), root.box);
            },
            else => {},
        },
        .focus => |foc| {
            const chr: *Charcoal = @fieldParentPtr("ui", ui);
            if (chr.wayland.hid.cursor_shape) |cursor_shape| {
                cursor_shape.setShape(foc.serial, .default);
            }

            switch (foc.from) {
                .keyboard => {
                    const mods: KMod = .init(ui.hid.mods);
                    _ = root.keyPress(.{
                        .up = true,
                        .key = .{ .focus = foc.focus == .enter },
                        .mods = mods,
                    });
                    //root.focused(foc);
                },
                .mouse => |mot| {
                    const x, const y = switch (mot) {
                        .enter => |e| .{
                            @intFromEnum(e.surface_x),
                            @intFromEnum(e.surface_y),
                        },
                        .leave => .{ 0, 0 },
                        else => unreachable,
                    };
                    var m: Pointer.Motion = .fromFixed(
                        x,
                        y,
                        false,
                        .init(ui.hid.mods),
                    );
                    if (foc.focus == .leave) {
                        m.focus = .leave;
                    }
                    _ = root.mMove(m, root.box);
                },
            }
        },
    }
}

pub const Keyboard = struct {
    pub const Event = struct {
        up: bool,
        key: union(enum) {
            char: u8,
            ctrl: Keymap.Control,
            focus: bool,
        },
        mods: KMod,
    };
};

pub const Pointer = struct {
    pub const Position = struct {
        x: i24,
        y: i24,
        /// base 2 fractional. Divide by 0xff to get dec fraction
        fractional: struct {
            x: u8,
            y: u8,
        },

        pub const zero: Position = .{ .x = 0, .y = 0, .fractional = .{ .x = 0, .y = 0 } };

        pub fn fromFixed(x: i32, y: i32) Position {
            return .{
                .x = @as(i24, @intCast(x >> 8)),
                .y = @as(i24, @intCast(y >> 8)),
                .fractional = .{
                    .x = @intCast(x & 0xff),
                    .y = @intCast(y & 0xff),
                },
            };
        }

        pub fn addOffset(p: Position, x: i24, y: i24) Position {
            return .{
                .x = p.x + x,
                .y = p.y + y,
                .fractional = p.fractional,
            };
        }

        pub fn withinBox(pos: Position, box: Buffer.Box) ?Position {
            if (pos.x >= box.x and pos.x <= box.x2() and pos.y >= box.y and pos.y <= box.y2()) {
                const x: i24 = @intCast(box.x);
                const y: i24 = @intCast(box.y);
                return pos.addOffset(-x, -y);
            }
            return null;
        }
    };

    pub const Motion = struct {
        pos: Position,
        up: bool,
        focus: enum { enter, leave } = .enter,
        mods: KMod,

        pub fn fromFixed(x: i32, y: i32, up: bool, mods: KMod) Motion {
            return .{
                .pos = .fromFixed(x, y),
                .up = up,
                .mods = mods,
            };
        }

        pub fn withinBox(m: Motion, box: Buffer.Box) ?Motion {
            if (m.pos.withinBox(box)) |pos| {
                return .{
                    .pos = pos,
                    .up = m.up,
                    .focus = m.focus,
                    .mods = m.mods,
                };
            }
            return null;
        }

        pub fn format(m: Motion, _: []const u8, _: anytype, w: anytype) !void {
            return w.print("Motion: x: {d:5} y: {d:5}{s}{s}{s} ({d}.{d:02.2}|{d}.{d:02.2})", .{
                m.pos.x, m.pos.y,
                if (m.mods.ctrl) " ctrl" else "", if (m.mods.shift) " shift" else "", //
                if (m.mods.alt) " alt" else "", //
                m.pos.x, @as(usize, m.pos.fractional.x) * 100 / 265, //
                m.pos.y, @as(usize, m.pos.fractional.y) * 100 / 265,
            });
        }
    };

    pub const Click = struct {
        pos: Position,
        up: bool,
        button: Button,
        serial: u32,
        mods: KMod,

        pub fn withinBox(c: Click, box: Buffer.Box) ?Click {
            if (c.pos.withinBox(box)) |pos| {
                return .{
                    .pos = pos,
                    .up = c.up,
                    .button = c.button,
                    .serial = c.serial,
                    .mods = c.mods,
                };
            }
            return null;
        }

        pub fn format(m: Click, _: []const u8, _: anytype, w: anytype) !void {
            return w.print("*Click: x: {d:5} y: {d:5}{s}{s}{s} ({d}.{d:02.2}|{d}.{d:02.2})", .{
                m.pos.x, m.pos.y,
                if (m.mods.ctrl) " ctrl" else "", if (m.mods.shift) " shift" else "", //
                if (m.mods.alt) " alt" else "", //
                m.pos.x, @as(usize, m.pos.fractional.x) * 100 / 255, //
                m.pos.y, @as(usize, m.pos.fractional.y) * 100 / 255,
            });
        }
    };

    pub const Button = enum(u32) {
        // linux/include/uapi/linux/input-event-codes.h
        // ***sigh***
        BTN_0 = 0x100,
        BTN_1 = 0x101,
        BTN_2 = 0x102,
        BTN_3 = 0x103,
        BTN_4 = 0x104,
        BTN_5 = 0x105,
        BTN_6 = 0x106,
        BTN_7 = 0x107,
        BTN_8 = 0x108,
        BTN_9 = 0x109,

        left = 0x110,
        right = 0x111,
        middle = 0x112,
        side = 0x113,
        extra = 0x114,
        forward = 0x115,
        back = 0x116,
        task = 0x117,

        joystick = 0x120,
        thumb = 0x121,
        thumb2 = 0x122,
        top = 0x123,
        top2 = 0x124,
        pinkie = 0x125,
        base = 0x126,
        base2 = 0x127,
        base3 = 0x128,
        base4 = 0x129,
        base5 = 0x12a,
        base6 = 0x12b,
        dead = 0x12f,

        south = 0x130,
        east = 0x131,
        center = 0x132,
        north = 0x133,
        west = 0x134,
        z = 0x135,
        tl = 0x136,
        tr = 0x137,
        tl2 = 0x138,
        tr2 = 0x139,
        select = 0x13a,
        start = 0x13b,
        mode = 0x13c,
        thumbl = 0x13d,
        thumbr = 0x13e,

        _,

        pub const trigger: Button = .joystick;
        pub const misc: Button = .BTN_0;
        pub const gamepad: Button = .south;
        pub const BTN_A: Button = .south;
        pub const BTN_B: Button = .east;
        pub const BTN_X: Button = .north;
        pub const BTN_Y: Button = .west;
    };
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
const Box = Buffer.Box;
