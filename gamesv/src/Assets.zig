pub const templates = @import("Assets/templates.zig");
pub const Graphs = @import("Assets/Graphs.zig");

graphs: Graphs,
main_city_object_map: templates.main_city_object.Map,
arena: ArenaAllocator,

pub fn load(io: std.Io, gpa: std.mem.Allocator) !Assets {
    var arena: ArenaAllocator = .init(gpa);
    errdefer arena.deinit();

    return .{
        .graphs = try Graphs.load(io, arena.allocator()),
        .main_city_object_map = try templates.main_city_object.createMap(arena.allocator()),
        .arena = arena,
    };
}

pub fn deinit(assets: *Assets) void {
    assets.arena.deinit();
}

const ArenaAllocator = std.heap.ArenaAllocator;

const std = @import("std");
const Assets = @This();
