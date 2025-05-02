//! Initialization of libraries for lua.c and other clients

// If you embed Lua in your program and need to open the standard
// libraries, call luaL_openlibs in your program. If you need a
// different set of libraries, copy this file to your project and edit
// it to suit your needs.
//
// You can also *preload* libraries, so that a later 'require' can
// open the library, which is already linked to the application.
// For that, do the following code:
//
//  luaL_getsubtable(L, LUA_REGISTRYINDEX, LUA_PRELOAD_TABLE);
//  lua_pushcfunction(L, luaopen_modname);
//  lua_setfield(L, -2, modname);
//  lua_pop(L, 1);  // remove PRELOAD table

pub const linit_c = "";
pub const LUA_LIB = "";

const clua = @import("lua_h");

/// these libs are loaded by lua.c and are readily available to any Lua
/// program
const loadedlibs: [11]clua.luaL_Reg = .{
    .{ .name = clua.LUA_GNAME, .func = &clua.luaopen_base },
    .{ .name = clua.LUA_LOADLIBNAME, .func = &clua.luaopen_package },
    .{ .name = clua.LUA_COLIBNAME, .func = &clua.luaopen_coroutine },
    .{ .name = clua.LUA_TABLIBNAME, .func = &clua.luaopen_table },
    .{ .name = clua.LUA_IOLIBNAME, .func = &clua.luaopen_io },
    .{ .name = clua.LUA_OSLIBNAME, .func = &clua.luaopen_os },
    .{ .name = clua.LUA_STRLIBNAME, .func = &clua.luaopen_string },
    .{ .name = clua.LUA_MATHLIBNAME, .func = &clua.luaopen_math },
    .{ .name = clua.LUA_UTF8LIBNAME, .func = &clua.luaopen_utf8 },
    .{ .name = clua.LUA_DBLIBNAME, .func = &clua.luaopen_debug },
    .{ .name = null, .func = null },
};

pub export fn luaL_openlibs(L: *clua.lua_State) callconv(.c) void {
    // "require" functions from 'loadedlibs' and set results to global table
    for (loadedlibs) |lib| {
        // zig doesn't need this null terminator but that's how it was done in C code
        if (lib.func == null) break;
        clua.luaL_requiref(L, lib.name, lib.func, 1);
        clua.lua_pop(L, 1); // remove lib
    }
}
