const log = std.log.scoped(.@"remielle-gamesv");

pub fn bind(
    io: Io,
    gpa: Allocator,
    csprng: Random,
    udp_address: *const net.IpAddress,
    concurrent_session_limit: Io.Limit,
) Io.Cancelable!void {
    var persistent = Persistent.init(io, gpa, .cwd()) catch |err| switch (err) {
        error.Canceled => |e| return e,
        else => |e| fatal("failed to initialize Persistent: {t}", .{e}),
    };

    defer persistent.deinit(gpa);

    const udp_socket = udp_address.bind(
        io,
        .{ .mode = .dgram, .protocol = .udp },
    ) catch |err| switch (err) {
        error.AddressInUse => fatal(
            "the address {f} is already in use; another instance of this server might be already running",
            .{udp_address},
        ),
        else => |e| fatal("bind: {t}", .{e}),
    };

    defer udp_socket.close(io);

    // Used for all of the `Server`-related persistent allocations
    var server_arena: heap.ArenaAllocator = .init(gpa);
    defer server_arena.deinit();

    // Used for temporary per-message allocations.
    var per_message_arena: heap.ArenaAllocator = .init(gpa);
    defer per_message_arena.deinit();

    var server: Server = .init(&per_message_arena, csprng, concurrent_session_limit);
    var buffer: [kcp.mtu]u8 = undefined;

    log.info("waiting for clients at udp://{f}", .{udp_address});

    recv_loop: while (true) {
        const udp_message = udp_socket.receive(io, &buffer) catch |err| switch (err) {
            // The size of packet was greater than `mtu`,
            // this should not happen for well-behaved clients.
            error.MessageOversize => continue :recv_loop,

            error.Canceled => break :recv_loop,

            else => |e| {
                log.err("UDP packet receive failed: {t}", .{e});
                continue :recv_loop;
            },
        };

        const current_time: Io.Timestamp = .now(io, .real);

        if (udp_message.data.len == kcp.Control.size) {
            var out_buf: ?[kcp.Control.size]u8 = null;
            const status = server.receiveControlPacket(
                &udp_message.from,
                .{ .buffer = buffer[0..kcp.Control.size] },
                &out_buf,
            );

            switch (status) {
                .nothing => {},
                .disconnect => |conv_id| disconnect: {
                    const index: u32 = @intCast(server.conv_map.getIndex(conv_id) orelse
                        break :disconnect);

                    defer _ = server.release(conv_id);

                    log.debug("player from {f} disconnected", .{udp_message.from});

                    // Save player on disconnect
                    const player_uid = server.clients.get(.uid, index);

                    savePlayer(
                        io,
                        per_message_arena.allocator(),
                        &persistent,
                        &server.properties,
                        player_uid,
                        index,
                    ) catch |err| log.err(
                        "failed to save player with uid {d}: {t}",
                        .{ player_uid, err },
                    );
                },
            }

            if (out_buf) |*send_buf|
                udp_socket.send(io, &udp_message.from, send_buf) catch |err| switch (err) {
                    error.Canceled => |e| return e,
                    else => {},
                };

            continue;
        } else if (udp_message.data.len < kcp.Header.size) continue;

        const status = server.receiveKcpPacket(
            current_time,
            &udp_message.from,
            udp_message.data,
        ) catch |recv_err| switch (recv_err) {
            error.InvalidToken => {
                // This may happen if server has been restarted, but the game
                // had an active session.
                const kcp_header = kcp.Header.decode(buffer[0..kcp.Header.size]) catch unreachable;
                var ctl: [kcp.Control.size]u8 = undefined;

                kcp.Control.encode(&ctl, .disconnect, kcp_header.conv_id, kcp_header.token, 404);
                udp_socket.send(io, &udp_message.from, &ctl) catch |send_err| switch (send_err) {
                    error.Canceled => |e| return e,
                    else => {},
                };

                continue;
            },
            error.MalformedPacket, error.FillFailed => continue,
        };

        switch (status) {
            .success => {},
            .unauthenticated => |input| {
                var request_string_buffer: [1024]u8 = undefined;

                const request = messaging.expectFirstPacket(
                    &request_string_buffer,
                    buffer[kcp.Header.size..][0..input.header.len],
                ) catch |err| switch (err) {
                    error.SizeMismatch,
                    error.InvalidMagic,
                    error.UnexpectedCmdId,
                    error.MalformedPayload,
                    => continue,
                };

                var response_string_buffer: [messaging.auth.string_buffer_size]u8 = undefined;

                const player_token = messaging.auth.playerGetToken(
                    gpa,
                    csprng,
                    &persistent,
                    &request,
                    &response_string_buffer,
                ) catch |err| switch (err) {
                    error.OutOfMemory,
                    error.InvalidUidString,
                    error.RandKeyDecryptFail,
                    => |e| {
                        log.err("failed to authenticate client from {f}: {t}", .{ udp_message.from, e });
                        continue;
                    },
                };

                const player_index = server.onAuthSucceeded(
                    server_arena.allocator(),
                    &udp_message.from,
                    udp_message.data,
                    input.header.conv_id,
                    input.token,
                    current_time,
                    player_token.key,
                    player_token.response,
                ) catch |err| switch (err) {
                    error.MessageOversize,
                    error.OutOfMemory,
                    error.SessionLimitExceeded,
                    error.InvalidFirstPacket,
                    error.MappingFailed,
                    => continue,
                };

                if (player_token.is_first_login) {
                    const old_cancel_protection = io.swapCancelProtection(.blocked);
                    defer _ = io.swapCancelProtection(old_cancel_protection);

                    persistent.saveAccountUidMap(io) catch |err| switch (err) {
                        error.Canceled => unreachable, // blocked
                        else => |e| fatal("failed to save account uid map: {t}", .{e}),
                    };

                    logic.Properties.setDefaultsAt(&server.properties, @enumFromInt(player_index));

                    savePlayer(
                        io,
                        per_message_arena.allocator(),
                        &persistent,
                        &server.properties,
                        player_token.uid,
                        player_index,
                    ) catch |err| log.err(
                        "failed to save player with uid {d}: {t}",
                        .{ player_token.uid, err },
                    );
                } else {
                    const player_save = persistent.loadPlayer(
                        io,
                        per_message_arena.allocator(),
                        player_token.uid,
                    ) catch |err| switch (err) {
                        error.Canceled => |e| return e,
                        else => |e| {
                            log.err("failed to load player with uid {d}: {t}", .{ player_token.uid, e });

                            // Reset defaults for now.
                            logic.Properties.setDefaultsAt(&server.properties, @enumFromInt(player_index));
                            continue;
                        },
                    };

                    logic.Properties.fromPlayerSave(
                        &server.properties,
                        gpa,
                        @enumFromInt(player_index),
                        &player_save,
                    ) catch |err| {
                        log.err("failed to load player with uid {d}: {t}", .{ player_token.uid, err });

                        // Reset defaults for now.
                        logic.Properties.setDefaultsAt(&server.properties, @enumFromInt(player_index));
                        continue;
                    };
                }
            },
        }

        while (server.multi_conversation.nextUndrained()) |index| drainOutgoingPackets(
            io,
            udp_socket,
            current_time,
            &server.multi_conversation,
            index,
            &udp_message.from,
        ) catch |err| switch (err) {
            error.Canceled => break :recv_loop, // The cancelation was requested.
            else => {},
        };
    }

    log.info("shutting down...", .{});

    const current_time: Io.Timestamp = .now(io, .real);
    var i: u32 = 0;

    // Save all online players and, if possible, kick them out gracefully
    while (i < server.conv_map.count()) : (i += 1) {
        const uid = server.clients.getPtr(.uid, i);

        savePlayer(
            io,
            server_arena.allocator(),
            &persistent,
            &server.properties,
            uid.*,
            i,
        ) catch |err| log.err(
            "failed to save player with uid {d}: {t}",
            .{ uid.*, err },
        );

        if (rmpb.features.isAvailable(.player_kick)) {
            notifyPlayerKick(
                io,
                udp_socket,
                &server,
                current_time,
                i,
                .PlayerKickReason_ServerClose,
            ) catch {};
        }
    }
}

