vtable: VTable,
box: Box = undefined,
draw_needed: bool = true,
children: []Component = &.{},

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

pub fn tick(comp: *Component, tik: usize) void {
    if (comp.vtable.tick) |tickV| {
        tickV(comp, tik);
    } else for (comp.children) |*child| child.tick(tik);
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

pub fn keyPress(comp: *Component, evt: Keyboard.Event) bool {
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

    pub fn auto(uicomp: type) VTable {
        return .{
            .init = uicomp.init,
            .raze = uicomp.raze,
            .tick = uicomp.tick,
            .background = uicomp.background,
            .draw = uicomp.draw,
            .keypress = uicomp.keyPress,
            .mmove = uicomp.mMove,
            .mclick = uicomp.mClick,
        };
    }
};

pub const Init = *const fn (*Component, Allocator, Box) InitError!void;
pub const Raze = *const fn (*Component, Allocator) void;
pub const Tick = *const fn (*Component, usize) void;
pub const Background = *const fn (*Component, *Buffer, Box) void;
pub const Draw = *const fn (*Component, *Buffer, Box) void;
pub const KeyPress = *const fn (*Component, Keyboard.Event) bool;
pub const MMove = *const fn (*Component, Pointer.Motion, Box) void;
pub const MClick = *const fn (*Component, Pointer.Click) bool;

pub const InitError = error{
    OutOfMemory,
    UnableToInit,
};

const Pointer = Ui.Pointer;
const Keyboard = Ui.Keyboard;
const Motion = Pointer.Motion;

const Allocator = @import("std").mem.Allocator;
const Keymap = @import("../Keymap.zig");
const Buffer = @import("../Buffer.zig");
const Ui = @import("../Ui.zig");
const Box = Buffer.Box;
