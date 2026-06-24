main_city: MainCity,
interacts: Interacts,

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

    const interacts_bytes = try cwd.readFileAllocOptions(
        io,
        "assets/graphs/interacts.remi",
        arena,
        .unlimited,
        .@"64",
        null,
    );

    return .{
        .main_city = .fromBytes(main_city_bytes),
        .interacts = .fromBytes(interacts_bytes),
    };
}

pub const Event = packed struct {
    actions_begin: u32,
    actions_end: u32,
};

pub const Action = packed struct(u64) {
    tag: Tag,
    data: Data,

    const Tag = enum(u32) {
        create_npc = 1,
        change_interact = 2,
        switch_section = 3,
        open_ui = 4,
    };

    const Data = packed union(u32) {
        create_npc: CreateNpc,
        change_interact: ExtraIndex,
        switch_section: ExtraIndex,
        open_ui: ExtraIndex,
    };

    pub const ExtraIndex = enum(u32) {
        _,

        pub inline fn toIndex(ei: ExtraIndex) u32 {
            return @intFromEnum(ei);
        }
    };

    pub const CreateNpc = packed struct {
        tag_id: u32,
    };

    pub const ChangeInteract = packed struct {
        tag_id: u32,
        interact_id: u32,
    };

    const SwitchSection = packed struct {
        section_id: u32,
        transform_id: String,
        camera_x: u32,
        camera_y: u32,
    };

    const OpenUi = packed struct {
        ui: String,
        store_template_id: u32,
    };
};

pub const MainCity = struct {
    sections: []const u32,
    events: [*]const Event,
    actions: [*]const Action,
    change_interact: [*]const Action.ChangeInteract,

    const Header = packed struct {
        section_count: u32,
        sections_offset: u32,
        events_offset: u32,
        actions_offset: u32,
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
            .change_interact = @ptrCast(@alignCast(bytes[header.change_interact_offset..].ptr)),
        };
    }
};

pub const String = enum(u32) {
    empty = std.math.maxInt(u32),
    _,
};

pub const Interacts = struct {
    ids: []const u32,
    events: [*]const Event,
    actions: [*]const Action,
    change_interact: [*]const Action.ChangeInteract,
    switch_section: [*]const Action.SwitchSection,
    open_ui: [*]const Action.OpenUi,
    string_table: [*]const u8,

    const Header = packed struct {
        count: u32,
        ids_offset: u32,
        events_offset: u32,
        actions_offset: u32,
        change_interact_offset: u32,
        switch_section_offset: u32,
        open_ui_offset: u32,
        string_table_offset: u32,
    };

    pub fn getString(interacts: *const Interacts, string: String) [:0]const u8 {
        return switch (string) {
            .empty => "",
            _ => |index| std.mem.span(@as(
                [*:0]const u8,
                @ptrCast(interacts.string_table[@intFromEnum(index)..]),
            )),
        };
    }

    pub fn fromBytes(bytes: []const u8) Interacts {
        const header: *const Header = @ptrCast(@alignCast(bytes.ptr));

        return .{
            .ids = @ptrCast(@alignCast(
                bytes[header.ids_offset..][0 .. header.count * @sizeOf(u32)],
            )),
            .events = @ptrCast(@alignCast(bytes[header.events_offset..].ptr)),
            .actions = @ptrCast(@alignCast(bytes[header.actions_offset..].ptr)),
            .change_interact = @ptrCast(@alignCast(bytes[header.change_interact_offset..].ptr)),
            .switch_section = @ptrCast(@alignCast(bytes[header.switch_section_offset..].ptr)),
            .open_ui = @ptrCast(@alignCast(bytes[header.open_ui_offset..].ptr)),
            .string_table = @ptrCast(@alignCast(bytes[header.string_table_offset..].ptr)),
        };
    }
};

const Io = std.Io;
const Allocator = std.mem.Allocator;

const std = @import("std");
const Graphs = @This();
