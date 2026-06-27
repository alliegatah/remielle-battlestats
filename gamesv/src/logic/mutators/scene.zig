pub fn mutateHall(
    changes: logic.Changes.Subset(.{
        logic.Changes.GameMode,
        logic.Changes.PosInMainCity,
    }),
    properties: logic.Properties.Mutable(.{
        logic.Properties.Hall,
    }),
) !void {
    if (changes.game_mode) |game_mode| switch (game_mode.*) {
        .hall => |hall| {
            properties.hall.section_id = hall.section_id;
            properties.hall.position = hall.position;
        },

        .training, .hadal_zone => {},
    };

    if (changes.pos_in_main_city) |pos_in_main_city|
        properties.hall.position = pos_in_main_city.new_position;
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
