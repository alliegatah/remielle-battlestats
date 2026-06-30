pub fn mutateQuickTeam(
    changes: logic.Changes.Subset(.{
        logic.Changes.QuickTeam,
    }),
    properties: logic.Properties.Mutable(.{
        logic.Properties.QuickTeam,
    }),
) !void {
    for (changes.quick_teams) |change|
        properties.quick_team.meta[change.slot.toIndex()] = change.meta;
}

const logic = @import("../../logic.zig");
const mutators = @import("../mutators.zig");
const std = @import("std");
