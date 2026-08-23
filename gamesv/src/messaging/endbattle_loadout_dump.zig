const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

const logic = @import("../logic.zig");
const Properties = logic.Properties;
const pb = @import("rmpb").main;

pub fn writeSidecar(
    io: Io,
    arena: Allocator,
    seq: u64,
    properties: *Properties.List,
    player_index: u32,
    message: *const pb.EndBattleCsReq,
) void {
    const json = formatSidecar(arena, seq, properties, player_index, message) catch return;

    const cwd = Io.Dir.cwd();
    cwd.createDirPath(io, "logs/") catch {};

    var path_buf: [80]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "logs/endbattle_{d}_loadout.json", .{seq}) catch return;

    const file = cwd.createFile(io, path, .{}) catch return;
    defer file.close(io);

    file.writeStreamingAll(io, json) catch {};
}

fn appendFmt(buf: *std.ArrayList(u8), arena: Allocator, comptime fmt: []const u8, args: anytype) !void {
    const slice = try std.fmt.allocPrint(arena, fmt, args);
    try buf.appendSlice(arena, slice);
}

fn formatSidecar(
    arena: Allocator,
    seq: u64,
    properties: *Properties.List,
    player_index: u32,
    message: *const pb.EndBattleCsReq,
) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(arena);

    const avatar_prop = properties.getPtr(.avatar, player_index);
    const weapon_prop = properties.getPtr(.weapon, player_index);
    const equip_prop = properties.getPtr(.equip, player_index);
    const quick_team = properties.getPtr(.quick_team, player_index);

    const resolved = try resolveAvatarIds(arena, message.fight_result, avatar_prop, quick_team);

    try appendFmt(&buf, arena, "{{\n  \"seq\": {d},\n  \"avatar_id_source\": \"{s}\",\n  \"avatars\": [", .{
        seq,
        resolved.source,
    });

    for (resolved.ids, 0..) |avatar_id, index| {
        if (index != 0) try buf.appendSlice(arena, ",");

        try appendFmt(&buf, arena, "\n    {{\n      \"avatar_id\": {d}", .{avatar_id});

        const avatar_id_enum = std.enums.fromInt(Properties.Avatar.Id, avatar_id) orelse {
            try buf.appendSlice(arena, ",\n      \"weapon\": null,\n      \"drive_discs\": []\n    }");
            continue;
        };

        const avatar_index = avatar_prop.indexes.get(avatar_id_enum) orelse {
            try buf.appendSlice(arena, ",\n      \"weapon\": null,\n      \"drive_discs\": []\n    }");
            continue;
        };

        try buf.appendSlice(arena, ",\n      ");
        try appendWeaponJson(&buf, arena, avatar_prop, weapon_prop, avatar_index);

        try buf.appendSlice(arena, ",\n      ");
        try appendDriveDiscsJson(&buf, arena, avatar_prop, equip_prop, avatar_index);

        try buf.appendSlice(arena, "\n    }");
    }

    try buf.appendSlice(arena, "\n  ]\n}\n");
    return buf.toOwnedSlice(arena);
}

const ResolvedAvatarIds = struct {
    ids: []const u32,
    source: []const u8,
};

fn resolveAvatarIds(
    arena: Allocator,
    fight_result: ?pb.FightResult,
    avatar_prop: *const Properties.Avatar,
    quick_team: *const Properties.QuickTeam,
) !ResolvedAvatarIds {
    var ids: std.ArrayList(u32) = .empty;

    if (fight_result) |result| {
        try collectAvatarIdsFromFightResult(&ids, arena, &result);
        if (ids.items.len > 0)
            return .{ .ids = ids.items, .source = "fight_result" };
    }

    try collectAvatarIdsFromQuickTeam(&ids, arena, quick_team);
    if (ids.items.len > 0)
        return .{ .ids = ids.items, .source = "quick_team" };

    try collectAvatarIdsFromEquippedRoster(&ids, arena, avatar_prop);
    return .{
        .ids = ids.items,
        .source = if (ids.items.len > 0) "equipped_roster" else "none",
    };
}

fn appendUnique(list: *std.ArrayList(u32), arena: Allocator, id: u32) !void {
    if (id == 0) return;
    for (list.items) |existing| if (existing == id) return;
    try list.append(arena, id);
}

fn collectFromAvatarRecords(
    list: *std.ArrayList(u32),
    arena: Allocator,
    entries: []const pb.PAIBIAOMCOE,
) !void {
    for (entries) |entry| {
        if (entry.avatar_id <= 0) continue;
        try appendUnique(list, arena, @intCast(entry.avatar_id));
    }
}

