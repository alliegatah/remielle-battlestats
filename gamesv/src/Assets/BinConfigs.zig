main_city_object: MainCityObjectTemplateTb,

pub fn load(io: Io, arena: Allocator) !BinConfig {
    const cwd: Io.Dir = .cwd();
    const bytes = try cwd.readFileAllocOptions(
        io,
        "assets/bincfg/main_city_object_template_tb.remi",
        arena,
        .unlimited,
        .@"64",
        null,
    );

    return .{
        .main_city_object = try .fromBytes(arena, bytes),
    };
}

pub const String = enum(u32) {
    empty = std.math.maxInt(u32),
    _,
};

pub const MainCityObjectTemplateTb = struct {
    const TagMap = std.array_hash_map.Auto(u32, void);

    tag_ids: TagMap,
    default_interact_ids: []const u32,
    interact_names: []const String,
    string_table: [*]const u8,

    const Header = packed struct {
        count: u32,
        tag_ids_offset: u32,
        default_interact_ids_offset: u32,
        interact_names_offset: u32,
        string_table_offset: u32,
    };

    pub fn getString(tb: *const MainCityObjectTemplateTb, string: String) [:0]const u8 {
        return switch (string) {
            .empty => "",
            _ => |index| std.mem.span(@as(
                [*:0]const u8,
                @ptrCast(tb.string_table[@intFromEnum(index)..]),
            )),
        };
    }

    pub fn fromBytes(arena: Allocator, bytes: []const u8) !MainCityObjectTemplateTb {
        const header: *const Header = @ptrCast(@alignCast(bytes.ptr));

        const tag_ids: []const u32 = @ptrCast(@alignCast(
            bytes[header.tag_ids_offset..][0 .. header.count * @sizeOf(u32)],
        ));

        var map: TagMap = .empty;
        try map.reinit(arena, tag_ids, &.{});

        return .{
            .tag_ids = map,
            .default_interact_ids = @ptrCast(@alignCast(
                bytes[header.default_interact_ids_offset..][0 .. header.count * @sizeOf(u32)],
            )),
            .interact_names = @ptrCast(@alignCast(
                bytes[header.interact_names_offset..][0 .. header.count * @sizeOf(u32)],
            )),
            .string_table = bytes[header.string_table_offset..].ptr,
        };
    }
};

const Io = std.Io;
const Allocator = std.mem.Allocator;

const std = @import("std");
const BinConfig = @This();
