raw: []u32,
pool: *wl.ShmPool,
buffer: *wl.Buffer,
width: u32,
height: u32,
stride: u32,

capacity: struct {
    width: u32,
    height: u32,
},

damage: Box = .zero,

const Buffer = @This();

pub const formats = @import("Buffer/formats.zig");
pub const ARGB = formats.ARGB;

pub const Box = struct {
    x: usize,
    y: usize,
    w: usize,
    h: usize,

    pub const zero: Box = .{ .x = 0, .y = 0, .w = 0, .h = 0 };

    pub const Delta = struct {
        x: isize,
        y: isize,
        w: isize,
        h: isize,
        pub const zero: Delta = .{ .x = 0, .y = 0, .w = 0, .h = 0 };

        pub fn vector(s: isize) Delta {
            return .{ .x = s, .y = s, .w = s * -2, .h = s * -2 };
        }

        pub fn xy(x: isize, y: isize) Delta {
            return .{ .x = x, .y = y, .w = 0, .h = 0 };
        }

        pub fn wh(w: isize, h: isize) Delta {
            return .{ .x = 0, .y = 0, .w = w, .h = h };
        }

        pub fn xywh(x: isize, y: isize, w: isize, h: isize) Delta {
            return .{ .x = x, .y = y, .w = w, .h = h };
        }
    };

    pub const WH = struct {
        w: isize,
        h: isize,

        pub fn wh(w: usize, h: usize) Box {
            return .{ .w = w, .h = h };
        }

        pub fn box(wh_: WH) Box {
            return .wh(wh_.w, wh_.h);
        }
    };

    pub const XY = struct {
        x: isize,
        y: isize,

        pub fn xy(x: isize, y: isize) XY {
            return .{ .x = x, .y = y };
        }

        pub fn box(xy_: XY) Box {
            return .xy(xy_.x, xy_.y);
        }
    };

    /// Box.x + Box.w
    pub inline fn x2(b: Box) usize {
        return b.x + b.w;
    }

    /// Box.y + Box.w
    pub inline fn y2(b: Box) usize {
        return b.y + b.h;
    }

    pub fn xy(x: usize, y: usize) Box {
        return .{ .x = x, .y = y, .w = 0, .h = 0 };
    }

    pub fn xywh(x: usize, y: usize, w: usize, h: usize) Box {
        return .{ .x = x, .y = y, .w = w, .h = h };
    }

    pub fn wh(w: usize, h: usize) Box {
        return .{ .w = w, .h = h, .x = 0, .y = 0 };
    }

    pub fn radius(x: usize, y: usize, r: usize) Box {
        return .{ .x = x, .y = y, .w = r, .h = r };
    }

    pub fn merge(src: *Box, delta: Delta) void {
        src.x = @max(0, @as(isize, @intCast(src.x)) + delta.x);
        src.y = @max(0, @as(isize, @intCast(src.y)) + delta.y);
        src.w = @max(0, @as(isize, @intCast(src.w)) + delta.w);
        src.h = @max(0, @as(isize, @intCast(src.h)) + delta.h);
    }

    pub fn add(src: Box, d: Delta) Box {
        var box = src;
        box.merge(d);
        return box;
    }

    /// unstable api
    pub fn within(box: Box, pos: Box) bool {
        if (pos.x < box.x or pos.y < box.y) return false;
        if (pos.x > box.w or pos.y > box.w) return false;
        if (pos.w > 0 and pos.x2() > box.x2()) return false;
        if (pos.y > 0 and pos.y2() > box.y2()) return false;
        return true;
    }
};

pub const Direction = enum {
    north,
    north_east,
    east,
    south_east,
    south,
    south_west,
    west,
    north_west,
};

pub fn init(shm: *wl.Shm, box: Box, name: []const u8) !Buffer {
    return try initCapacity(shm, box, box, name);
}

