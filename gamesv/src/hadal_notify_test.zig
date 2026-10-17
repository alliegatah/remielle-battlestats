//! Protocol-level coverage for the end-battle completion notification.
//!
//! The contribution values in that notification are computed from the battle statistics
//! (`result_scores.zig`) and can be overridden by the manual score file; both are exercised here.

const std = @import("std");

const rmpb = @import("rmpb");
const scores = @import("messaging/manual_result_scores.zig");
const result_scores = @import("messaging/result_scores.zig");

// Field numbers come from the 3.3.4 wire descriptor.
const IEKEBLNBCPN = rmpb.main_desc.IEKEBLNBCPN;
const PJKDEPHMICK = rmpb.main_desc.PJKDEPHMICK;

const allocate = std.heap.smp_allocator;

/// Encodes `message` into `buffer` and returns the written prefix.
fn encodeMessage(
    comptime desc_set: rmpb.Descriptors,
    buffer: []u8,
    message: anytype,
) []const u8 {
    var writer: std.Io.Writer = .fixed(buffer);
    rmpb.encode(desc_set, &writer, message) catch unreachable;

    return writer.buffered();
}

fn decodeMessage(
    comptime desc_set: rmpb.Descriptors,
    comptime Message: type,
    bytes: []const u8,
) rmpb.DecodeError!Message {
    var reader: std.Io.Reader = .fixed(bytes);
    return rmpb.decode(desc_set, Message, allocate, &reader);
}

test "3.3.4 completion notification descriptor facts" {
    try std.testing.expectEqual(@as(u16, 3486), IEKEBLNBCPN.cmd_id);
    try std.testing.expectEqual(@as(u16, 3486), rmpb.cmdId(rmpb.main.IEKEBLNBCPN).?);

    // Contribution list: repeated field 8, no scalar XOR.
    try std.testing.expectEqual(@as(u32, 8), IEKEBLNBCPN.JBCOFFADDGJ_field_desc.number);
    try std.testing.expectEqual(@as(u32, 0), IEKEBLNBCPN.JBCOFFADDGJ_field_desc.xor);

    // Record: avatar_id field 1 XOR 0, contribution score field 2 XOR 0.
    try std.testing.expectEqual(@as(u32, 1), PJKDEPHMICK.avatar_id_field_desc.number);
    try std.testing.expectEqual(@as(u32, 0), PJKDEPHMICK.avatar_id_field_desc.xor);
    try std.testing.expectEqual(@as(u32, 2), PJKDEPHMICK.JCCBJCMEKJI_field_desc.number);
    try std.testing.expectEqual(@as(u32, 0), PJKDEPHMICK.JCCBJCMEKJI_field_desc.xor);

    try std.testing.expectEqualStrings("IEKEBLNBCPN", rmpb.main.IEKEBLNBCPN.pb_desc_name);
    try std.testing.expectEqualStrings("PJKDEPHMICK", rmpb.main.PJKDEPHMICK.pb_desc_name);
}

test "completion notification carries one record per avatar, in order" {
    var contributions: std.ArrayList(rmpb.main.PJKDEPHMICK) = .empty;
    defer contributions.deinit(allocate);

    try contributions.append(allocate, .{ .avatar_id = 1011, .JCCBJCMEKJI = 1500 });
    try contributions.append(allocate, .{ .avatar_id = 1032, .JCCBJCMEKJI = 2000 });
    try contributions.append(allocate, .{ .avatar_id = 1381, .JCCBJCMEKJI = 667 });

    const notify: rmpb.main.IEKEBLNBCPN = .{ .JBCOFFADDGJ = contributions };

    var buffer: [128]u8 = undefined;
    const bytes = encodeMessage(.main, &buffer, notify);

    try std.testing.expectEqualSlices(u8, &.{
        // tag(8, length-prefixed)
        0x42, 0x06, 0x08, 0xF3, 0x07, 0x10, 0xDC, 0x0B, // avatar 1011, score 1500
        0x42, 0x06, 0x08, 0x88, 0x08, 0x10, 0xD0, 0x0F, // avatar 1032, score 2000
        0x42, 0x06, 0x08, 0xE5, 0x0A, 0x10, 0x9B, 0x05, // avatar 1381, score 667
    }, bytes);

    const decoded = try decodeMessage(.main, rmpb.main.IEKEBLNBCPN, bytes);
    try std.testing.expectEqual(@as(usize, 3), decoded.JBCOFFADDGJ.items.len);

    const expected_avatar_ids = [_]u32{ 1011, 1032, 1381 };
    const expected_scores = [_]u32{ 1500, 2000, 667 };

    for (decoded.JBCOFFADDGJ.items, expected_avatar_ids, expected_scores) |record, avatar_id, score| {
        try std.testing.expectEqual(avatar_id, record.avatar_id);
        try std.testing.expectEqual(score, record.JCCBJCMEKJI);
    }
}

test "an empty completion notification has no body" {
    var buffer: [8]u8 = undefined;
    const bytes = encodeMessage(.main, &buffer, rmpb.main.IEKEBLNBCPN.init);

    try std.testing.expectEqual(@as(usize, 0), bytes.len);
}

