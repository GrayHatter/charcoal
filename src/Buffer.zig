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
pub const Box = @import("Box.zig");

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

pub const Point = struct {
    x: f64,
    y: f64,

    pub fn pt(x: anytype, y: anytype) Point {
        return .{
            .x = switch (@TypeOf(x)) {
                f64 => x,
                f32 => x,
                comptime_float => x,
                usize => @floatFromInt(x),
                u32 => @floatFromInt(x),
                comptime_int => x,
                else => |T| @compileError("Point.pt not implemented for type " ++ @typeName(T)),
            },
            .y = switch (@TypeOf(y)) {
                f64 => y,
                f32 => y,
                comptime_float => y,
                usize => @floatFromInt(y),
                u32 => @floatFromInt(y),
                comptime_int => y,
                else => |T| @compileError("Point.pt not implemented for type " ++ @typeName(T)),
            },
        };
    }

    pub fn xyRound(p: Point) Box.XY {
        // lol
        const x = @round(p.x);
        const y = @round(p.y);
        return .{ .x = @intFromFloat(x), .y = @intFromFloat(y) };
    }

    pub fn format(point: Point, w: *std.Io.Writer) !void {
        try w.print("{: >8.4} {: >8.4}      {: >8.4} {: >8.4}", .{
            point.x, point.y, @round(point.x), @round(point.y),
        });
    }
};

pub fn init(shm: *wl.Shm, box: Box, name: [:0]const u8) !Buffer {
    return try initCapacity(shm, box, box, name);
}