pub fn initCapacity(shm: *wl.Shm, active: Box, extra: Box, name: []const u8) !Buffer {
    const width: u31 = @intCast(extra.w);
    const stride: u31 = width * 4;
    const height: u31 = @intCast(extra.h);
    const size: u31 = stride * height;

    const active_width: u31 = @intCast(active.w);
    const active_height: u31 = @intCast(active.h);

    const fd = try posix.memfd_create(name, 0);
    try posix.ftruncate(fd, size);
    const prot = posix.PROT.READ | posix.PROT.WRITE;
    const raw = try posix.mmap(null, size, prot, .{ .TYPE = .SHARED }, fd, 0);

    const pool = try shm.createPool(fd, size);
    const buffer = try pool.createBuffer(0, active_width, active_height, stride, .argb8888);
    return .{
        .buffer = buffer,
        .raw = @ptrCast(raw),
        .width = active_width,
        .height = active_height,
        .capacity = .{
            .width = width,
            .height = height,
        },
        .stride = stride / 4,
        .pool = pool,
    };
}

pub fn raze(b: Buffer) void {
    b.buffer.destroy();
    b.pool.destroy();
    posix.munmap(@alignCast(@ptrCast(b.raw)));
}

pub fn resize(b: *Buffer, new: Box) !void {
    assert(new.x == 0);
    assert(new.y == 0);
    // TODO there's no reason we can't support ratio changes as well
    if (new.w > b.capacity.width or new.h > b.capacity.height) return error.OutOfRange;
    const old = b.buffer;
    b.buffer = try b.pool.createBuffer(0, @intCast(new.w), @intCast(new.h), @intCast(b.stride * 4), .argb8888);
    old.destroy();
    b.width = @intCast(new.w);
    b.height = @intCast(new.h);
}

pub fn addDamage(b: *Buffer, box: Box) void {
    b.damage = .{
        .x = @min(b.damage.x, box.x),
        .y = @min(b.damage.y, box.y),
        .w = @max(b.damage.w, box.x2()),
        .h = @max(b.damage.h, box.y2()),
    };
}

pub fn getDamage(b: *Buffer) ?Box {
    if (b.damage.x == 0 and b.damage.y == 0 and b.damage.w == 0 and b.damage.h == 0) return null;
    defer b.damage = .zero;
    return b.damage;
}

fn rowSlice(b: Buffer, y: usize) []u32 {
    return b.raw[b.stride * y ..][0..b.width];
}

pub fn draw(b: Buffer, box: Box, src: []const u32) void {
    for (0..box.h, box.y..box.y + box.h) |sy, dy| {
        @memcpy(
            b.rowSlice(dy)[box.x..][0..box.w],
            src[sy * box.w ..][0..box.w],
        );
    }
}

/// the src_box param specifies the xy offset to start the copies from, and the
/// wh is the size of the src buffer
pub fn copyFromTile(b: Buffer, T: type, box: Box, src: []const T, src_box: Box) void {
    assert(@sizeOf(T) == @sizeOf(u32));
    assert(src.len >= src_box.w * src_box.h);
    const repeat_x = box.w / src_box.w;
    const remain_x = box.w % src_box.w;

    for (0..box.h, box.y..box.y2()) |sy, dy| {
        const dst_row = b.rowSlice(dy)[box.x..][0..box.w];
        const src_row = src[(sy % src_box.h) + src_box.y .. src_box.w];
        for (0..repeat_x) |rx| {
            @memcpy(
                dst_row[src_box.w * rx .. src_box.w * (rx + 1)],
                @as([]const u32, @ptrCast(src_row[(src_box.x % src_box.w)..][0..src_box.w])),
            );
        }
        if (remain_x > 0) {
            @memcpy(
                dst_row[src_box.w * repeat_x ..][0..remain_x],
                @as([]const u32, @ptrCast(src_row[(src_box.x % src_box.w)..][0..remain_x])),
            );
        }
    }
}

/// the src_box param specifies the xy offset to start the copies from, and the
/// wh is the size of the src buffer
///
/// if the destination is larger than the source, use `copyFromTile` instead.
pub fn copyFrom(b: Buffer, T: type, box: Box, src: []const T, src_box: Box) void {
    assert(@sizeOf(T) == @sizeOf(u32));
    assert(src_box.w >= box.w);
    assert(src_box.h >= box.h);

    for (0..box.h, box.y..box.y + box.h) |sy, dy| {
        const src_row = src[sy + src_box.y .. src_box.w];
        @memcpy(
            b.rowSlice(dy)[box.x..][0..box.w],
            @as([]const u32, @ptrCast(src_row[src_box.x..][0..box.w])),
        );
    }
}

