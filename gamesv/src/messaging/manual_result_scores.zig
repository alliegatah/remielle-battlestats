//! Manual overrides for the thumbs-up display scores on the end-battle result screen.
//!
//! Scores are normally computed from the battle statistics by `result_scores.zig`, which reproduces
//! the official server's values. An entry here replaces the computed score for that avatar or slot; agents
//! with no entry keep the computed score. The file is `manual-result-scores.txt`, read relative to
//! the server's working directory every time a battle completes, so edits apply to subsequent
//! results without restarting the server.
//!
//! Each non-empty, non-`#` line is either
//!
//!     <result_slot> <score>
//!
//! where `result_slot` is 1-based in the extracted (displayed) team order, or
//!
//!     <avatar_id> <score>
//!
//! An explicit avatar id takes precedence over a slot score. Unknown lines and unparseable
//! numbers are ignored; missing entries default to zero.

const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const file_name = "manual-result-scores.txt";
pub const max_file_size: Io.Limit = .limited(1 << 20);
pub const max_entries = 64;

const Entry = union(enum) {
    slot: u32,
    avatar: u32,
};

pub const Scores = struct {
    const empty: Scores = .{
        .entries = @splat(.{ .slot = 0 }),
        .scores = @splat(0),
        .count = 0,
    };

    entries: [max_entries]Entry,
    /// Parallel to `entries`; 0 means "not configured", which is also the default display value.
    scores: [max_entries]u32,
    count: usize,
};

/// Reads `manual-result-scores.txt` from the server's working directory.
///
/// A missing or unreadable file yields an empty `Scores`, so every result defaults to zero.
/// `arena` only backs the temporary file contents; the returned `Scores` owns no allocations.
pub fn load(arena: Allocator, io: Io) Scores {
    const bytes = Io.Dir.cwd().readFileAllocOptions(
        io,
        file_name,
        arena,
        max_file_size,
        .of(u8),
        null,
    ) catch |err| switch (err) {
        error.FileNotFound => return .empty,
        else => |e| {
            log.warn("failed to read {s}: {t}", .{ file_name, e });
            return .empty;
        },
    };

    return parse(bytes);
}

/// Parses the file format described in the module documentation.
pub fn parse(bytes: []const u8) Scores {
    var scores: Scores = .empty;
    var lines = std.mem.tokenizeAny(u8, bytes, "\r\n");

    while (lines.next()) |raw_line| {
        if (scores.count == max_entries) break;

        const line = std.mem.trim(u8, raw_line, " \t");
        if (line.len == 0 or line[0] == '#') continue;

        var fields = std.mem.tokenizeAny(u8, line, " \t");
        const key_text = fields.next() orelse continue;
        const score_text = fields.next() orelse continue;
        if (fields.next() != null) continue; // trailing garbage: ignore the whole line

        const key = std.fmt.parseUnsigned(u32, key_text, 10) catch continue;
        const score = std.fmt.parseUnsigned(u32, score_text, 10) catch continue;

        scores.entries[scores.count] = if (isAvatarId(key))
            .{ .avatar = key }
        else
            .{ .slot = key };

        scores.scores[scores.count] = score;
        scores.count += 1;
    }

    return scores;
}

/// Avatar ids are 4-digit identifiers (`templates.avatar_base.Id`); result slots are 1-based and
/// small, so a value with 3 or more digits can never be a slot.
fn isAvatarId(key: u32) bool {
    return key >= 100;
}

/// Resolves the configured score for one result avatar.
///
/// An explicit avatar id wins over a slot score, and an absent entry defaults to zero.
pub fn get(
    frame: *const Frame,
    scores: *const Scores,
    avatar_id: u32,
    slot: u32,
) u32 {
    _ = frame;
    return find(scores, avatar_id, slot) orelse 0;
}

/// The configured score for one result avatar, or `null` when the file has no entry for it.
pub fn find(scores: *const Scores, avatar_id: u32, slot: u32) ?u32 {
    var slot_score: ?u32 = null;

    for (scores.entries[0..scores.count], scores.scores[0..scores.count]) |entry, score| switch (entry) {
        .avatar => |entry_id| if (entry_id == avatar_id) return score,
        .slot => |entry_slot| if (entry_slot == slot) {
            slot_score = score;
        },
    };

    return slot_score;
}

/// Same as `find`, resolving the 1-based result slot from the extracted battle avatar ids.
pub fn findForBattleAvatar(scores: *const Scores, team: []const u32, avatar_id: u32) ?u32 {
    const slot = std.mem.indexOfScalar(u32, team, avatar_id) orelse return find(scores, avatar_id, 0);
    return find(scores, avatar_id, @intCast(slot + 1));
}

/// Same as `get`, resolving the result slot from the extracted battle avatar ids.
pub fn getForBattleAvatar(
    frame: *const Frame,
    scores: *const Scores,
    team: []const u32,
    avatar_id: u32,
) u32 {
    for (team, 1..) |team_avatar_id, slot|
        if (team_avatar_id == avatar_id)
            return get(frame, scores, avatar_id, @intCast(slot));

    return get(frame, scores, avatar_id, 0);
}

pub const Frame = struct {
    /// Server working directory, where `manual-result-scores.txt` is read from.
    io: Io,
    /// Same as `Server.Frame.properties`.
    properties: *logic.Properties.List,
    /// Same as `Server.Frame.target_index`.
    player_index: u32,
};

const log = std.log.scoped(.@"remielle-gamesv::manual-result-scores");

const logic = @import("../logic.zig");
