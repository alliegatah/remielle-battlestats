pub const templates = @import("Assets/templates.zig");
pub const Graphs = @import("Assets/Graphs.zig");
pub const BinConfigs = @import("Assets/BinConfigs.zig");

graphs: Graphs,
configs: BinConfigs,
arena: ArenaAllocator,

pub fn load(io: std.Io, gpa: std.mem.Allocator) !Assets {
    var arena: ArenaAllocator = .init(gpa);
    errdefer arena.deinit();

    return .{
        .graphs = try Graphs.load(io, arena.allocator()),
        .configs = try BinConfigs.load(io, arena.allocator()),
        .arena = arena,
    };
}

pub fn deinit(assets: *Assets) void {
    assets.arena.deinit();
}

const ArenaAllocator = std.heap.ArenaAllocator;

const std = @import("std");
const Assets = @This();