pub fn copy(b: Buffer, T: type, box: Box, src: []const T) void {
    for (0..box.h, box.y..box.y + box.h) |sy, dy| {
        @memcpy(
            b.rowSlice(dy)[box.x..][0..box.w],
            @as([]const u32, @ptrCast(src[sy * box.w ..][0..box.w])),
        );
    }
}

pub fn drawLine(b: *Buffer, T: type, box: Box, color: T) void {
    assert(box.h <= 1);
    const row = b.rowSlice(box.y);
    @memset(row[box.x..box.x2()], @intFromEnum(color));
}

pub fn drawLineV(b: *Buffer, T: type, box: Box, color: T) void {
    assert(box.w <= 1);
    for (box.y..box.y2()) |y| {
        b.rowSlice(y)[box.x] = @intFromEnum(color);
    }
}

pub fn drawEmboss(b: *Buffer, T: type, box: Box, direction: Direction, high: T, low: T) void {
    switch (direction) {
        .north, .north_west => {
            b.drawLine(T, .xywh(box.x, box.y, box.w, 1), low);
            b.drawLineV(T, .xywh(box.x, box.y, 1, box.h), low);
            b.drawLine(T, .xywh(box.x + 1, box.y2(), box.w, 1), high);
            b.drawLineV(T, .xywh(box.x2(), box.y + 1, 1, box.h), high);
        },
        .south, .south_east => {
            b.drawLine(T, .xywh(box.x, box.y, box.w, 1), high);
            b.drawLineV(T, .xywh(box.x, box.y, 1, box.h), high);
            b.drawLine(T, .xywh(box.x, box.y2(), box.w, 1), low);
            b.drawLineV(T, .xywh(box.x2(), box.y + 1, 1, box.h), low);
        },
        else => unreachable,
    }
}

pub fn drawRectangle(b: *Buffer, T: type, box: Box, ecolor: T) void {
    b.addDamage(box);
    const width = box.x + box.w;
    const height = box.y + box.h;
    const color: u32 = @intFromEnum(ecolor);
    assert(box.w > 1);
    assert(box.h > 1);
    for (box.y + 1..height - 1) |y| {
        const row = b.rowSlice(y);
        row[box.x] = color;
        row[width - 1] = color;
    }
    const top = b.rowSlice(box.y);
    @memset(top[box.x..width], color);
    const bottom = b.rowSlice(height - 1);
    @memset(bottom[box.x..width], color);
}

pub fn drawRectangleFill(b: *Buffer, T: type, box: Box, ecolor: T) void {
    b.addDamage(box);
    const width = box.x + box.w;
    const height = box.y + box.h;
    const color: u32 = @intFromEnum(ecolor);
    assert(box.w > 2);
    assert(box.h > 2);
    for (box.y..height) |y| {
        const row = b.rowSlice(y);
        @memset(row[box.x..width], color);
    }
}

pub fn drawRectangleFillMix(b: *Buffer, T: type, box: Box, ecolor: T) void {
    b.addDamage(box);
    //const width = box.x + box.w;
    const height = box.y + box.h;
    //const color: u32 = @intFromEnum(ecolor);
    assert(box.w > 2);
    assert(box.h > 2);
    for (box.y..height) |y| {
        const row = b.rowSlice(y);
        for (box.x..box.x2()) |x| {
            ecolor.mixInt(&row[x]);
        }
    }
}

