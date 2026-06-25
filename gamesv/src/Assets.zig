pub const templates = @import("Assets/templates.zig");
pub const graphs = @import("Assets/graphs.zig");

main_city_object_map: templates.main_city_object.Map,

pub fn init(gpa: Allocator) !Assets {
    return .{
        .main_city_object_map = try templates.main_city_object.createMap(gpa),
    };
}

pub fn deinit(assets: *Assets, gpa: Allocator) void {
    assets.main_city_object_map.deinit(gpa);
}

const Allocator = std.mem.Allocator;

const std = @import("std");
const Assets = @This();
