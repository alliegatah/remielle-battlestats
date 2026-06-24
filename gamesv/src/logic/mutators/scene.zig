pub fn mutateHall(
    changes: logic.Changes.Subset(.{
        logic.Changes.GameMode,
    }),
    properties: logic.Properties.Mutable(.{
        logic.Properties.Hall,
    }),
) !void {
    switch (changes.game_mode.?) {
        .hall => |hall| {
            properties.hall.section_id = hall.section_id;
        },

        .training => {},
    }
}

const logic = @import("../../logic.zig");
const mutators = @import("../mutators.zig");
