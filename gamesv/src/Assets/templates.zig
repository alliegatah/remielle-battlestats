pub const avatar_base = @import("templates/avatar_base.zig");
pub const avatar_skin_base = @import("templates/avatar_skin_base.zig");
pub const unlock_config = @import("templates/unlock_config.zig");
pub const post_girl_config = @import("templates/post_girl_config.zig");
pub const section_config = @import("templates/section_config.zig");
pub const yorozuya_level = @import("templates/yorozuya_level.zig");
pub const training_quest = @import("templates/training_quest.zig");
pub const weapon = @import("templates/weapon.zig");
pub const urban_area_map = @import("templates/urban_area_map.zig");
pub const urban_area_map_group = @import("templates/urban_area_map_group.zig");
pub const teleport_config = @import("templates/teleport_config.zig");

pub const Property = struct {
    property: u32,
    value: i32,
};

pub const ItemCount = struct {
    item_id: u32,
    number: u32,
};

pub const equipment = @import("templates/equipment.zig");
