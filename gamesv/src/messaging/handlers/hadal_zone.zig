const EntranceId = enum(u32) {
    hadal_zone_scheduled = 1,
    hadal_zone_stable = 2,
    hadal_zone_defensive = 3,
    boss_challenge_normal = 9,
    boss_challenge_hard = 16,

    pub fn entranceType(id: EntranceId) pb.EntranceType {
        return switch (id) {
            .hadal_zone_stable,
            .hadal_zone_defensive,
            => .CONSTANT,

            .hadal_zone_scheduled,
            .boss_challenge_normal,
            .boss_challenge_hard,
            => .SCHEDULED,
        };
    }
};

const configured_entrances = @import("config").hadal_zone_entrances;

pub fn getHadalZoneData(
    rtc: RealTimeClock,
    message: Message(pb.GetHadalZoneDataCsReq),
    response: Response(pb.GetHadalZoneDataScRsp),
) !void {
    _ = message;

    var entrance_list: ArrayList(pb.HadalEntranceInfo) = try .initCapacity(
        response.allocator,
        configured_entrances.len,
    );

    inline for (configured_entrances) |configured_entrance| {
        const id: EntranceId = configured_entrance.id;
        const zone_id = configured_entrance.zone;

        entrance_list.appendAssumeCapacity(.{
            .entrance_type = id.entranceType(),
            .entrance_id = @intFromEnum(id),
            .state = @enumFromInt(3),
            .cur_zone_record = .{
                .zone_id = zone_id,
                .begin_timestamp = switch (id.entranceType()) {
                    .NONE, .CONSTANT => 0,
                    .SCHEDULED => @intCast(rtc.time.toSeconds() - 3600 * 24),
                },
                .end_timestamp = switch (id.entranceType()) {
                    .NONE, .CONSTANT => 0,
                    .SCHEDULED => @intCast(rtc.time.toSeconds() + 3600 * 24 * 14),
                },
                .layer_record_list = layer_record_list: {
                    var list: ArrayList(pb.LayerRecord) = .empty;

                    for (templates.zone_info.entries) |zone_info| if (zone_info.zone_id == zone_id) {
                        try list.append(response.allocator, .{
                            .layer_index = zone_info.layer_index,
                            .status = @enumFromInt(4),
                        });
                    };

                    break :layer_record_list list;
                },
            },
        });
    }

    response.set(.{ .hadal_entrance_list = entrance_list });
}

const ArrayList = std.ArrayList;
const Message = handlers.Message;
const Response = handlers.Response;
const RealTimeClock = logic.RealTimeClock;

const templates = Assets.templates;

const pb = @import("rmpb").main;
const logic = @import("../../logic.zig");
const Assets = @import("../../Assets.zig");
const handlers = @import("../handlers.zig");
const std = @import("std");
