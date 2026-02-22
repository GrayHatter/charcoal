const Box = @This();

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

    pub fn fromBox(b: Box) Delta {
        return .{
            .x = @intCast(b.x),
            .y = @intCast(b.y),
            .w = @intCast(b.w),
            .h = @intCast(b.h),
        };
    }

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
    x: usize,
    y: usize,

    pub fn xy(x: usize, y: usize) XY {
        return .{ .x = x, .y = y };
    }

    pub fn box(xy_: XY) Box {
        return .xy(xy_.x, xy_.y);
    }

    pub fn fromBox(b: Box) XY {
        return .xy(b.x, b.y);
    }
};

/// Box.x + Box.w
pub inline fn x2(b: Box) usize {
    return b.x + b.w;
}

/// Box.y + Box.h
pub inline fn y2(b: Box) usize {
    return b.y + b.h;
}

/// Box.w - Box.x
pub inline fn w2(b: Box) usize {
    return b.w - b.x;
}

/// Box.h + Box.y
pub inline fn h2(b: Box) usize {
    return b.h - b.y;
}

pub fn toXY(b: Box) XY {
    return .xy(b.x, b.y);
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
