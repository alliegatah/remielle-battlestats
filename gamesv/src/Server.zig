const log = std.log.scoped(.@"remielle-gamesv");

assets: *const Assets,
multi_conversation: kcp.MultiConversation,
clients: Clients,
properties: logic.Properties.List,
conv_counter: kcp.ConvId.Counter,
/// ConvId -> session index
conv_map: array_hash_map.Auto(kcp.ConvId, void),
/// Used for kcp tokens
conv_random: u64,
per_message_arena: *heap.ArenaAllocator,
session_limit: Io.Limit,

pub const Client = struct {
    packet_counter: PacketCounter,
    xorpad: messaging.Xorpad,
    addr: net.IpAddress,
    uid: u32,
};

pub const Clients = rmmem.RemielleArrayList(rmmem.suggestBucketSize(64, Client), Client, u32);

pub const Frame = struct {
    target_index: u32,
    time: Io.Timestamp,
    clients: *Clients,
    assets: *const Assets,
    properties: *logic.Properties.List,
    multi_conversation: *kcp.MultiConversation,

    pub inline fn player(frame: *const Frame) logic.Properties.Player {
        return @enumFromInt(frame.target_index);
    }
};

pub fn init(
    /// Used for per-message allocations
    per_message_arena: *heap.ArenaAllocator,
    csprng: Random,
    assets: *const Assets,
    session_limit: Io.Limit,
) Server {
    return .{
        .assets = assets,
        .multi_conversation = .init,
        .conv_counter = .init,
        .conv_map = .empty,
        .clients = .empty,
        .properties = .empty,
        .conv_random = csprng.int(u64),
        .per_message_arena = per_message_arena,
        .session_limit = session_limit,
    };
}

pub const ControlPacketStatus = union(enum) {
    nothing: void,
    disconnect: kcp.ConvId,
};

pub fn receiveControlPacket(
    server: *Server,
    from: *const net.IpAddress,
    ctl: kcp.Control,
    out: *?[kcp.Control.size]u8,
) ControlPacketStatus {
    switch (ctl.kind()) {
        .connect => {
            const conv_id = server.conv_counter.next();
            const token: kcp.Token = .init(&.{
                .random = server.conv_random,
                .conv_id = conv_id,
                .addr = @bitCast(from.ip4.bytes),
            });

            out.* = @as([kcp.Control.size]u8, undefined);
            kcp.Control.encode(&out.*.?, .send_back_conv, conv_id, token.downgrade(), 0);

            return .nothing;
        },
        .disconnect => {
            const conv_id = ctl.conv();
            const token: kcp.Token = .init(&.{
                .random = server.conv_random,
                .conv_id = conv_id,
                .addr = @bitCast(from.ip4.bytes),
            });

            if (!ctl.isToken(token)) return .nothing;

            out.* = @as([kcp.Control.size]u8, undefined);
            kcp.Control.encode(&out.*.?, .disconnect, conv_id, token.downgrade(), 0);

            return .{ .disconnect = conv_id };
        },
        .send_back_conv, _ => return .nothing, // Clients should not send this
    }
}

pub fn onAuthSucceeded(
    server: *Server,
    /// Used for allocation of per-client ring buffers.
    /// The allocation will be recycled.
    arena: Allocator,
    from: *const net.IpAddress,
    first_packet: []u8,
    conv_id: kcp.ConvId,
    token: kcp.Token,
    current_time: Io.Timestamp,
    key: messaging.Xorpad.Key,
    auth_response: rmpb.main.PlayerGetTokenScRsp,
) !u32 {
    server.session_limit = switch (server.session_limit) {
        .unlimited => .unlimited,
        .nothing => return error.SessionLimitExceeded,
        _ => |limit| limit.subtract(1).?,
    };

    errdefer server.increaseLimit();

    const client = try server.multi_conversation.create(arena, conv_id, token, current_time);
    errdefer server.multi_conversation.swapRemove(client);

    // ACK the packet at kcp level
    server.multi_conversation.fillAt(client, first_packet) catch
        return error.InvalidFirstPacket;

    _ = server.multi_conversation.reader(client) orelse
        return error.InvalidFirstPacket;

    server.multi_conversation.discardAt(client);

    const length = messaging.encodingLength(.init, auth_response);
    var writer = try server.multi_conversation.writer(client, length);

    const cmd_id = comptime rmpb.cmdId(rmpb.main.PlayerGetTokenScRsp).?;
    messaging.encode(&writer.interface, .initial, cmd_id, .init, auth_response) catch unreachable;

    try server.conv_map.put(arena, conv_id, {});
    errdefer _ = server.conv_map.swapRemove(conv_id);

    const index = try server.addClient(from.*, key, auth_response.uid);
    log.debug("player from {f} has logged in into account with uid {d}", .{ from, auth_response.uid });

    return index;
}

