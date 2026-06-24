pub fn enterWorld(
    message: Message(pb.EnterWorldCsReq),
    properties: Properties.Immutable(.{
        Properties.Hall,
    }),
    changes: Changes.Builder(.{
        Changes.GameMode,
    }),
    response: Response(pb.EnterWorldScRsp),
) !void {
    _ = message;

    const mode_switch: Changes.GameMode = .{ .hall = .{
        .section_id = properties.hall.section_id,
    } };

    changes.insert(mode_switch);
    response.set(.init);
}

pub fn leaveCurScene(
    message: Message(pb.LeaveCurSceneCsReq),
    properties: Properties.Immutable(.{
        Properties.Hall,
    }),
    changes: Changes.Builder(.{
        Changes.GameMode,
    }),
    response: Response(pb.LeaveCurSceneScRsp),
) !void {
    _ = message;

    const mode_switch: Changes.GameMode = .{ .hall = .{
        .section_id = properties.hall.section_id,
    } };

    changes.insert(mode_switch);
    response.set(.init);
}

pub fn enterSection(
    message: Message(pb.EnterSectionCsReq),
    changes: Changes.Builder(.{
        Changes.GameMode,
    }),
    response: Response(pb.EnterSectionScRsp),
) !void {
    // TODO: respect `transform` and `transform_id` parameters.

    const section_id = std.enums.fromInt(
        templates.section_config.Id,
        message.data.section_id,
    ) orelse return response.fail(1);

    const mode_switch: Changes.GameMode = .{ .hall = .{
        .section_id = section_id,
    } };

    changes.insert(mode_switch);
    response.set(.init);
}

pub fn interactWithUnit(
    assets: *const Assets,
    message: Message(pb.InteractWithUnitCsReq),
    changes: Changes.Builder(.{
        Changes.NpcInteraction,
    }),
    response: Response(pb.InteractWithUnitScRsp),
) !void {
    const interaction: Changes.NpcInteraction = .{
        .interact_index = @intCast(std.mem.findScalar(
            u32,
            assets.graphs.interacts.ids,
            @bitCast(message.data.interact_id),
        ) orelse
            return response.fail(1)),
    };

    changes.insert(interaction);
    response.set(.init);
}

pub fn enterSectionComplete(
    message: Message(pb.EnterSectionCompleteCsReq),
    response: Response(pb.EnterSectionCompleteScRsp),
) !void {
    _ = message;
    response.set(.init);
}

const Message = handlers.Message;
const Response = handlers.Response;

const Changes = logic.Changes;
const Properties = logic.Properties;

const templates = Assets.templates;

const logic = @import("../../logic.zig");
const Assets = @import("../../Assets.zig");
const handlers = @import("../handlers.zig");

const pb = @import("rmpb").main;
const std = @import("std");
