//! Thumbs-up (contribution) scores for the end-battle result screen, computed the way the official
//! server does.
//!
//! The official server derives them from the battle-statistics block the client sends in the fight
//! result, and returns them in the dungeon-completion notification (live CNOS 3.2: cmd 616, field 13,
//! entries {11: avatar_id ^ 0x1798, 8: score ^ 0x2D11}; CNBeta 3.3.4: cmd 3486, field 8). Reconstructed
//! from live 3.2 captures, this matches the official server's values for 39 of 39 agents in 13 fights,
//! and the in-game display for all 30 that were recorded:
//!
//!     damage_i  = agent damage + 1/2 x damage of summons naming agent i
//!     daze_i    = agent daze   + 1/2 x daze   of summons naming agent i
//!     score_i   = floor(1000 x damage_i  / team damage
//!                     + 1000 x daze_i    / team daze
//!                     + 1500 x assists_i / team assists)    <- only if the team made any assist
//!
//! So a team shares 3500 points (2000 when nobody assisted, e.g. solo runs), and flooring is why the
//! displayed totals come to 3498-3499. Anomaly buildup, healing and shields play no part.
//!
//! Summon entries count only when their owner field holds the agent's avatar id. Entries naming a
//! summon template instead are excluded; attributing those by template breaks the reconstruction.

/// Field numbers inside the fight result's battle-statistics block. The descriptor names the block
/// (`FightResult.PLHKKINHBFH`, field 6) but records no type for it, so the inner numbers are written
/// out here. Identical in live CNOS 3.2 and in the CNBeta 3.3.4 requests under `logs/`.
const stats = struct {
    const agents = 7;
    const summons = 20;
};
const unit = struct {
    const avatar_id = 1;
    const damage = 7;
    const daze = 13;
    const assists = 30;
};

const damage_points = 1000.0;
const daze_points = 1000.0;
const assist_points = 1500.0;
const summon_weight = 0.5;

/// Scores for `team` (avatar ids, any order), parallel to it. Agents absent from the statistics
/// block, or a request without one, score 0.
pub fn compute(
    arena: Allocator,
    end_battle_body: []const u8,
    team: []const u32,
) Allocator.Error![]u32 {
    const scores = try arena.alloc(u32, team.len);
    @memset(scores, 0);

    const totals = try arena.alloc(Totals, team.len);
    @memset(totals, .{});

    collect(end_battle_body, team, totals) catch |err| switch (err) {
        error.Malformed => {
            log.warn("malformed battle statistics; thumbs-up scores default to 0", .{});
            return scores;
        },
    };

    var team_total: Totals = .{};
    for (totals) |t| {
        team_total.damage += t.damage;
        team_total.daze += t.daze;
        team_total.assists += t.assists;
    }

    for (totals, scores) |t, *score| {
        var points: f64 = 0;
        if (team_total.damage > 0) points += damage_points * t.damage / team_total.damage;
        if (team_total.daze > 0) points += daze_points * t.daze / team_total.daze;
        if (team_total.assists > 0) points += assist_points * t.assists / team_total.assists;

        score.* = @intFromFloat(@floor(points + 1e-9));
    }

    return scores;
}

const Totals = struct {
    damage: f64 = 0,
    daze: f64 = 0,
    assists: f64 = 0,
};

fn collect(body: []const u8, team: []const u32, totals: []Totals) error{Malformed}!void {
    const fight_result = try findBytes(body, rmpb.main_desc.EndBattleCsReq.fight_result_field_desc.number) orelse
        return;
    const block = try findBytes(fight_result, rmpb.main_desc.FightResult.PLHKKINHBFH_field_desc.number) orelse
        return;

    var fields: Fields = .{ .bytes = block };
    while (try fields.next()) |field| {
        if (field.wire != .length_prefixed) continue;

        const weight: f64 = switch (field.number) {
            stats.agents => 1,
            stats.summons => summon_weight,
            else => continue,
        };

        const entry = try readUnit(field.bytes);
        const slot = std.mem.indexOfScalar(u32, team, entry.avatar_id) orelse continue;

        totals[slot].damage += weight * entry.damage;
        totals[slot].daze += weight * entry.daze;
        if (field.number == stats.agents) totals[slot].assists += entry.assists;
    }
}

const Unit = struct {
    avatar_id: u32 = 0,
    damage: f64 = 0,
    daze: f64 = 0,
    assists: f64 = 0,
};

fn readUnit(bytes: []const u8) error{Malformed}!Unit {
    var result: Unit = .{};
    var fields: Fields = .{ .bytes = bytes };

    while (try fields.next()) |field| {
        if (field.wire != .varint) continue;

        switch (field.number) {
            unit.avatar_id => result.avatar_id = std.math.cast(u32, field.varint) orelse return error.Malformed,
            unit.damage => result.damage = @floatFromInt(field.varint),
            unit.daze => result.daze = @floatFromInt(field.varint),
            unit.assists => result.assists = @floatFromInt(field.varint),
            else => {},
        }
    }

    return result;
}

/// First length-prefixed field `number` in `bytes`.
fn findBytes(bytes: []const u8, number: u32) error{Malformed}!?[]const u8 {
    var fields: Fields = .{ .bytes = bytes };
    while (try fields.next()) |field|
        if (field.number == number and field.wire == .length_prefixed) return field.bytes;

    return null;
}

/// Minimal protobuf field iterator over a byte slice.
const Fields = struct {
    bytes: []const u8,
    pos: usize = 0,

    const Wire = enum(u3) { varint = 0, fixed64 = 1, length_prefixed = 2, fixed32 = 5, _ };

    const Field = struct {
        number: u32,
        wire: Wire,
        varint: u64 = 0,
        bytes: []const u8 = &.{},
    };

    fn next(self: *Fields) error{Malformed}!?Field {
        if (self.pos >= self.bytes.len) return null;

        const key = try self.readVarint();
        const number = std.math.cast(u32, key >> 3) orelse return error.Malformed;
        var field: Field = .{ .number = number, .wire = @enumFromInt(@as(u3, @truncate(key))) };

        switch (field.wire) {
            .varint => field.varint = try self.readVarint(),
            .fixed64 => try self.skip(8),
            .fixed32 => try self.skip(4),
            .length_prefixed => {
                const len = std.math.cast(usize, try self.readVarint()) orelse return error.Malformed;
                const start = self.pos;
                try self.skip(len);
                field.bytes = self.bytes[start..self.pos];
            },
            _ => return error.Malformed,
        }

        return field;
    }

    fn readVarint(self: *Fields) error{Malformed}!u64 {
        var result: u64 = 0;
        var shift: u32 = 0;

        while (shift < 64) : (shift += 7) {
            if (self.pos >= self.bytes.len) return error.Malformed;
            const byte = self.bytes[self.pos];
            self.pos += 1;

            result |= std.math.shl(u64, byte & 0x7F, shift);
            if (byte < 0x80) return result;
        }

        return error.Malformed;
    }

    fn skip(self: *Fields, len: usize) error{Malformed}!void {
        if (len > self.bytes.len - self.pos) return error.Malformed;
        self.pos += len;
    }
};

const log = std.log.scoped(.@"remielle-gamesv::result-scores");

const Allocator = std.mem.Allocator;

const rmpb = @import("rmpb");
const std = @import("std");
