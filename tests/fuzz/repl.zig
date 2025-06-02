const std = @import("std");
const lua = @import("lua");

// fn status(L: *lua.lua_State) !void {
//     if (lua.lua_status(L) != lua.LUA_OK) {
//         return error.LuaStatusFail;
//     }
// }

test "repl fuzz" {
    const L_maybe = lua.luaL_newstate();
    const L = L_maybe orelse return error.LuaFailedNewState;
    defer lua.lua_close(L);

    // Not opening IO or OS libs for the rare case fuzzer tries to mess up the system
    if (lua.luaopen_math(L) != lua.LUA_OK) return error.LuaFailedOpenLib;
    if (lua.luaopen_string(L) != lua.LUA_OK) return error.LuaFailedOpenLib;
    if (lua.luaopen_utf8(L) != lua.LUA_OK) return error.LuaFailedOpenLib;
    if (lua.luaopen_table(L) != lua.LUA_OK) return error.LuaFailedOpenLib;

    const code = "print('Hello, World!')";

    if (lua.luaL_loadstring(L, code) == lua.LUA_OK) {
        if (lua.lua_pcall(L, 0, 0, 0) == lua.LUA_OK) {
            // clear stack
            _ = lua.lua_pop(L, lua.lua_gettop(L));
        }
        // don't care about errors, just panics, so just clear the stack
        lua.lua_pop(L, lua.lua_gettop(L));
    }
}
