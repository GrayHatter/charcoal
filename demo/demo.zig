const Char = @import("charcoal");
const Buffer = Char.Buffer;
const Ui = Char.Ui;
const Box = Char.Box;

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();

    // Step one, create Charcoal
    var char: Char = try .init();
    defer char.raze();
    // Connect to the wayland compositor
    try char.connect();

    // The default window size
    const box: Buffer.Box = .wh(1000, 1000);

    // We call char.wayland.createBuffer instead of `Charcoal.createBuffer` because we're creating
    // two buffers, one for each page.
    var default_buffer = try char.wayland.createBuffer(box, "buffer1");
    defer default_buffer.raze();
    var color_buffer = try char.wayland.createBuffer(box, "buffer2");
    defer color_buffer.raze();

    // The buffers are ready, draw the background colors
    try drawColorsPage1(box.w, 0, &default_buffer);
    try drawColorsPage2(box.w, 0, &color_buffer);

    // The font file is embedded directly
    const ttf: Ttf = try .load(@alignCast(@embedFile("font.ttf")));
    // We use a global glyph cache so both pages can share the rendered and cached glyphs
    glyph_cache = .init(&ttf, 0.01866);
    defer glyph_cache.raze(alloc);
    const small_font = false;
    if (small_font) {
        glyph_cache.scale_vert = 0.0195;
        glyph_cache.scale_horz = 0.025;
    }
    // Fonts are ready, so draw the extra page features.
    try drawPage1(alloc, &default_buffer);
    try drawPage2(alloc, &color_buffer);

    // Resize also specifies the max surface size, and then commits the surface, and sends a
    // round to the compositor. If you don't want to specify a max size, you'll have to commit
    // the surface directly.
    try char.wayland.resize(box);
    // Because we calling `createBuffer` from `char.wayland` instead directly from `char` it
    // doesn't get automagically attached; and we need tell the wayland compositor about it
    // Directly **after** calling resize. Different orders will hang the protocol...
    // No, I don't get it either.
    try char.wayland.attach(&default_buffer);

    // the reusable widget like interface is Charcoal.Ui.Component, your widget or complication
    // can embed a Ui component, and it will get events, ticks, and primitive redrawing suggestions
    var root: Root = .{
        .alloc = alloc,
        // The Component VTable provides an `auto` helper if you have all functions defined
        // (or set to null as below)
        .comp = .{ .vtable = .auto(Root) },
        .extra = .{ .buffer = &default_buffer, .colors = &color_buffer, .char = &char },
    };

    // Calling init on char.ui is optional, if you specify the root component directly at
    // `charcoal.ui.root`, charcoal will still deliver ticks and events, but wont send redraw
    // requests. Not from itself, and not from the compositor. Depending on how you drawing
    // your surface, this might be desirable. Here, we want draw events so we call init.
    try char.ui.init(&root.comp, &default_buffer, box, alloc);

    // We finally done. Charcoal.run will try to redraw as fast as possible, but it's unlikely
    // your compositor and/or monitor can keep up with the 300 FPS I've seen on some windows.
    try char.runRateLimit(.fps(30), init.io);
}

var glyph_cache: Ttf.GlyphCache = undefined;

const Root = struct {
    alloc: Allocator,
    comp: Ui.Component,
    on_color: bool = true,
    color: ARGB = .black,
    extra: Extra = undefined,

    pub const Extra = struct {
        char: *Char,
        colors: *Buffer,
        buffer: *Buffer,
    };

    pub fn init(_: *Ui.Component, _: Buffer.Box, _: ?Allocator) !void {}

    pub const raze = null;
    pub const background = null;
    pub const keyPress = null;
    pub const mMove = null;
    pub const mClick = null;

    pub fn draw(comp: *Ui.Component, buffer: *Buffer, _: Buffer.Box) void {
        const root: *Root = @fieldParentPtr("comp", comp);
        buffer.drawCircleFill(Buffer.ARGB, .xywh(300, 500, 80, 80), root.color);
    }

    pub fn tick(comp: *Ui.Component, iter: usize) void {
        // Swap the active page every 100-ish ticks and then recalculate
        // the color the color of the circle. While this calculation is
        // extremely cheap, It's often better to all processing inside
        // the tick function, and only draw
        const root: *Root = @fieldParentPtr("comp", comp);
        if (iter % 180 == 0) {
            if (iter / 180 & 1 > 0) {
                std.debug.print("swap on\n", .{});
                root.on_color = true;
                root.extra.colors.damageAll();
                root.extra.char.ui.active_buffer = root.extra.colors;
            } else {
                std.debug.print("swap off\n", .{});
                root.on_color = false;
                root.extra.buffer.damageAll();
                root.extra.char.ui.active_buffer = root.extra.buffer;
            }
        }
        const low: u32 = @as(u8, @truncate(iter));
        const mid: u32 = @as(u16, @truncate(iter)) >> 8;
        root.color = .rgb(mid * 4, low, low * 4);
    }
};

