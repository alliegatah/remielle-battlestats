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

        .training, .hadal_zone => {},
    }
}

pub fn mutateMainCityTime(
    changes: logic.Changes.Subset(.{
        logic.Changes.MainCityTime,
    }),
    properties: logic.Properties.Mutable(.{
        logic.Properties.MainCityTime,
    }),
) !void {
    properties.main_city_time.time_in_minutes = changes.main_city_time.?.time_in_minutes;
    properties.main_city_time.day_of_week = changes.main_city_time.?.day_of_week;
}

const logic = @import("../../logic.zig");
const mutators = @import("../mutators.zig");
