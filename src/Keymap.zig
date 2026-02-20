data: ?[]const u8 = null,

const Keymap = @This();

const AModded = [4]?u8;
const CModded = [4]?Control;

pub const Control = enum(u16) {
    escape = 1,
    ctrl_left = 29,
    alt_left = 56,
    shift_left = 42,
    shift_right = 54,

    backspace = 14,
    delete = 111,
    enter = 28,
    meta = 125,

    delete_word,

    arrow_up = 103,
    arrow_down = 108,
    arrow_left = 105,
    arrow_right = 106,
    tab = 15,

    ascii_char,

    UNKNOWN = 0,
};

pub const KMod = struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,

    pub const Wrapped = enum {
        none,
        shf,
        ctl,
        alt,
        shf_ctl,
        shf_alt,
        ctl_alt,
        shf_ctl_alt,
    };

    pub const ControlW = union(Wrapped) {
        none: Control,
        shf: Control,
        ctl: Control,
        alt: Control,
        shf_ctl: Control,
        shf_alt: Control,
        ctl_alt: Control,
        shf_ctl_alt: Control,
    };

    pub fn init(code: u32) KMod {
        return .{
            .shift = code & 1 > 0,
            .ctrl = code & 4 > 0,
            .alt = code & 8 > 0,
        };
    }

    pub fn wrappedCtrl(km: KMod, ct: CModded) ControlW {
        if (km.shift) {
            return if (km.ctrl and km.alt)
                .{ .shf_ctl_alt = ct[1] }
            else if (km.ctrl)
                .{ .shf_ctl = ct[1] }
            else if (km.alt)
                .{ .shf_alt = ct[1] }
            else
                .{ .shf = ct[1] };
        } else if (km.ctrl) {
            return if (km.alt)
                .{ .ctl_alt = ct[2] }
            else
                .{ .ctl = ct[2] };
        } else if (km.alt) {
            return .{ .alt = ct[3] };
        }
        return .{ .none = ct[0] };
    }
};

pub fn init() Keymap {
    return .{};
}

pub fn initFd(fd: anytype, size: u32) !Keymap {
    const prot = std.os.linux.PROT{ .READ = true, .WRITE = true };
    const data_code = std.os.linux.mmap(null, size, prot, .{ .TYPE = .PRIVATE }, fd, 0);
    if (std.posix.errno(data_code) != .SUCCESS) @panic("OOM");
    const data = @as([*]align(std.heap.page_size_min) u8, @ptrFromInt(data_code))[0..size];

    if (false) std.debug.print("{s}\n", .{data});
    _ = try parse(data);
    return .{
        .data = data,
    };
}

pub fn raze(k: Keymap) void {
    if (k.data) |d| _ = std.os.linux.munmap(@alignCast(d.ptr), d.len);
}

fn parse(_: []const u8) !void {
    // lol you thought
    return error.NotImplemented;
}

