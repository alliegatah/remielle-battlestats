pub fn mutateBasicInfo(
    changes: logic.Changes.Subset(.{
        logic.Changes.ControlAvatar,
        logic.Changes.ControlGuiseAvatar,
    }),
    properties: logic.Properties.Mutable(.{
        logic.Properties.BasicInfo,
    }),
) !void {
    if (changes.control_avatar) |control_avatar|
        properties.basic_info.control_avatar = control_avatar.*;

    if (changes.control_guise_avatar) |control_guise_avatar| {
        properties.basic_info.control_guise_avatar = control_guise_avatar.guise;
        properties.basic_info.control_guise_avatar_skin = control_guise_avatar.guise_skin;
    }
}

pub fn mutatePlayerAccessory(
    changes: logic.Changes.Subset(.{
        logic.Changes.PlayerAccessory,
    }),
    properties: logic.Properties.Mutable(.{
        logic.Properties.PlayerAccessory,
    }),
) !void {
    properties.player_accessory.meta.set(changes.player_accessory.?.avatar, changes.player_accessory.?.meta);
}

const logic = @import("../../logic.zig");
const mutators = @import("../mutators.zig");

const std = @import("std");
