main_city: MainCity,

pub fn load(io: Io, arena: Allocator) !Graphs {
    const cwd: Io.Dir = .cwd();
    const main_city_bytes = try cwd.readFileAllocOptions(
        io,
        "assets/graphs/main_city.remi",
        arena,
        .unlimited,
        .@"64",
        null,
    );

    return .{
        .main_city = .fromBytes(main_city_bytes),
    };
}

pub const Event = packed struct {
    first_action: u32,
    last_action: u32,
};

pub const Action = packed struct {
    const Tag = enum(u32) {
        create_npc = 1,
        change_interact = 2,
    };

    tag: Tag,
    index: u32,

    const CreateNpc = packed struct {
        tag_id: u32,
    };

    const ChangeInteract = packed struct {
        tag_id: u32,
        interact_id: u32,
    };
};

pub const MainCity = struct {
    sections: []const u32,
    events: [*]const Event,
    actions: [*]const Action,
    create_npc: [*]const Action.CreateNpc,
    change_interact: [*]const Action.ChangeInteract,

    const Header = packed struct {
        section_count: u32,
        sections_offset: u32,
        events_offset: u32,
        actions_offset: u32,
        create_npc_offset: u32,
        change_interact_offset: u32,
    };

    pub fn fromBytes(bytes: []const u8) MainCity {
        const header: *const Header = @ptrCast(@alignCast(bytes.ptr));

        return .{
            .sections = @ptrCast(@alignCast(
                bytes[header.sections_offset..][0 .. header.section_count * @sizeOf(u32)],
            )),
            .events = @ptrCast(@alignCast(bytes[header.events_offset..].ptr)),
            .actions = @ptrCast(@alignCast(bytes[header.actions_offset..].ptr)),
            .create_npc = @ptrCast(@alignCast(bytes[header.create_npc_offset..].ptr)),
            .change_interact = @ptrCast(@alignCast(bytes[header.change_interact_offset..].ptr)),
        };
    }
};

const Io = std.Io;
const Allocator = std.mem.Allocator;

const std = @import("std");
const Graphs = @This();