pub fn initCapacity(shm: *wl.Shm, active: Box, extra: Box, name: [:0]const u8) !Buffer {
    const color_byte_size = 4;
    const width: u31 = @intCast(@max(active.w, extra.w));
    const stride: u31 = width * color_byte_size;
    const height: u31 = @intCast(@max(active.h, extra.h));
    const size: u31 = stride * height;

    const active_width: u31 = @intCast(active.w);
    const active_height: u31 = @intCast(active.h);

    const fd = linux.memfd_create(name.ptr, 0);
    if (fd < 0) return error.MemFdCreateFailed;
    if (std.os.linux.ftruncate(@intCast(fd), size) != 0) return error.TruncateFailed;
    const prot = std.os.linux.PROT{ .READ = true, .WRITE = true };
    const raw_code = linux.mmap(null, size, prot, .{ .TYPE = .SHARED }, @intCast(fd), 0);
    if (std.posix.errno(raw_code) != .SUCCESS) @panic("OOM");
    const raw = @as([*]align(std.heap.page_size_min) u8, @ptrFromInt(raw_code))[0..size];

    const pool = try shm.createPool(@intCast(fd), size);
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
    _ = linux.munmap(@ptrCast(@alignCast(b.raw)), b.raw.len);
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

pub fn addDamage(b: *Buffer, dmg: Box) void {
    if (@max(b.damage.x, b.damage.y, b.damage.w, b.damage.h) == 0) {
        b.damage = .{ .x = dmg.x, .y = dmg.y, .w = dmg.x2(), .h = dmg.y2() };
        return;
    }
    b.damage = .{
        .x = @min(b.damage.x, dmg.x),
        .y = @min(b.damage.y, dmg.y),
        .w = @max(b.damage.w, dmg.x2()),
        .h = @max(b.damage.h, dmg.y2()),
    };
}

pub fn getDamage(b: *Buffer) ?Box {
    if (b.damage.x == 0 and b.damage.y == 0 and b.damage.w == 0 and b.damage.h == 0) return null;
    defer b.damage = .zero;
    return b.damage;
}

pub fn damageAll(b: *Buffer) void {
    b.addDamage(.wh(b.width, b.height));
}

fn rowSlice(b: Buffer, y: usize) []u32 {
    return b.raw[b.stride * y ..][0..b.width];
}

pub fn draw(b: Buffer, box: Box, src: []const u32) void {
    for (0..box.h, box.y..box.y2()) |sy, dy| {
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
    assert(box.w <= src_box.w);
    assert(box.h <= src_box.h);

    for (0..box.h, box.y..box.y2()) |sy, dy| {
        const src_row = src[(sy + src_box.y) * src_box.w ..][0..src_box.w];
        @memcpy(
            b.rowSlice(dy)[box.x..][0..box.w],
            @as([]const u32, @ptrCast(src_row[src_box.x..][0..box.w])),
        );
    }
}

pub fn copy(b: Buffer, T: type, box: Box, src: []const T) void {
    for (0..box.h, box.y..box.y2()) |sy, dy| {
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
    b.addDamage(box);
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
    const color: u32 = @intFromEnum(ecolor);
    assert(box.w > 1);
    assert(box.h > 1);
    for (box.y + 1..box.y2() -| 1) |y| {
        const row = b.rowSlice(y);
        row[box.x] = color;
        row[box.x2() -| 1] = color;
    }
    const top = b.rowSlice(box.y);
    @memset(top[box.x..box.x2()], color);
    const bottom = b.rowSlice(box.y2() -| 1);
    @memset(bottom[box.x..box.x2()], color);
}

pub fn drawRectangleFill(b: *Buffer, T: type, box: Box, ecolor: T) void {
    b.addDamage(box);
    const width = box.x + box.w;
    const height = box.y + box.h;
    const color: u32 = @intFromEnum(ecolor);
    assert(box.w > 1);
    assert(box.h > 1);
    for (box.y..height) |y| {
        const row = b.rowSlice(y);
        @memset(row[box.x..width], color);
    }
}

pub fn drawRectangleFillMix(b: *Buffer, T: type, box: Box, ecolor: T) void {
    b.addDamage(box);
    //const width = box.x + box.w;
    //const color: u32 = @intFromEnum(ecolor);
    assert(box.w > 1);
    assert(box.h > 1);
    for (box.y..box.y2()) |y| {
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

pub fn drawPoint(b: *Buffer, T: type, pos: Box.XY, ecolor: T) void {
    const color: u32 = @intFromEnum(ecolor);
    b.rowSlice(pos.y)[pos.x] = color;
}

pub fn drawFPoint(b: *Buffer, T: type, point: Point, rule: enum { hard, soft }, ecolor: T) void {
    const color: u32 = @intFromEnum(ecolor);
    switch (rule) {
        .hard => {
            const pos = point.xyRound();
            b.rowSlice(pos.y)[pos.x] = color;
        },
        .soft => {
            const pos = point.xyRound();
            b.rowSlice(pos.y)[pos.x] = color;
        },
    }
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

pub fn drawTrianglePoints(b: *Buffer, T: type, box: Box, color: T, points: [3]Point) void {
    const p0, const p1, const p2 = points;
    const area = (-p1.y * p2.x + p0.y * (p2.x - p1.x) + p0.x * (p1.y - p2.y) + p1.x * p2.y);
    const s_c = p0.y * p2.x - p0.x * p2.y;
    const s_t = p0.x * p1.y - p0.y * p1.x;
    stride: for (0..box.h) |y| {
        const s_y: f64 = (p0.x - p2.x) * @as(f64, @floatFromInt(y));
        const t_y: f64 = (p1.x - p0.x) * @as(f64, @floatFromInt(y));
        const row = b.rowSlice(box.y + y);
        var open: bool = false;
        for (0..box.w) |x| {
            const px: f64 = @floatFromInt(x);
            const s = 1 / area * (s_c + (p2.y - p0.y) * px + s_y);
            const t = 1 / area * (s_t + (p0.y - p1.y) * px + t_y);
            if (s >= 0 and t >= 0 and s + t <= 1) {
                row[box.x + x] = @intFromEnum(color);
                open = true;
            } else if (open) continue :stride;
        }
    }
}

pub fn drawTriangle(b: *Buffer, T: type, dir: Direction, box: Box, color: T) void {
    const points: [3]Point = switch (dir) {
        .north => .{
            .pt(box.w, box.h),
            .pt(0, box.h),
            .pt(@as(f64, @floatFromInt(box.w)) / 2.0, 0),
        },
        .north_east => .{
            .pt(0, 0),
            .pt(box.w, 0),
            .pt(box.w, box.h),
        },
        .east => .{
            .pt(0, 0),
            .pt(box.w, @as(f64, @floatFromInt(box.h)) / 2.0),
            .pt(0, box.h),
        },
        .south_east => .{
            .pt(box.w, box.h),
            .pt(0, box.h),
            .pt(box.w, 0),
        },
        .south => .{
            .pt(0, 0),
            .pt(box.w, 0),
            .pt(@as(f64, @floatFromInt(box.w)) / 2.0, box.h),
        },
        .south_west => .{
            .pt(0, 0),
            .pt(box.w, box.h),
            .pt(0, box.h),
        },
        .west => .{
            .pt(box.w, 0),
            .pt(box.w, box.h),
            .pt(0, @as(f64, @floatFromInt(box.h)) / 2.0),
        },
        .north_west => .{
            .pt(0, 0),
            .pt(box.w, 0),
            .pt(0, box.h),
        },
    };
    b.drawTrianglePoints(T, box, color, points);
}

pub fn drawFont(b: *Buffer, T: type, color: T, box: Box, src: []const u8) void {
    b.addDamage(box);
    for (0..box.h, box.y..) |sy, dy| {
        const row = b.rowSlice(dy);
        for (box.x..box.x2(), 0..) |dx, sx| {
            const p: u8 = src[sy * box.w + sx];
            if (p == 0) continue;
            const color2 = color.alpha(p);
            color2.mixInt(&row[dx]);
        }
    }
}

pub fn drawBezier3(buf: *Buffer, T: type, points: [3]Point, color: T) void {
    const a, const b, const c = points;
    for (0..1000) |i| {
        const t: f64 = @floatFromInt(i);
        const p = bezier(t / 1000.0, a, b, b, c);
        buf.drawFPoint(T, p, .hard, color);
    }
}

pub fn drawBezier4(buf: *Buffer, T: type, points: [4]Point, color: T) void {
    const a, const b, const c, const d = points;
    for (0..1000) |i| {
        const t: f64 = @floatFromInt(i);
        const p = bezier(t / 1000.0, a, b, c, d);
        buf.drawFPoint(T, p, .hard, color);
    }
}

fn bezier(t: f64, a: Point, b: Point, c: Point, d: Point) Point {
    const t2 = pow(f64, t, 2);
    const t3 = pow(f64, t, 3);
    const T = 1.0 - t;
    const T_2 = pow(f64, T, 2);
    const T_3 = pow(f64, T, 3);
    const _3t_T2 = 3 * t * T_2;
    const _3t2_T = 3 * t2 * T;

    // B = (1-t)^3 * a + 3t(1-t)^2 * b + 3t^2(1-t) * c + t^3 * d;

    return .{
        .x = @mulAdd(f64, T_3, a.x, @mulAdd(f64, _3t_T2, b.x, @mulAdd(f64, _3t2_T, c.x, t3 * d.x))),
        .y = @mulAdd(f64, T_3, a.y, @mulAdd(f64, _3t_T2, b.y, @mulAdd(f64, _3t2_T, c.y, t3 * d.y))),
    };
}

test bezier {
    const a: Point = .{ .x = 100.0, .y = 100.0 };
    const b: Point = .{ .x = 200.0, .y = 200.0 };
    const c: Point = .{ .x = 200.0, .y = 200.0 };
    const d: Point = .{ .x = 300.0, .y = 100.0 };

    for (0..1000) |i| {
        const t: f64 = @floatFromInt(i);
        const p = bezier(t / 1000.0, a, b, c, d);
        if (false) std.debug.print("{f}\n", .{p});
    }
}

test {
    _ = &std.testing.refAllDecls(@This());
}

const std = @import("std");
const assert = std.debug.assert;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const hypot = std.math.hypot;
const pow = std.math.pow;
const linux = std.os.linux;