fn drawText(alloc: Allocator, buffer: *Buffer, text: []const u8) !void {
    var next_x: i32 = 0;
    for (text) |g| {
        const glyph = try glyph_cache.get(alloc, g);
        buffer.drawFont(
            ARGB,
            .black,
            .xywh(400 + glyph.off_x + next_x, 100 + glyph.off_y, glyph.width, glyph.height),
            glyph.pixels,
        );
        next_x += glyph.width + glyph.off_x;
    }
}

fn drawPage1(alloc: Allocator, buffer: *Buffer) !void {
    try drawTextLowercase(alloc, .xy(20, 30), buffer);
    try drawTextUppercase(alloc, .xy(20, 55), buffer);

    // Overlapping boxes
    buffer.drawRectangleFill(Buffer.ARGB, .xywh(130, 110, 200, 50), .blue);
    buffer.drawRectangleFill(Buffer.ARGB, .xywh(30, 100, 200, 50), .red);
    // Drawing order matters. The blue box should merge with the red box, but not the background
    // Draw the blue box without mixing, draw the red box, finally draw the blue box with an
    // alpha to mix it with the red box.
    buffer.drawRectangleFillMix(Buffer.ARGB, .xywh(130, 110, 200, 50), .alpha(.blue, 0xc8));
    buffer.drawRectangleFill(Buffer.ARGB, .xywh(400, 100, 100, 50), @enumFromInt(0xffff00ff));

    buffer.drawRectangleFill(Buffer.ARGB, .xywh(130, 330, 200, 30), .blue);
    buffer.drawRectangleFill(Buffer.ARGB, .xywh(30, 300, 200, 50), .red);
    // The height of the top box is only 30, and the alpha is lower, so part of this box will
    // mix with the background, and will include more red
    buffer.drawRectangleFillMix(Buffer.ARGB, .xywh(130, 310, 200, 50), .alpha(.blue, 0x88));
    buffer.drawRectangleFill(Buffer.ARGB, .xywh(400, 400, 100, 50), .hex(0xffff00ff));

    // The color changing circle is dynamic, so it is drawn elsewhere.
    // every draw call will also `damage` the buffer, so static pixels don't need to be
    // re-rendered by the compositor.

    buffer.drawTriangle(ARGB, .north, .xywh(825, 625, 50, 50), .blue);
    buffer.drawTriangle(ARGB, .west, .xywh(775, 675, 50, 50), .blue);
    buffer.drawTriangle(ARGB, .east, .xywh(875, 675, 50, 50), .blue);
    buffer.drawTriangle(ARGB, .south, .xywh(825, 725, 50, 50), .blue);

    buffer.drawTriangle(ARGB, .north_west, .xywh(750, 600, 100, 100), .charcoal);
    buffer.drawTriangle(ARGB, .north_east, .xywh(850, 600, 100, 100), .charcoal);
    buffer.drawTriangle(ARGB, .south_east, .xywh(850, 700, 100, 100), .charcoal);
    buffer.drawTriangle(ARGB, .south_west, .xywh(750, 700, 100, 100), .charcoal);

    try drawTextBottom(alloc, buffer);
}

fn drawTextLowercase(alloc: Allocator, box: Box, buffer: *Buffer) !void {
    const text = "abcdefghijklmnopqrstuvwxyz";
    var next_x: i32 = 0;
    for (text) |g| {
        const glyph = try glyph_cache.get(alloc, g);
        buffer.drawFont(ARGB, .black, box.add(
            .xywh(glyph.off_x + next_x, glyph.off_y, glyph.width, glyph.height),
        ), glyph.pixels);
        next_x += glyph.width + glyph.off_x;
    }
}

fn drawTextUppercase(alloc: Allocator, box: Box, buffer: *Buffer) !void {
    const text = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    var next_x: i32 = 0;
    for (text) |g| {
        const glyph = try glyph_cache.get(alloc, g);
        buffer.drawFont(ARGB, .black, box.add(
            .xywh(glyph.off_x + next_x, glyph.off_y, glyph.width, glyph.height),
        ), glyph.pixels);
        next_x += glyph.width + glyph.off_x;
    }
}

