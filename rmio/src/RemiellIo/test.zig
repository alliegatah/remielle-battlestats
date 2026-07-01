const loopback = Io.net.IpAddress.parseIp4("127.0.0.1", 0) catch unreachable;

test "netBind with unspecified port" {
    if (!RemiellIo.supported) return error.SkipZigTest;

    var rmio: RemiellIo = try .init(testing.allocator, .{
        .coroutine_limit = .limited(1),
        .stack_size = 1024 * 1024,
    });

    defer rmio.deinit();
    const io = rmio.io();

    const socket = try loopback.bind(io, .{ .mode = .dgram, .protocol = .udp });
    defer socket.close(io);

    try testing.expect(socket.address.ip4.port != 0);
}

test "futex operations: Io.Queue with an empty buffer" {
    if (!RemiellIo.supported) return error.SkipZigTest;

    var rmio: RemiellIo = try .init(testing.allocator, .{
        .coroutine_limit = .limited(1),
        .stack_size = 1024 * 1024,
    });

    defer rmio.deinit();
    const io = rmio.io();

    var queue: Io.Queue(u8) = .init(&.{});
    var consumer = try io.concurrent(queueConsumer, .{ io, &queue });

    var i: u8 = 1;

    while (i <= 5) : (i += 1)
        try queue.putOne(io, i);

    try testing.expectError(error.Canceled, consumer.cancel(io));
}

fn queueConsumer(io: Io, queue: *Io.Queue(u8)) !void {
    var i: u8 = 1;

    while (i <= 5) : (i += 1)
        try testing.expectEqual(i, queue.getOne(io));

    const get_result = queue.getOne(io);
    try testing.expectError(error.Canceled, get_result);

    _ = try get_result;
}

const Io = std.Io;

const testing = std.testing;

const RemiellIo = @import("../RemiellIo.zig");
const std = @import("std");
