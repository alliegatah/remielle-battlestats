pub fn packBuddyInfo(arena: Allocator, id: logic.Properties.Buddy.Id, meta: *const logic.Properties.Buddy.Meta) !pb.BuddyInfo {
    const Buddy = logic.Properties.Buddy;
    var skill_levels: ArrayList(pb.BuddySkillLevel) = try .initCapacity(arena, Buddy.Skill.Levels.len);

    inline for (std.meta.fields(Buddy.Skill)) |field| {
        const skill: Buddy.Skill = @enumFromInt(field.value);
        const level = meta.skill_levels.get(skill);
        skill_levels.appendAssumeCapacity(.{
            .skill_type = skill.toInt(),
            .level = level.toInt(),
        });
    }

    return .{
        .id = @intFromEnum(id),
        .level = meta.level.toInt(),
        .exp = meta.exp,
        .rank = meta.rank.toInt(),
        .star = meta.star.toInt(),
        .is_favorite = meta.flags.favorite,
        .skill_type_level = skill_levels,
    };
}

pub fn packSelfBasicInfo(arena: Allocator, info: *const Properties.BasicInfo) !pb.SelfBasicInfo {
    _ = arena;

    return .{
        .level = info.level.toInt(),
        .nick_name = "xeondev", // TODO
        .name_change_times = 1, // TODO
        .avatar_id = info.avatar.toInt(),
        .control_avatar_id = info.control_avatar.toInt(),
        .control_guise_avatar_id = info.control_guise_avatar.toInt(),
    };
}

pub fn packAvatarInfo(
    arena: Allocator,
    id: Avatar.Id,
    meta: *const Avatar.Meta,
    weapon_uid: Avatar.OptionalUID,
    equipment_uids: [Avatar.equipment_slots]Avatar.OptionalUID,
) !pb.AvatarInfo {
    var avatar_skills: [Avatar.Skill.count]pb.AvatarSkillLevel = undefined;

    for (&avatar_skills, meta.skill_levels, 0..) |*avatar_skill, level, skill_type|
        avatar_skill.* = .{ .skill_type = @intCast(skill_type), .level = level.toInt() };

    var dressed_equip_list: ArrayList(pb.DressedEquip) = try .initCapacity(arena, Avatar.equipment_slots);

    for (equipment_uids, 1..) |maybe_uid, slot| if (maybe_uid.unwrap()) |uid|
        dressed_equip_list.appendAssumeCapacity(.{
            .index = @intCast(slot),
            .equip_uid = uid,
        });

    return .{
        .id = @intFromEnum(id),
        .level = meta.level.toInt(),
        .rank = meta.rank.toInt(),
        .unlocked_talent_num = meta.talents.toInt(),
        .talent_switch_list = .fromOwnedSlice(try arena.dupe(bool, &meta.talent_switch.toBools())),
        .skill_type_level = .fromOwnedSlice(try arena.dupe(pb.AvatarSkillLevel, &avatar_skills)),
        .passive_skill_level = meta.skill_levels[Avatar.Skill.core_skill.toInt()].toInt() - 1,
        .cur_weapon_uid = weapon_uid.unwrap() orelse 0,
        .dressed_equip_list = dressed_equip_list,
        .is_favorite = meta.flags.favorite,
        .avatar_skin_id = meta.skin.toInt(),
    };
}

pub fn packEquipmentInfo(
    arena: Allocator,
    uid: Equipment.Uid,
    id: u32,
    level: Equipment.Level,
    star: Equipment.Star,
    properties: *const [Equipment.properties_count]Equipment.Property,
) !pb.EquipInfo {
    var equip_properties: ArrayList(pb.EquipProperty) = try .initCapacity(
        arena,
        Properties.Equipment.properties_count,
    );

    equip_properties.appendAssumeCapacity(.{
        .key = @intFromEnum(properties[0].key), // main property is required.
        .base_value = properties[0].base_value,
        .add_value = properties[0].add_value,
    });

    for (properties[1..]) |prop| if (prop.key.unwrap()) |key|
        equip_properties.appendAssumeCapacity(.{
            .key = key,
            .base_value = prop.base_value,
            .add_value = prop.add_value,
        });

    return .{
        .uid = uid.toInt(),
        .id = id,
        .level = level.toInt(),
        .star = star.toInt(),
        .propertys = .fromOwnedSlice(equip_properties.items[0..1]),
        .sub_propertys = .fromOwnedSlice(equip_properties.items[1..]),
    };
}

const ArrayList = std.ArrayList;
const Avatar = Properties.Avatar;
const Equipment = Properties.Equipment;
const Properties = logic.Properties;
const Allocator = std.mem.Allocator;

const logic = @import("../logic.zig");

const pb = @import("rmpb").main;
const std = @import("std");
