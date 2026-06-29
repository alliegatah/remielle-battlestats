const LoginParam = struct {
    uid: []const u8,
    token: []const u8,
};

pub fn @"/combo/granter/login/v2/login"(
    request: *const routes.Request,
) !void {
    const param = json.view(LoginParam, .escaped_once, request.payload.body) orelse
        return error.BadRequest;

    const r = request.response;

    try r.appendConstant(
        \\{"retcode":0,"message":"OK","data":{"account_type":1,"combo_id":"
    );

    try r.append(param.uid);

    try r.appendConstant(
        \\","combo_token":"
    );

    try r.append(param.token);

    try r.appendConstant(
        \\","data":"{\"guest\":false}","heartbeat":false,"open_id":"
    );

    try r.append(param.uid);

    try r.appendConstant(
        \\"}}
    );
}

const json = @import("../json.zig");
const routes = @import("../routes.zig");
