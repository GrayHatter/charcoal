vtable: VTable,
box: Box = undefined,
draw_needed: bool = true,
state: *anyopaque = undefined,
children: []Component,

const Component = @This();

pub fn init(comp: *Component, a: Allocator, box: Box, ptr: ?*anyopaque) InitError!void {
    if (comp.vtable.init) |initV| {
        try initV(comp, a, box, ptr);
    } else for (comp.children) |*child| try child.init(a, box, ptr);
}

pub fn raze(comp: *Component, a: Allocator) void {
    if (comp.vtable.raze) |razeV| {
        razeV(comp, a);
    } else for (comp.children) |*child| child.raze(a);
}

pub fn tick(comp: *Component, tik: usize, ptr: ?*anyopaque) void {
    if (comp.vtable.tick) |tickV| {
        tickV(comp, tik, ptr);
    } else for (comp.children) |*child| child.tick(tik, ptr);
}

pub fn background(comp: *Component, buffer: *Buffer, box: Box) void {
    if (comp.vtable.background) |bg| {
        bg(comp, buffer, box);
    } else for (comp.children) |*child| child.background(buffer, box);
}

pub fn draw(comp: *Component, buffer: *Buffer, box: Box) void {
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
            comp.draw_needed = child.draw_needed or comp.draw_needed;
            return true;
        }
        comp.draw_needed = child.draw_needed or comp.draw_needed;
    }

    return false;
}

pub fn mMove(comp: *Component, mmove: Pointer.Motion, box: Box) void {
    if (comp.vtable.mmove) |mmoveV| {
        mmoveV(comp, mmove, box);
    } else for (comp.children) |*child| {
        child.mMove(mmove, box);
        comp.draw_needed = child.draw_needed or comp.draw_needed;
    }
}

pub fn mClick(comp: *Component, clk: Pointer.Click) bool {
    if (comp.vtable.mclick) |clickV| {
        return clickV(comp, clk);
    } else for (comp.children) |*child| {
        if (child.mClick(clk)) {
            comp.draw_needed = child.draw_needed or comp.draw_needed;
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
    mclick: ?MClick,

    pub const empty: VTable = .{
        .init = null,
        .raze = null,
        .tick = null,
        .background = null,
        .draw = null,
        .keypress = null,
        .mmove = null,
        .mclick = null,
    };

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

pub const Init = *const fn (*Component, Allocator, Box, ?*anyopaque) InitError!void;
pub const Raze = *const fn (*Component, Allocator) void;
pub const Tick = *const fn (*Component, usize, ?*anyopaque) void;
pub const Background = *const fn (*Component, *Buffer, Box) void;
pub const Draw = *const fn (*Component, *Buffer, Box) void;
pub const KeyPress = *const fn (*Component, KeyEvent) bool;
pub const MMove = *const fn (*Component, Pointer.Motion, Box) void;
pub const MClick = *const fn (*Component, Pointer.Click) bool;

pub const InitError = error{
    OutOfMemory,
    UnableToInit,
};

const Pointer = Ui.Pointer;
const Motion = Pointer.Motion;
const KeyEvent = Ui.Keyboard.Event;

const Allocator = @import("std").mem.Allocator;
const Keymap = @import("../Keymap.zig");
const Buffer = @import("../Buffer.zig");
const Ui = @import("../Ui.zig");
const Box = Buffer.Box;