pub fn drawRectangleRounded(b: *Buffer, T: type, box: Box, base_r: f64, ecolor: T) void {
    b.addDamage(box);
    const r: f64 = base_r - 0.5;
    const color: u32 = @intFromEnum(ecolor);
    const radius: usize = @intFromFloat(base_r);
    assert(box.w > radius);
    assert(box.h > radius);
    for (box.y..box.y + radius, 0..) |dst_y, y| {
        const row = b.rowSlice(dst_y);
        const dy: f64 = @as(f64, @floatFromInt(y)) - r;
        for (box.x..box.x + radius, 0..) |dst_x, x| {
            const dx: f64 = @as(f64, @floatFromInt(x)) - r;
            const pixel: f64 = hypot(dx, dy) - r + 0.6;
            if (pixel <= 1.0 and pixel >= 0.0) row[dst_x] = color;
        }
        for (box.x2() - radius..box.x2(), radius..) |dst_x, x| {
            const dx: f64 = @as(f64, @floatFromInt(x)) - r;
            const pixel: f64 = hypot(dx, dy) - r + 0.6;
            if (pixel <= 1.0 and pixel >= 0.0) row[dst_x] = color;
        }
    }

    for (box.y2() - radius..box.y2(), radius..) |dst_y, y| {
        const row = b.rowSlice(dst_y);
        const dy: f64 = @as(f64, @floatFromInt(y)) - r;
        for (box.x..box.x + radius, 0..) |dst_x, x| {
            const dx: f64 = @as(f64, @floatFromInt(x)) - r;
            const pixel: f64 = hypot(dx, dy) - r + 0.6;
            if (pixel <= 1.0 and pixel >= 0.0) row[dst_x] = color;
        }
        for (box.x2() - radius..box.x2(), radius..) |dst_x, x| {
            const dx: f64 = @as(f64, @floatFromInt(x)) - r;
            const pixel: f64 = hypot(dx, dy) - r + 0.6;
            if (pixel <= 1.0 and pixel >= 0.0) row[dst_x] = color;
        }
    }

    for (box.y + radius..box.y2() - radius) |y| {
        const row = b.rowSlice(y);
        row[box.x] = color;
        row[box.x2() - 1] = color;
    }
    const top = b.rowSlice(box.y);
    @memset(top[box.x + radius .. box.x2() - radius], color);
    const bottom = b.rowSlice(box.y2() - 1);
    @memset(bottom[box.x + radius .. box.x2() - radius], color);
}

pub fn drawRectangleRoundedFill(b: *Buffer, T: type, box: Box, base_r: f64, ecolor: T) void {
    b.addDamage(box);
    const r: f64 = base_r - 0.5;
    const radius: usize = @intFromFloat(base_r);
    const color: u32 = @intFromEnum(ecolor);
    assert(box.w > radius);
    assert(box.h > radius);
    for (box.y..box.y + radius, 0..) |dst_y, y| {
        const row = b.rowSlice(dst_y);
        const dy: f64 = @as(f64, @floatFromInt(y)) - r;
        for (box.x..box.x + radius, 0..) |dst_x, x| {
            const dx: f64 = @as(f64, @floatFromInt(x)) - r;
            const pixel: f64 = hypot(dx, dy) - r + 0.6;
            if (pixel <= 1.0) row[dst_x] = color;
        }
        for (box.x2() - radius..box.x2(), radius..) |dst_x, x| {
            const dx: f64 = @as(f64, @floatFromInt(x)) - r + 0.0;
            const pixel: f64 = hypot(dx, dy) - r + 0.6;
            if (pixel <= 1.0) row[dst_x] = color;
        }
        @memset(row[box.x + radius .. box.x2() - radius], color);
    }

    for (box.y2() - radius..box.y2(), radius..) |dst_y, y| {
        const row = b.rowSlice(dst_y);
        const dy: f64 = @as(f64, @floatFromInt(y)) - r;
        for (box.x..box.x + radius, 0..) |dst_x, x| {
            const dx: f64 = @as(f64, @floatFromInt(x)) - r;
            const pixel: f64 = hypot(dx, dy) - r + 0.6;
            if (pixel < 1.0) row[dst_x] = color;
        }
        for (box.x2() - radius..box.x2(), radius..) |dst_x, x| {
            const dx: f64 = @as(f64, @floatFromInt(x)) - r;
            const pixel: f64 = hypot(dx, dy) - r + 0.6;
            if (pixel < 1.0) row[dst_x] = color;
        }
        @memset(row[box.x + radius .. box.x2() - radius], color);
    }

    for (box.y + radius..box.y2() - radius) |y| {
        const row = b.rowSlice(y);
        @memset(row[box.x..box.x2()], color);
    }
    const top = b.rowSlice(box.y);
    @memset(top[box.x + radius .. box.x2() - radius], color);
    const bottom = b.rowSlice(box.y2() - 1);
    @memset(bottom[box.x + radius .. box.x2() - radius], color);
}

