vtable: VTable,
box: Box = undefined,
damaged: bool = false,
redraw_req: bool = false,
state: *anyopaque = undefined,
children: []Component,

const Component = @This();

pub fn init(comp: *Component, a: Allocator, box: Box) InitError!void {
    if (comp.vtable.init) |initV| {
        try initV(comp, a, box);
    } else for (comp.children) |*child| try child.init(a, box);
}

pub fn raze(comp: *Component, a: Allocator) void {
    if (comp.vtable.raze) |razeV| {
        razeV(comp, a);
    } else for (comp.children) |*child| child.raze(a);
}

pub fn tick(comp: *Component, ptr: ?*anyopaque) void {
    if (comp.vtable.tick) |tickV| {
        tickV(comp, ptr);
    } else for (comp.children) |*child| child.tick(ptr);
}

pub fn background(comp: *Component, buffer: *const Buffer, box: Box) void {
    if (comp.vtable.background) |bg| {
        bg(comp, buffer, box);
    } else for (comp.children) |*child| child.background(buffer, box);
}

pub fn draw(comp: *Component, buffer: *const Buffer, box: Box) void {
    // pre-set damaged = false so called fn can reset it if required
    comp.redraw_req = false;
    comp.damaged = false;
    if (comp.vtable.draw) |drawV| {
        drawV(comp, buffer, box);
    } else for (comp.children) |*child| {
        child.draw(buffer, box);
    }
}

pub fn keyPress(comp: *Component, evt: KeyEvent) bool {
    if (comp.vtable.keypress) |kp| {
        return kp(comp, evt);
    } else for (comp.children) |*child| {
        if (child.keyPress(evt)) {
            comp.damaged = child.damaged or comp.damaged;
            return true;
        }
    }

    return false;
}

pub fn mMove(comp: *Component, mmove: Pointer.Motion, box: Box) void {
    if (comp.vtable.mmove) |mmoveV| {
        mmoveV(comp, mmove, box);
    } else for (comp.children) |*child| {
        child.mMove(mmove, box);
        comp.damaged = child.damaged or comp.damaged;
    }
}

pub fn click(comp: *Component, clk: Pointer.Click, box: Box) bool {
    if (comp.vtable.click) |clickV| {
        return clickV(comp, clk, box);
    } else for (comp.children) |*child| {
        if (child.click(clk, box)) {
            comp.damaged = child.damaged or comp.damaged;
            return true;
        }
    }

    return false;
}

pub const VTable = struct {
    init: ?Init,
    raze: ?Raze,
    tick: ?Tick,
    background: ?Background,
    draw: ?Draw,
    keypress: ?KeyPress,
    mmove: ?MMove,
    click: ?Click,

    pub fn auto(comptime uicomp: type) VTable {
        return .{
            .init = if (@hasDecl(uicomp, "init")) uicomp.init else null,
            .raze = if (@hasDecl(uicomp, "raze")) uicomp.raze else null,
            .tick = if (@hasDecl(uicomp, "tick")) uicomp.tick else null,
            .background = if (@hasDecl(uicomp, "background")) uicomp.background else null,
            .draw = if (@hasDecl(uicomp, "draw")) uicomp.draw else null,
            .keypress = if (@hasDecl(uicomp, "keyPress")) uicomp.keyPress else null,
            .mmove = if (@hasDecl(uicomp, "mMove")) uicomp.mMove else null,
            .click = if (@hasDecl(uicomp, "click")) uicomp.mClick else null,
        };
    }
};

pub const Init = *const fn (*Component, Allocator, Box) InitError!void;
pub const Raze = *const fn (*Component, Allocator) void;
pub const Tick = *const fn (*Component, ?*anyopaque) void;
pub const Background = *const fn (*Component, *const Buffer, Box) void;
pub const Draw = *const fn (*Component, *const Buffer, Box) void;
pub const KeyPress = *const fn (*Component, KeyEvent) bool;
pub const MMove = *const fn (*Component, Pointer.Motion, Box) void;
pub const Click = *const fn (*Component, Pointer.Click) bool;

pub const InitError = error{
    OutOfMemory,
    UnableToInit,
};

pub const KeyEvent = struct {
    up: bool,
    key: union(enum) {
        char: u8,
        ctrl: Keymap.Control,
    },
    mods: Keymap.Modifiers,
};

pub const Pointer = struct {
    pub const Motion = struct {
        up: bool,
        x: i24,
        y: i24,
        mods: Keymap.Modifiers,
        fractional: struct {
            x: u8,
            y: u8,
        },

        pub fn fromFixed(x: i32, y: i32, up: bool, mods: Keymap.Modifiers) Motion {
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
        mods: Keymap.Modifiers,
    };
    pub const Button = u8;
};

const Allocator = @import("std").mem.Allocator;
const Keymap = @import("../Keymap.zig");
const Buffer = @import("../Buffer.zig");
const Box = Buffer.Box;