test "manifest: slot scores, avatar scores, precedence and ignored lines" {
    const parsed = scores.parse(
        \\# result slot scores
        \\1 1500
        \\2 2000
        \\
        \\3 667
        \\
        \\# an explicit avatar id wins over the slot score
        \\1011 4242
        \\1011 9999
        \\
        \\abc 5
        \\5
        \\6 6 6
        \\7 not-a-score
        \\  8   800  
    );

    try std.testing.expectEqual(@as(usize, 6), parsed.count);

    // Slots are 1-based in the extracted/displayed team order.
    try std.testing.expectEqual(@as(u32, 1500), scores.get(undefined, &parsed, 9_999_999, 1));
    try std.testing.expectEqual(@as(u32, 800), scores.get(undefined, &parsed, 9_999_999, 8));

    // Missing entries default to zero.
    try std.testing.expectEqual(@as(u32, 0), scores.get(undefined, &parsed, 9_999_999, 0));
    try std.testing.expectEqual(@as(u32, 0), scores.get(undefined, &parsed, 9_999_999, 5));

    // The first explicit avatar id wins.
    try std.testing.expectEqual(@as(u32, 4242), scores.get(undefined, &parsed, 1011, 1));

    const team = [_]u32{ 1011, 9_999_999, 1234 };
    try std.testing.expectEqual(@as(u32, 4242), scores.getForBattleAvatar(undefined, &parsed, &team, 1011));
    try std.testing.expectEqual(@as(u32, 2000), scores.getForBattleAvatar(undefined, &parsed, &team, 9_999_999));
    try std.testing.expectEqual(@as(u32, 667), scores.getForBattleAvatar(undefined, &parsed, &team, 1234));
}

test "manifest: missing or empty file defaults every result to zero" {
    try std.testing.expectEqual(@as(usize, 0), scores.parse("").count);
    try std.testing.expectEqual(@as(u32, 0), scores.get(undefined, &scores.parse(""), 1011, 1));
}

/// Minimal EndBattleCsReq bodies built from live CNOS 3.2 fights: field 9 (fight result) -> field 6
/// (battle statistics) holding only the agent and summon fields the formula reads, plus one summon
/// entry that names a summon template instead of an agent (which must be ignored). Expected values
/// are the thumbs-up scores shown in game.
const live_fights = [_]struct { hex: []const u8, team: [3]u32, shown: [3]u32 }{
    .{ // Harumasa / Norma / Astra Yao: Norma's summons, assists by both attackers -> 3500
        .hex = "4a5432523a0e08b10938a3b68d0b68d15ef001043a0f08a30c38bdf4cc0b68eccd04f001043a0a089f0a38e8f346689004a2010608a30c68c14da2010608a30c68a948a2010508a30c6840a2010808afe5fa5e688827",
        .team = .{ 1201, 1571, 1311 },
        .shown = .{ 1351, 2119, 29 },
    },
    .{ // Ye Shunguang / Dialyn / Sunna: no assists -> 2000
        .hex = "4a3c323a3a0a08c90b389d927468ca473a0b08970b38c99f871a68f80c3a0a08d30b38b3e11868ba13a2010708d30b38b6b201a2010808afe5fa5e688827",
        .team = .{ 1481, 1431, 1491 },
        .shown = .{ 721, 1083, 194 },
    },
    .{ // Claret / Qingyi / Rina: Rina's summons, team listed out of block order
        .hex = "4a4832463a0e08cb0c3897c6bb5368a462f001033a0c08e30938f78f930368cf86023a0a08bb0938b7b46768c633a2010608bb0968e618a2010508bb09687da2010808afe5fa5e688827",
        .team = .{ 1211, 1611, 1251 },
        .shown = .{ 160, 2685, 653 },
    },
};

test "thumbs-up scores reproduce live result screens" {
    var arena_state: std.heap.ArenaAllocator = .init(allocate);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    for (live_fights) |fight| {
        var body: [256]u8 = undefined;
        const bytes = try std.fmt.hexToBytes(&body, fight.hex);

        const computed = try result_scores.compute(arena, bytes, &fight.team);
        try std.testing.expectEqualSlices(u32, &fight.shown, computed);
    }
}

test "thumbs-up scores: requests without statistics or with garbage score zero" {
    var arena_state: std.heap.ArenaAllocator = .init(allocate);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const team = [_]u32{ 1011, 1032 };
    try std.testing.expectEqualSlices(u32, &.{ 0, 0 }, try result_scores.compute(arena, "", &team));
    try std.testing.expectEqualSlices(u32, &.{ 0, 0 }, try result_scores.compute(arena, "\x4a\x7f\x01", &team));
    try std.testing.expectEqualSlices(u32, &.{ 0, 0 }, try result_scores.compute(arena, "\xff\xff\xff", &team));
}

test "manual entries override computed scores only where present" {
    const overrides = scores.parse(
        \\2 777
    );
    const team = [_]u32{ 1201, 1571, 1311 };

    try std.testing.expectEqual(@as(?u32, null), scores.findForBattleAvatar(&overrides, &team, 1201));
    try std.testing.expectEqual(@as(?u32, 777), scores.findForBattleAvatar(&overrides, &team, 1571));
    try std.testing.expectEqual(@as(?u32, null), scores.findForBattleAvatar(&overrides, &team, 1311));
}

test "manifest: stops at the entry cap" {
    var buffer: [scores.max_entries * 8]u8 = undefined;
    var length: usize = 0;

    for (1..scores.max_entries + 10) |slot| {
        const line = try std.fmt.bufPrint(buffer[length..], "{d} 1\n", .{slot});
        length += line.len;
    }

    const parsed = scores.parse(buffer[0..length]);
    try std.testing.expectEqual(@as(usize, scores.max_entries), parsed.count);
}
