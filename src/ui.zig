pub const Component = struct {
    vtable: VTable,
    box: Buffer.Box = undefined,
    damaged: bool = false,
    redraw_req: bool = false,
    state: *anyopaque = undefined,
    children: []Component,

    pub fn init(comp: *Component, a: Allocator, box: Buffer.Box) InitError!void {
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

    pub fn background(comp: *Component, buffer: *const Buffer, box: Buffer.Box) void {
        if (comp.vtable.background) |bg| {
            bg(comp, buffer, box);
        } else for (comp.children) |*child| child.background(buffer, box);
    }

    pub fn draw(comp: *Component, buffer: *const Buffer, box: Buffer.Box) void {
        if (comp.vtable.draw) |drawV| {
            drawV(comp, buffer, box);
        } else for (comp.children) |*child| {
            child.draw(buffer, box);
            child.redraw_req = false;
        }
        comp.redraw_req = false;
    }

    pub fn keyPress(comp: *Component, evt: KeyEvent) bool {
        if (comp.vtable.keypress) |kp| {
            comp.damaged = kp(comp, evt);
        } else for (comp.children) |*child| {
            if (child.keyPress(evt)) {
                comp.damaged = child.damaged or comp.damaged;
                return true;
            }
        }

        return false;
    }

    pub fn mMove(comp: *Component, mmove: Mouse.Movement, box: Buffer.Box) void {
        if (comp.vtable.mmove) |mmoveV| {
            mmoveV(comp, mmove, box);
        } else for (comp.children) |*child| {
            child.mMove(mmove, box);
            comp.damaged = child.damaged or comp.damaged;
        }
    }

    pub fn mClick(comp: *Component, mclick: Mouse.Click, box: Buffer.Box) bool {
        if (comp.vtable.mclick) |mclickV| {
            return mclickV(comp, mclick, box);
        } else for (comp.children) |*child| {
            if (child.mClick(mclick, box)) break;
        }

        return false;
    }

    pub fn painted(comp: *Component) void {
        comp.damaged = false;
        for (comp.children) |*child| child.painted();
    }
};

pub const VTable = struct {
    init: ?Init,
    raze: ?Raze,
    tick: ?Tick,
    background: ?Background,
    draw: ?Draw,
    keypress: ?KeyPress,
    mmove: ?MMove,
    mclick: ?MClick,

    pub fn auto(comptime uicomp: type) VTable {
        return .{
            .init = if (@hasDecl(uicomp, "init")) uicomp.init else null,
            .raze = if (@hasDecl(uicomp, "raze")) uicomp.raze else null,
            .tick = if (@hasDecl(uicomp, "tick")) uicomp.tick else null,
            .background = if (@hasDecl(uicomp, "background")) uicomp.background else null,
            .draw = if (@hasDecl(uicomp, "draw")) uicomp.draw else null,
            .keypress = if (@hasDecl(uicomp, "keyPress")) uicomp.keyPress else null,
            .mmove = if (@hasDecl(uicomp, "mMove")) uicomp.mMove else null,
            .mclick = if (@hasDecl(uicomp, "mClick")) uicomp.mClick else null,
        };
    }
};

pub const Init = *const fn (*Component, Allocator, Buffer.Box) InitError!void;
pub const Raze = *const fn (*Component, Allocator) void;
pub const Tick = *const fn (*Component, ?*anyopaque) void;
pub const Background = *const fn (*Component, *const Buffer, Buffer.Box) void;
pub const Draw = *const fn (*Component, *const Buffer, Buffer.Box) void;
pub const KeyPress = *const fn (*Component, KeyEvent) bool;
pub const MMove = *const fn (*Component, Mouse.Movement) void;
pub const MClick = *const fn (*Component, Mouse.Click) bool;

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

pub const Mouse = struct {
    pub const Movement = struct {
        up: bool,
        x: isize,
        y: isize,
        mods: Keymap.Modifiers,
    };
    pub const Click = struct {
        up: bool,
        button: Button,
        x: isize,
        y: isize,
        mods: Keymap.Modifiers,
    };
    pub const Button = u8;
};

const Allocator = @import("std").mem.Allocator;
const Keymap = @import("Keymap.zig");
const Buffer = @import("Buffer.zig");