fn savePlayer(
    io: Io,
    arena: Allocator,
    persistent: *Persistent,
    properties: *logic.Properties.List,
    uid: u32,
    index: u32,
) !void {
    const player_save = try logic.Properties.toPlayerSave(properties, arena, @enumFromInt(index));

    const old_cancel_protection = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(old_cancel_protection);

    persistent.savePlayer(io, uid, player_save) catch |err| switch (err) {
        error.Canceled => unreachable, // blocked
        else => |e| return e,
    };
}

/// Sends `PlayerKickScNotify` followed by disconnection control packet.
fn notifyPlayerKick(
    io: Io,
    udp_socket: net.Socket,
    server: *Server,
    current_time: Io.Timestamp,
    index: u32,
    reason: rmpb.main.PlayerKickReason,
) !void {
    const notify: rmpb.main.PlayerKickScNotify = .{ .reason = reason };

    try messaging.send(
        &server.multi_conversation,
        &server.clients,
        index,
        .notify,
        notify,
    );

    try drainOutgoingPackets(
        io,
        udp_socket,
        current_time,
        &server.multi_conversation,
        index,
        server.clients.getPtr(.addr, index),
    );

    var ctl: [kcp.Control.size]u8 = undefined;
    const identifier = server.multi_conversation.identifierAt(index);

    kcp.Control.encode(
        &ctl,
        .disconnect,
        identifier.id,
        identifier.token.downgrade(),
        404,
    );

    try udp_socket.send(io, server.clients.getPtr(.addr, index), &ctl);
}

fn drainOutgoingPackets(
    io: Io,
    udp_socket: net.Socket,
    current_time: Io.Timestamp,
    multi_conversation: *kcp.MultiConversation,
    index: u32,
    destination: *const net.IpAddress,
) !void {
    multi_conversation.updateAt(index, current_time);

    var output_buf: [kcp.mtu]u8 = undefined;
    var it: kcp.MultiConversation.DrainIterator = .init;

    while (!it.isAtEnd()) {
        const n_send = multi_conversation.drainAt(index, &it, &output_buf);
        if (n_send == 0) continue;

        try udp_socket.send(io, destination, output_buf[0..n_send]);
    }
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    log.err(fmt, args);
    std.process.exit(1);
}

const Io = std.Io;
const Random = std.Random;
const Allocator = std.mem.Allocator;

const heap = std.heap;
const net = std.Io.net;

const kcp = @import("kcp.zig");
const logic = @import("logic.zig");
const Server = @import("Server.zig");
const messaging = @import("messaging.zig");
const Persistent = @import("Persistent.zig");

const rmpb = @import("rmpb");
const rmio = @import("rmio");
const std = @import("std");