fn drawTextBottom(alloc: Allocator, buffer: *Buffer) !void {
    var next_x: i32 = 0;
    var per_char: f16 = 0xff;
    const per_char_delta: f16 = 255.0 / (0x7f.0 - 0x21.0);
    const box: Box = .xy(10, 825);
    for (0x21..0x7f) |g| {
        const glyph = try glyph_cache.get(alloc, @intCast(g));
        buffer.drawFont(ARGB, .black, box.add(
            .xywh(glyph.off_x + next_x, 25 + glyph.off_y, glyph.width, glyph.height),
        ), glyph.pixels);
        buffer.drawFont(ARGB, .dark_gray, box.add(
            .xywh(glyph.off_x + next_x, 50 + glyph.off_y, glyph.width, glyph.height),
        ), glyph.pixels);
        buffer.drawFont(ARGB, .gray, box.add(
            .xywh(glyph.off_x + next_x, 75 + glyph.off_y, glyph.width, glyph.height),
        ), glyph.pixels);
        buffer.drawFont(ARGB, .light_gray, box.add(
            .xywh(glyph.off_x + next_x, 100 + glyph.off_y, glyph.width, glyph.height),
        ), glyph.pixels);
        buffer.drawFont(ARGB, .white, box.add(
            .xywh(glyph.off_x + next_x, 125 + glyph.off_y, glyph.width, glyph.height),
        ), glyph.pixels);

        buffer.drawFont(ARGB, .rgb(
            @intFromFloat(@round(per_char)),
            @intFromFloat(@round(per_char)),
            @intFromFloat(@round(per_char)),
        ), box.add(
            .xywh(glyph.off_x + next_x, 150 + glyph.off_y, glyph.width, glyph.height),
        ), glyph.pixels);
        per_char -= per_char_delta;
        next_x += glyph.width + glyph.off_x;
    }
}

fn drawPage2(_: Allocator, colors: *Buffer) !void {
    // Colors is the 2nd screen

    // Top left
    colors.drawRectangleFill(Buffer.ARGB, .xywh(90, 75, 50, 50), .purple);
    colors.drawRectangle(Buffer.ARGB, .xywh(50, 50, 50, 50), .green);

    colors.drawCircleFill(Buffer.ARGB, .xywh(300, 200, 50, 50), .purple);
    colors.drawCircle(Buffer.ARGB, .xywh(200, 200, 50, 50), .purple);

    colors.drawCircle(Buffer.ARGB, .xywh(800, 100, 50, 50), .purple);
    colors.drawCircleFill(Buffer.ARGB, .xywh(700, 100, 50, 50), .purple);

    colors.drawPoint(Buffer.ARGB, .xy(300, 200), .black);

    colors.drawCircleCentered(Buffer.ARGB, .radius(700, 100, 11), .cyan);
    colors.drawPoint(Buffer.ARGB, .xy(700, 100), .black);

    colors.drawRectangleRounded(Buffer.ARGB, .xywh(10, 300, 200, 50), 10, .red);
    colors.drawRectangleRoundedFill(Buffer.ARGB, .xywh(10, 400, 200, 20), 3, .parchment);
    colors.drawRectangleRounded(Buffer.ARGB, .xywh(10, 400, 200, 20), 3, .bittersweet_shimmer);

    colors.drawRectangleRoundedFill(Buffer.ARGB, .xywh(40, 600, 300, 40), 10, .parchment);
    colors.drawRectangleRounded(Buffer.ARGB, .xywh(40, 600, 300, 40), 10, .bittersweet_shimmer);
    colors.drawRectangleRounded(Buffer.ARGB, .xywh(41, 601, 298, 38), 9, .bittersweet_shimmer);
}

fn drawColorsPage1(size: usize, rotate: usize, buffer: *Buffer) !void {
    for (0..size) |x| for (0..size) |y| {
        const r_x: usize = x * 0xff / size;
        const r_y: usize = y * 0xff / size;
        const r: u8 = @intCast(r_x & 0xfe);
        const g: u8 = @intCast(r_y & 0xfe);
        const b: u8 = 0xff - g;
        const c: ARGB = .rgb(r, g, b);
        buffer.drawPoint(ARGB, .xy(x, (y + rotate) % size), c);
    };
}

fn drawColorsPage2(size: usize, rotate: usize, colors: *Buffer) !void {
    for (0..size) |x| for (0..size) |y| {
        const r_x: usize = x * 0xff / size;
        const r_y: usize = y * 0xff / size;
        const r: u8 = @intCast(r_x & 0xfe);
        const g: u8 = @intCast(r_y & 0xfe);
        const b: u8 = @intCast(0xff - r);
        const c: ARGB = .rgb(r, g, b);
        colors.drawPoint(ARGB, .xy((x + rotate) % size, y), c);
    };
}

const Ttf = Char.TrueType;
const ARGB = Char.Buffer.ARGB;
const std = @import("std");
const Allocator = std.mem.Allocator;
