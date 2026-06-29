pub const Method = enum {
    GET,
    HEAD,
    POST,

    pub fn hasResponseBody(method: Method) bool {
        return switch (method) {
            .GET, .POST => true,
            .HEAD => false,
        };
    }
};

pub const Line = struct {
    method: Method,
    path: []const u8,
    query: []const u8,

    pub const ParseError = error{
        /// The request line didn't fit into `reader.buffer`.
        RequestLineTooLong,
        /// The request line doesn't contain the required components in canonical form.
        MissingComponents,
        /// The specified request method is not defined in `Method`.
        UnsupportedMethod,
    } || Io.Reader.Error;

    /// `reader` must have a non-zero buffer size.
    pub fn parse(reader: *Io.Reader) ParseError!Line {
        const line = reader.takeDelimiterInclusive('\n') catch |err| return switch (err) {
            error.StreamTooLong => error.RequestLineTooLong,
            else => |e| e,
        };

        var parts = std.mem.tokenizeScalar(u8, line, ' ');
        const raw_method = parts.next() orelse return error.MissingComponents;
        const method = std.meta.stringToEnum(Method, raw_method) orelse
            return error.UnsupportedMethod;

        const target = parts.next() orelse return error.MissingComponents;

        const query_start = std.mem.findScalar(u8, target, '?') orelse
            return .{ .method = method, .path = target, .query = "" };

        return .{
            .method = method,
            .path = target[0..query_start],
            .query = if (target.len > query_start + 1)
                target[query_start + 1 ..]
            else
                "",
        };
    }

    pub const ExtractQueryError = error{
        /// The query string is formed in an unexpected way
        Malformed,
        /// Non-optional query parameters are missing
        MissingParameters,
        /// Query string has parameters not defined in resulting struct
        UnexpectedParameters,
        TypeMismatch,
    };

    pub fn extractQuery(line: *const Line, comptime Q: type) ExtractQueryError!Q {
        var it = std.mem.tokenizeScalar(u8, line.query, '&');
        var result: Q = undefined;

        const Name = std.meta.FieldEnum(Q);
        var set: EnumSet(std.meta.FieldEnum(Q)) = .empty;

        while (it.next()) |pair| {
            var split = std.mem.splitScalar(u8, pair, '=');
            const param = split.next().?;
            const value = split.next() orelse return error.Malformed;
            if (split.next() != null) return error.Malformed;

            const name = std.meta.stringToEnum(Name, param) orelse
                return error.UnexpectedParameters;

            set.insert(name);

            switch (name) {
                inline else => |n| @field(result, @tagName(n)) = switch (@FieldType(Q, @tagName(n))) {
                    []const u8 => value,
                    u32, u64 => |T| std.fmt.parseInt(T, value, 10) catch return error.TypeMismatch,
                    else => |T| @compileError("Unsupported type " ++ @typeName(T)),
                },
            }
        } else if (!set.eql(.full)) return error.MissingParameters;

        return result;
    }
};

pub const Headers = struct {
    content_length: ?u64,

    pub const ParseError = error{
        HeaderTooLong,
        HeadersMalformed,
        IllegalHeaderValue,
    } || Io.Reader.Error;

    pub fn parse(reader: *Io.Reader) ParseError!Headers {
        var headers: Headers = .{ .content_length = null };

        while (true) {
            const header = reader.takeDelimiterInclusive('\n') catch |err| return switch (err) {
                error.StreamTooLong => error.HeaderTooLong,
                else => |e| e,
            };

            if (header.len < 2 or header[header.len - 2] != '\r')
                return error.HeadersMalformed;

            if (header.len == 2) // "\r\n" only, this is the end.
                return headers;

            var it = std.mem.tokenizeScalar(u8, header[0 .. header.len - 2], ' ');
            const prefix = it.next().?;
            const value = it.next() orelse return error.HeadersMalformed;

            if (std.ascii.eqlIgnoreCase(prefix, "content-length:")) {
                headers.content_length = std.fmt.parseInt(u64, value, 10) catch
                    return error.IllegalHeaderValue;
            }
        }
    }
};

pub fn Payload(comptime PathEnum: type) type {
    return struct {
        method: Method,
        /// `null` if the requested path didn't match any of enum variants.
        path: ?PathEnum,
        body: []const u8,
    };
}

pub const ReceiveError = error{
    /// Indicates, for example, missing `Content-Length` for `POST` requests.
    ///
    /// After this, the connection is in illegal state.
    IllegalHeaders,
    /// `Content-Length` exceeds reader capacity.
    ///
    /// After this, it's legal to call `receive` again,
    /// the request body is discarded.
    BodyTooBig,
} || Line.ParseError || Headers.ParseError;

pub fn receive(comptime Path: type, reader: *Io.Reader) ReceiveError!Payload(Path) {
    const line: Line = try .parse(reader);
    const path = std.meta.stringToEnum(Path, line.path) orelse noprefix: {
        // strip shit like '/nap_global' at the beginning.
        const path_sep = std.mem.findScalar(u8, line.path[1..], '/') orelse
            break :noprefix null;

        break :noprefix std.meta.stringToEnum(Path, line.path[path_sep + 1 ..]);
    };

    const headers: Headers = try .parse(reader);

    return switch (line.method) {
        .HEAD, .GET => if (headers.content_length == null)
            .{ .method = line.method, .path = path, .body = "" }
        else
            error.IllegalHeaders,
        .POST => POST: {
            const content_length = headers.content_length orelse
                return error.IllegalHeaders;

            if (reader.buffer.len < content_length) {
                try reader.discardAll(content_length);
                return error.BodyTooBig;
            }

            const body = try reader.take(content_length);

            break :POST .{ .method = line.method, .path = path, .body = body };
        },
    };
}

const Io = std.Io;
const EnumSet = std.EnumSet;

const std = @import("std");
const Request = @This();