pub fn drawPoint(b: *Buffer, T: type, box: Box, ecolor: T) void {
    b.addDamage(box);
    assert(box.w < 2);
    assert(box.h < 2);
    const color: u32 = @intFromEnum(ecolor);
    const row = b.rowSlice(box.y);
    row[box.x] = color;
}

pub fn drawCircleFill(b: *Buffer, T: type, box: Box, ecolor: T) void {
    b.addDamage(box);
    const color: u32 = @intFromEnum(ecolor);
    const half: f64 = @as(f64, @floatFromInt(box.w)) / 2.0 - 0.5;
    for (box.y..box.y + box.w, 0..) |dst_y, y| {
        const row = b.rowSlice(dst_y);
        for (box.x..box.x + box.w, 0..) |dst_x, x| {
            const dx: f64 = @as(f64, @floatFromInt(x)) - half;
            const dy: f64 = @as(f64, @floatFromInt(y)) - half;
            const pixel: f64 = hypot(dx, dy) - half + 0.5;
            if (pixel <= 1) row[dst_x] = color;
        }
    }
}

/// TODO add support for center vs corner alignment
pub fn drawCircle(b: *Buffer, T: type, box: Box, ecolor: T) void {
    b.addDamage(box);
    const color: u32 = @intFromEnum(ecolor);
    const half: f64 = @as(f64, @floatFromInt(box.w)) / 2.0 - 0.5;
    for (box.y..box.y + box.w, 0..) |dst_y, y| {
        const row = b.rowSlice(dst_y);
        for (box.x..box.x + box.w, 0..) |dst_x, x| {
            const dx: f64 = @as(f64, @floatFromInt(x)) - half;
            const dy: f64 = @as(f64, @floatFromInt(y)) - half;
            const pixel: f64 = hypot(dx, dy) - half + 0.5;
            if (pixel < 1.5 and pixel > 0.5) row[dst_x] = color;
        }
    }
}

pub fn drawCircleCentered(b: *Buffer, T: type, box: Box, ecolor: T) void {
    b.addDamage(box);
    assert(box.h == box.w);
    assert(box.x > (box.w - 1) / 2);
    assert(box.y > (box.h - 1) / 2);
    const color: u32 = @intFromEnum(ecolor);
    const half: f64 = @as(f64, @floatFromInt(box.w)) / 2.0 - 0.5;
    const adj_x: u32 = @truncate(box.x - @as(u32, @intFromFloat(@floor(half + 0.6))));
    const adj_y: u32 = @truncate(box.y - @as(u32, @intFromFloat(@floor(half + 0.6))));

    for (adj_y..adj_y + box.h, 0..) |dst_y, y| {
        const row = b.rowSlice(dst_y);
        for (adj_x..adj_x + box.w, 0..) |dst_x, x| {
            const dx: f64 = @as(f64, @floatFromInt(x)) - half;
            const dy: f64 = @as(f64, @floatFromInt(y)) - half;
            const pixel: f64 = hypot(dx, dy) - half + 0.5;
            if (pixel <= 1) row[dst_x] = color;
        }
    }
}

pub fn drawFont(b: *Buffer, T: type, color: T, box: Box, src: []const u8) void {
    b.addDamage(box);
    for (0..box.h, box.y..) |sy, dy| {
        const row = b.rowSlice(dy);
        for (box.x..box.x + box.w, 0..) |dx, sx| {
            const p: u8 = src[sy * box.w + sx];
            if (p == 0) continue;
            const color2 = color.alpha(p);
            color2.mixInt(&row[dx]);
        }
    }
}

const std = @import("std");
const assert = std.debug.assert;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const posix = std.posix;
const hypot = std.math.hypot;
