const shield_config =
    \\{"retcode":0,"message":"OK","data":{"id":31,"game_key":"nap_cn","client":"PC","identity":"I_IDENTITY","guest":false,"ignore_versions":"","scene":"S_NORMAL","name":"Nap","disable_regist":false,"enable_email_captcha":false,"thirdparty":[],"disable_mmt":false,"server_guest":false,"thirdparty_ignore":{},"enable_ps_bind_account":false,"thirdparty_login_configs":{},"initialize_firebase":false,"bbs_auth_login":false,"bbs_auth_login_ignore":[],"fetch_instance_id":false,"enable_flash_login":false,"enable_logo_18":false,"logo_height":"0","logo_width":"0","enable_cx_bind_account":false,"firebase_blacklist_devices_switch":false,"firebase_blacklist_devices_version":0,"hoyolab_auth_login":false,"hoyolab_auth_login_ignore":[],"hoyoplay_auth_login":true,"enable_douyin_flash_login":false,"enable_age_gate":false,"enable_age_gate_ignore":[]}}
;

pub fn @"/mdk/shield/api/loadConfig"(
    request: *const routes.Request,
) !void {
    try request.response.appendConstant(shield_config);
}

const routes = @import("../routes.zig");