fn collectAvatarIdsFromFightResult(
    list: *std.ArrayList(u32),
    arena: Allocator,
    fight_result: *const pb.FightResult,
) !void {
    if (fight_result.battle_data_record) |record| {
        for (record.avatar_member_list.items) |member|
            try appendUnique(list, arena, member.avatar_id);
    }

    for (fight_result.NOKNHMFIACN.items) |member|
        try appendUnique(list, arena, member.avatar_id);

    for (fight_result.JAOJPCNEJJN.items) |avatar_id|
        try appendUnique(list, arena, avatar_id);

    for (fight_result.LCFEMDLMBJK.items) |avatar_id|
        try appendUnique(list, arena, avatar_id);

    for (fight_result.OIPDEJGLKGC.items) |entry|
        try appendUnique(list, arena, entry.key);

    if (fight_result.PLFBHFOCHOM) |detail| {
        try collectFromAvatarRecords(list, arena, detail.avatar_list.items);
        try collectFromAvatarRecords(list, arena, detail.MCLOEDEJGDD.items);
        try collectFromAvatarRecords(list, arena, detail.BNMCPGLDACG.items);
        try collectFromAvatarRecords(list, arena, detail.MNEOGNAKJJE.items);
    }
}

fn collectAvatarIdsFromQuickTeam(
    list: *std.ArrayList(u32),
    arena: Allocator,
    quick_team: *const Properties.QuickTeam,
) !void {
    for (&quick_team.meta) |*team| {
        var found_any = false;

        for (team.avatar_ids) |optional_id| {
            if (optional_id.unwrap()) |avatar_id| {
                try appendUnique(list, arena, avatar_id);
                found_any = true;
            }
        }

        if (found_any) return;
    }
}

fn collectAvatarIdsFromEquippedRoster(
    list: *std.ArrayList(u32),
    arena: Allocator,
    avatar_prop: *const Properties.Avatar,
) !void {
    const avatar_count = avatar_prop.indexes.count();

    for (avatar_prop.ids[0..avatar_count], 0..) |id, index| {
        const has_weapon = avatar_prop.weapon_uids[index].unwrap() != null;
        var has_equipment = false;

        for (avatar_prop.equipment_uids[index]) |optional_uid| {
            if (optional_uid.unwrap() != null) {
                has_equipment = true;
                break;
            }
        }

        if (has_weapon or has_equipment)
            try appendUnique(list, arena, @intFromEnum(id));
    }
}

fn appendWeaponJson(
    buf: *std.ArrayList(u8),
    arena: Allocator,
    avatar_prop: *const Properties.Avatar,
    weapon_prop: *const Properties.Weapon,
    avatar_index: u32,
) !void {
    const weapon_uid_int = avatar_prop.weapon_uids[avatar_index].unwrap() orelse {
        try buf.appendSlice(arena, "\"weapon\": null");
        return;
    };

    const weapon_uid = Properties.Weapon.Uid.fromInt(weapon_uid_int) orelse {
        try buf.appendSlice(arena, "\"weapon\": null");
        return;
    };

    const weapon_index = std.mem.findScalar(
        Properties.Weapon.Uid,
        weapon_prop.uids[0..weapon_prop.count],
        weapon_uid,
    ) orelse {
        try buf.appendSlice(arena, "\"weapon\": null");
        return;
    };

    try appendFmt(
        buf,
        arena,
        "\"weapon\": {{ \"uid\": {d}, \"id\": {d}, \"level\": {d}, \"star\": {d}, \"refine\": {d} }}",
        .{
            weapon_uid_int,
            @intFromEnum(weapon_prop.ids[weapon_index]),
            weapon_prop.levels[weapon_index].toInt(),
            weapon_prop.stars[weapon_index].toInt(),
            weapon_prop.refines[weapon_index].toInt(),
        },
    );
}

fn appendDriveDiscsJson(
    buf: *std.ArrayList(u8),
    arena: Allocator,
    avatar_prop: *const Properties.Avatar,
    equip_prop: *const Properties.Equipment,
    avatar_index: u32,
) !void {
    try buf.appendSlice(arena, "\"drive_discs\": [");

    var wrote_one = false;
    for (avatar_prop.equipment_uids[avatar_index], 0..) |optional_uid, slot_index| {
        const equip_uid_int = optional_uid.unwrap() orelse continue;

        const equip_uid = Properties.Equipment.Uid.fromInt(equip_uid_int) orelse continue;
        const equip_index = std.mem.findScalar(
            Properties.Equipment.Uid,
            equip_prop.uids[0..equip_prop.count],
            equip_uid,
        ) orelse continue;

        if (wrote_one) try buf.appendSlice(arena, ",") else wrote_one = true;

        try appendFmt(
            buf,
            arena,
            "\n        {{ \"slot\": {d}, \"uid\": {d}, \"id\": {d}, \"level\": {d}, \"star\": {d}, \"properties\": [",
            .{
                slot_index + 1,
                equip_uid_int,
                equip_prop.ids[equip_index],
                equip_prop.levels[equip_index].toInt(),
                equip_prop.stars[equip_index].toInt(),
            },
        );

        var wrote_property = false;
        for (equip_prop.properties[equip_index]) |property| {
            const key = property.key.unwrap() orelse continue;

            if (wrote_property) try buf.appendSlice(arena, ",") else wrote_property = true;
            try appendFmt(
                buf,
                arena,
                "\n          {{ \"key\": {d}, \"base_value\": {d}, \"add_value\": {d} }}",
                .{ key, property.base_value, property.add_value },
            );
        }

        try buf.appendSlice(arena, "\n        ] }");
    }

    if (wrote_one) try buf.appendSlice(arena, "\n      ]") else try buf.appendSlice(arena, "]");
}
