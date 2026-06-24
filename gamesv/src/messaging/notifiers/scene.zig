pub fn switchGameMode(
    properties: logic.Properties.Immutable(.{
        logic.Properties.BasicInfo,
        logic.Properties.Avatar,
        logic.Properties.Weapon,
        logic.Properties.Equipment,
    }),
    changes: logic.Changes.Subset(.{
        logic.Changes.GameMode,
    }),
    notify: Notify(pb.EnterSceneScNotify),
) !void {
    const game_mode = changes.game_mode.?;

    switch (game_mode) {
        .hall => |hall| notify.one(.{ .scene = .{
            .scene_type = 1,
            .hall_scene_data = .{
                .section_id = @intFromEnum(hall.section_id),
                .control_avatar_id = properties.basic_info.control_avatar.toInt(),
                .control_guise_avatar_id = properties.basic_info.control_guise_avatar.toInt(),
            },
        } }),
        .training => |training| notify.one(.{
            .scene = .{
                .scene_type = 3, // training is implemented in terms of FightScene
                .play_type = 290,
                .scene_id = training.quest.getBattleEventId(),
                .fight_scene_data = .{
                    .scene_reward = .init,
                    .scene_perform = .init,
                },
            },
            .dungeon = .{
                .quest_id = @intFromEnum(training.quest),
                .dungeon_package_info = dungeon_package_info: {
                    // Always allocates `avatars.len` (which is constant), but that's okay.
                    var avatar_list: ArrayList(pb.AvatarInfo) = try .initCapacity(
                        notify.allocator,
                        training.avatars.len,
                    );

                    var weapon_list: ArrayList(pb.WeaponInfo) = try .initCapacity(
                        notify.allocator,
                        training.avatars.len,
                    );

                    var equip_list: ArrayList(pb.EquipInfo) = try .initCapacity(
                        notify.allocator,
                        training.avatars.len * Properties.Avatar.equipment_slots,
                    );

                    for (training.avatars) |slot| if (slot.toId()) |avatar_id| {
                        const index = properties.avatar.indexes.get(avatar_id).?;

                        avatar_list.appendAssumeCapacity(try packers.packAvatarInfo(
                            notify.allocator,
                            avatar_id,
                            &properties.avatar.meta[index],
                            properties.avatar.weapon_uids[index],
                            properties.avatar.equipment_uids[index],
                        ));

                        if (properties.avatar.weapon_uids[index].unwrap()) |weapon_uid_int| {
                            const weapon_uid = logic.Properties.Weapon.Uid.fromInt(weapon_uid_int).?;
                            const weapon_index = std.mem.findScalar(
                                logic.Properties.Weapon.Uid,
                                &properties.weapon.uids,
                                weapon_uid,
                            ).?;

                            weapon_list.appendAssumeCapacity(.{
                                .uid = weapon_uid_int,
                                .id = @intFromEnum(properties.weapon.ids[weapon_index]),
                                .level = properties.weapon.levels[weapon_index].toInt(),
                                .star = properties.weapon.stars[weapon_index].toInt(),
                                .refine_level = properties.weapon.refines[weapon_index].toInt(),
                            });
                        }

                        for (properties.avatar.equipment_uids[index]) |uid| {
                            const equip_uid = logic.Properties.Equipment.Uid.fromInt(uid.unwrap() orelse continue).?;
                            const equip_index = std.mem.findScalar(
                                logic.Properties.Equipment.Uid,
                                &properties.equip.uids,
                                equip_uid,
                            ).?;

                            equip_list.appendAssumeCapacity(try packers.packEquipmentInfo(
                                notify.allocator,
                                equip_uid,
                                properties.equip.ids[equip_index],
                                properties.equip.levels[equip_index],
                                properties.equip.stars[equip_index],
                                properties.equip.properties[equip_index],
                            ));
                        }
                    };

                    break :dungeon_package_info .{
                        .avatar_list = avatar_list,
                        .weapon_list = weapon_list,
                        .equip_list = equip_list,
                    };
                },
            },
        }),
    }
}

const templates = Assets.templates;

const Notify = notifiers.Notify;
const ArrayList = std.ArrayList;

const logic = @import("../../logic.zig");
const Assets = @import("../../Assets.zig");
const packers = @import("../packers.zig");
const notifiers = @import("../notifiers.zig");
const Properties = @import("../../logic/Properties.zig");

const pb = @import("rmpb").main;
const std = @import("std");
