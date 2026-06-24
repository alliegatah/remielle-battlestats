const default_interact_target_list: []const pb.InteractTarget = &.{.InteractTarget_NPC};

pub fn switchGameMode(
    assets: *const Assets,
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
        .hall => |hall| notify.one(.{
            .scene = .{
                .scene_type = 1,
                .hall_scene_data = .{
                    .section_id = @intFromEnum(hall.section_id),
                    .control_avatar_id = properties.basic_info.control_avatar.toInt(),
                    .control_guise_avatar_id = properties.basic_info.control_guise_avatar.toInt(),
                    .npc_list = npc_list: {
                        const main_city = &assets.graphs.main_city;
                        const objects_template = &assets.configs.main_city_object;

                        const section_index = std.mem.findScalar(
                            u32,
                            main_city.sections,
                            @intFromEnum(hall.section_id),
                        ) orelse break :npc_list .empty;

                        var npc_id_list: ArrayList(u32) = .empty;
                        var npc_list: ArrayList(pb.NpcInfo) = .empty;

                        const event = &main_city.events[section_index];

                        for (main_city.actions[event.first_action..event.last_action]) |*action| switch (action.tag) {
                            .create_npc => {
                                const create_npc = action.data.create_npc;
                                const tmpl_index = objects_template.tag_ids.getIndex(create_npc.tag_id) orelse
                                    continue;

                                try npc_id_list.append(notify.allocator, create_npc.tag_id);

                                var npc_info: pb.NpcInfo = .{
                                    .npc_id = create_npc.tag_id,
                                    .is_active = true,
                                };

                                if (objects_template.default_interact_ids[tmpl_index] != 0) {
                                    const name = objects_template.interact_names[tmpl_index];

                                    try npc_info.interacts_info.append(notify.allocator, .{
                                        .key = objects_template.default_interact_ids[tmpl_index],
                                        .value = .{
                                            .tag_id = @intCast(create_npc.tag_id),
                                            .interact_target_list = .fromOwnedSlice(
                                                // constCast: this list won't be modified.
                                                @constCast(default_interact_target_list),
                                            ),
                                            .name = objects_template.getString(name),
                                            .scale_x = 1,
                                            .scale_y = 1,
                                            .scale_z = 1,
                                            .scale_w = 1,
                                            .scale_r = 1,
                                        },
                                    });
                                }

                                try npc_list.append(notify.allocator, npc_info);
                            },
                            .change_interact => {
                                const change_interact = &main_city.change_interact[action.data.change_interact.toIndex()];
                                const npc_index = std.mem.findScalar(
                                    u32,
                                    npc_id_list.items,
                                    change_interact.tag_id,
                                ) orelse continue;

                                const tmpl_index = objects_template.tag_ids.getIndex(change_interact.tag_id) orelse
                                    continue;

                                const name = objects_template.interact_names[tmpl_index];

                                // Clobber existing interact, if any.
                                npc_list.items[npc_index].interacts_info.items.len = 0;

                                try npc_list.items[npc_index].interacts_info.append(notify.allocator, .{
                                    .key = change_interact.interact_id,
                                    .value = .{
                                        .tag_id = @intCast(change_interact.tag_id),
                                        .interact_target_list = .fromOwnedSlice(
                                            // constCast: this list won't be modified.
                                            @constCast(default_interact_target_list),
                                        ),
                                        .name = objects_template.getString(name),
                                        .scale_x = 1,
                                        .scale_y = 1,
                                        .scale_z = 1,
                                        .scale_w = 1,
                                        .scale_r = 1,
                                    },
                                });
                            },
                            .switch_section, .open_ui => unreachable,
                        };

                        break :npc_list npc_list;
                    },
                },
            },
        }),
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
