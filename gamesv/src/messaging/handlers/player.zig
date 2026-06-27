pub fn playerLogin(
    message: Message(pb.PlayerLoginCsReq),
    response: Response(pb.PlayerLoginScRsp),
) !void {
    _ = message;
    response.set(.init);
}

pub fn keepAlive(message: Message(pb.KeepAliveNotify)) !void {
    _ = message;
}

pub fn getSelfBasicInfo(
    message: Message(pb.GetSelfBasicInfoCsReq),
    properties: Properties.Immutable(.{
        Properties.BasicInfo,
    }),
    response: Response(pb.GetSelfBasicInfoScRsp),
) !void {
    _ = message;

    response.set(.{ .self_basic_info = try packers.packSelfBasicInfo(
        response.allocator,
        properties.basic_info,
    ) });
}

pub fn modAvatar(
    message: Message(pb.ModAvatarCsReq),
    properties: Properties.Immutable(.{
        Properties.BasicInfo,
        Properties.Avatar,
    }),
    changes: Changes.Builder(.{
        Changes.ControlAvatar,
        Changes.ControlGuiseAvatar,
    }),
    response: Response(pb.ModAvatarScRsp),
) !void {
    const new_control_avatar = Properties.HallAvatar.fromInt(message.data.control_avatar_id) orelse
        return response.fail(1);

    const new_guise = Properties.HallAvatar.Guise.fromRawId(
        properties.avatar,
        message.data.control_guise_avatar_id,
    ) catch |err| return switch (err) {
        error.InvalidAvatarId,
        error.AvatarNotUnlocked,
        => response.fail(1),
    };

    if (properties.basic_info.control_avatar != new_control_avatar)
        changes.insert(new_control_avatar);

    if (properties.basic_info.control_guise_avatar != new_guise)
        changes.insert(Changes.ControlGuiseAvatar{
            .guise = new_guise,
            .guise_skin = new_guise.getSkin(properties.avatar),
        });

    response.set(.init);
}

const Message = handlers.Message;
const Response = handlers.Response;

const Changes = logic.Changes;
const Properties = logic.Properties;

const templates = Assets.templates;

const pb = @import("rmpb").main;
const logic = @import("../../logic.zig");
const packers = @import("../packers.zig");
const Assets = @import("../../Assets.zig");
const handlers = @import("../handlers.zig");