pub fn ascii(_: Keymap, key: u32, mods: KMod) ?u8 {
    const code: AModded = switch (key) {
        40 => .{ '\'', '"', '\'', '\'' },
        51 => .{ ',', '<', ',', ',' },
        52 => .{ '.', '>', '.', '.' },
        25 => .{ 'p', 'P', 'p', 'p' },
        21 => .{ 'y', 'Y', 'y', 'y' },
        33 => .{ 'f', 'F', 'f', 'f' },
        34 => .{ 'g', 'G', 'g', 'g' },
        46 => .{ 'c', 'C', 'c', 'c' },
        19 => .{ 'r', 'R', 'r', 'r' },
        38 => .{ 'l', 'L', 'l', 'l' },
        30 => .{ 'a', 'A', 'a', 'a' },
        24 => .{ 'o', 'O', 'o', 'o' },
        18 => .{ 'e', 'E', 'e', 'e' },
        22 => .{ 'u', 'U', 'u', 'u' },
        57 => .{ ' ', ' ', ' ', ' ' },
        23 => .{ 'i', 'I', 'i', 'i' },
        32 => .{ 'd', 'D', 'd', 'd' },
        35 => .{ 'h', 'H', 'h', 'h' },
        20 => .{ 't', 'T', 't', 't' },
        49 => .{ 'n', 'N', 'n', 'n' },
        31 => .{ 's', 'S', 's', 's' },
        39 => .{ ';', ':', ';', ';' },
        53 => .{ '/', '|', '/', '/' },
        13 => .{ '=', '+', '=', '=' },
        12 => .{ '-', '_', '-', '-' },
        16 => .{ 'q', 'Q', 'q', 'q' },
        36 => .{ 'j', 'J', 'j', 'j' },
        37 => .{ 'k', 'K', 'k', 'k' },
        45 => .{ 'x', 'X', 'x', 'x' },
        48 => .{ 'b', 'B', 'b', 'b' },
        50 => .{ 'm', 'M', 'm', 'm' },
        17 => .{ 'w', 'W', null, 'w' },
        47 => .{ 'v', 'V', 'v', 'v' },
        44 => .{ 'z', 'Z', 'z', 'z' },
        2 => .{ '1', '!', '1', '1' },
        3 => .{ '2', '@', '2', '2' },
        4 => .{ '3', '#', '3', '3' },
        5 => .{ '4', '$', '4', '4' },
        6 => .{ '5', '%', '5', '5' },
        7 => .{ '6', '^', '6', '6' },
        8 => .{ '7', '&', '7', '7' },
        9 => .{ '8', '*', '8', '8' },
        10 => .{ '9', '(', '9', '9' },
        11 => .{ '0', ')', '0', '0' },

        15 => .{ null, null, null, null }, // Tab,
        42 => .{ null, null, null, null }, // Left Shift,
        54 => .{ null, null, null, null }, // Right Shift,
        29 => .{ null, null, null, null }, // Left Ctrl,
        97 => .{ null, null, null, null }, // Right Ctrl,
        56 => .{ null, null, null, null }, // Left Alt,
        14 => .{ null, null, null, null }, // Backspace,
        28 => .{ null, null, null, null }, // Enter,
        125 => .{ null, null, null, null }, // Meta,
        103 => .{ null, null, null, null }, // Up,
        108 => .{ null, null, null, null }, // Down,
        105 => .{ null, null, null, null }, // Left,
        106 => .{ null, null, null, null }, // Right,
        111 => .{ null, null, null, null }, // Delete,
        1 => .{ null, null, null, null }, // Escape,
        else => {
            std.debug.print("Unable to translate ascii {}\n", .{key});
            return null;
        },
    };
    return if (mods.shift)
        code[1]
    else if (mods.ctrl)
        code[2]
    else if (mods.alt)
        code[3]
    else
        code[0];
}

pub fn ctrlMods(key: u32, mods: KMod) Control {
    const code: CModded = switch (key) {
        17 => .{ null, null, .delete_word, null },
        else => {
            std.debug.print("Unable to translate ctrlMod {}\n", .{key});
            return .UNKNOWN;
        },
    };

    const ctrlM: ?Control = if (mods.shift)
        code[1]
    else if (mods.ctrl)
        code[2]
    else if (mods.alt)
        code[3]
    else
        code[0];

    return ctrlM orelse {
        std.debug.print("Unable to translate ctrlMod {}\n", .{key});
        return .UNKNOWN;
    };
}

pub fn ctrl(_: Keymap, key: u32, mods: KMod) Control {
    return switch (key) {
        2...11 => .ascii_char,
        29 => .ctrl_left,
        42 => .shift_left,
        54 => .shift_right,
        56 => .alt_left,
        14 => .backspace,
        28 => .enter, // Enter
        125 => .meta, // Meta
        1 => .escape,
        103 => .arrow_up,
        108 => .arrow_down,
        105 => .arrow_left,
        106 => .arrow_right,
        15 => .tab,
        111 => .delete,
        17 => ctrlMods(key, mods),
        else => {
            std.debug.print("Unable to translate  ctrl {}\n", .{key});
            return .UNKNOWN;
        },
    };
}

test {
    _ = &std.testing.refAllDecls(@This());
}

const std = @import("std");
