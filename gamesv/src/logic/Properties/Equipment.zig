const size = templates.equipment.entries.len;

pub const max_properties_slots = 1;
pub const max_sub_properties_slots = 4;

pub const max_properties_per_item = max_properties_slots + max_sub_properties_slots;

pub const max_equipment = 3000;

count: u16,
uids: [max_equipment]Uid,
ids: [size]u32,
levels: [max_equipment]Level,
stars: [max_equipment]Star,
properties: [max_equipment][max_properties_per_item]?Property,

pub const init: Equipment = .{
    .count = 0,
    .uids = undefined,
    .ids = undefined,
    .levels = undefined,
    .stars = undefined,
    .properties = undefined,
};

pub const Uid = enum(u16) {
    _,

    pub const base: u32 = 0x02_00_00;

    /// From the protocol UID representation.
    pub fn fromInt(uid: u32) ?Uid {
        if (uid < base or uid > base + std.math.maxInt(u16))
            return null;

        return @enumFromInt(@as(u16, @intCast(uid - base)));
    }

    /// To the protocol UID representation.
    pub fn toInt(uid: Uid) u32 {
        return @intFromEnum(uid) + base;
    }
};

pub const Level = enum(u8) {
    init = 0,
    max = 15,
    _,

    pub fn toInt(level: Level) u8 {
        return @intFromEnum(level);
    }
};

pub const Star = enum(u8) {
    init = 0,
    max = 5,
    _,

    pub fn toInt(star: Star) u8 {
        return @intFromEnum(star);
    }
};

pub const Slot = enum(u8) {
    _,

    pub fn fromInt(index: u32) ?Slot {
        if (index < 1 or index > 6)
            return null;

        return @enumFromInt(@as(u8, @intCast(index)));
    }

    pub fn toIndex(dress_index: Slot) u8 {
        return @intFromEnum(dress_index) - 1;
    }
};

pub const Property = struct {
    key: u32,
    base_value: u32,
    add_value: u32,
};

const templates = Assets.templates;

const Assets = @import("../../Assets.zig");

const std = @import("std");
const Equipment = @This();