pub const ReceiveStatus = union(enum) {
    success: void,
    /// The conversation ID and token are valid,
    /// but the authentication is not finished yet,
    /// this might be the first packet after connection request.
    unauthenticated: struct { header: kcp.Header, token: kcp.Token },
};

pub fn receiveKcpPacket(
    server: *Server,
    time: Io.Timestamp,
    from: *const net.IpAddress,
    buffer: []u8,
) !ReceiveStatus {
    const kcp_header = kcp.Header.decode(buffer[0..kcp.Header.size]) catch
        return error.MalformedPacket;

    if (kcp_header.conv_id == .none)
        return error.MalformedPacket;

    if (buffer.len < kcp_header.len + kcp.Header.size)
        return error.MalformedPacket;

    const token = kcp_header.token.upgrade(
        server.conv_random,
        @bitCast(from.ip4.bytes),
        kcp_header.conv_id,
    ) orelse return error.InvalidToken;

    const client: u32 = @intCast(server.conv_map.getIndex(kcp_header.conv_id) orelse
        return .{ .unauthenticated = .{ .header = kcp_header, .token = token } });

    server.multi_conversation.fillAt(client, buffer) catch
        return error.FillFailed;

    const frame: Frame = .{
        .target_index = client,
        .time = time,
        .assets = server.assets,
        .clients = &server.clients,
        .properties = &server.properties,
        .multi_conversation = &server.multi_conversation,
    };

    while (true) {
        var reader = server.multi_conversation.reader(client) orelse break;
        defer server.multi_conversation.discardAt(client);
        defer _ = server.per_message_arena.reset(.retain_capacity);

        messaging.handlers.process(
            server.per_message_arena.allocator(),
            &frame,
            &reader.interface,
        ) catch |err| {
            log.err("failed to process message: {t}", .{err});
            break;
        };
    }

    return .success;
}

fn addClient(
    server: *Server,
    addr: net.IpAddress,
    key: messaging.Xorpad.Key,
    uid: u32,
) !u32 {
    const index = try server.clients.addOne();
    const properties_index = try server.properties.addOne();

    std.debug.assert(index == properties_index);

    server.clients.getPtr(.packet_counter, index).* = .init;
    server.clients.getPtr(.addr, index).* = addr;
    server.clients.getPtr(.uid, index).* = uid;
    server.clients.getPtr(.xorpad, index).fillSeeded(key);

    return index;
}

fn increaseLimit(server: *Server) void {
    server.session_limit = switch (server.session_limit) {
        .unlimited => .unlimited,
        .nothing, _ => |limit| @enumFromInt(limit.toInt().? + 1),
    };
}

pub fn release(server: *Server, id: kcp.ConvId) bool {
    const client: u32 = @intCast(server.conv_map.getIndex(id) orelse
        return false);

    // Release the resources associated with this `conv_id`.

    server.increaseLimit();

    _ = server.conv_map.swapRemove(id);

    server.multi_conversation.swapRemove(client);
    server.clients.swapRemove(client);
    server.properties.swapRemove(client);

    return true;
}

pub const PacketCounter = enum(u32) {
    init = 1,
    _,

    pub fn nextId(counter: *PacketCounter) u32 {
        defer counter.* = @enumFromInt(1 +% @intFromEnum(counter.*));
        return @intFromEnum(counter.*);
    }
};

const Io = std.Io;
const Random = std.Random;
const Allocator = std.mem.Allocator;

const heap = std.heap;
const net = std.Io.net;
const array_hash_map = std.array_hash_map;

const kcp = @import("kcp.zig");
const logic = @import("logic.zig");
const Assets = @import("Assets.zig");
const messaging = @import("messaging.zig");

const rmio = @import("rmio");
const rmpb = @import("rmpb");
const rmmem = @import("rmmem");

const std = @import("std");
const Server = @This();
