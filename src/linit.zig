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
const clualib = @import("lualib_h");
const cauxlib = @import("lauxlib_h");

/// these libs are loaded by lua.c and are readily available to any Lua
/// program
const loadedlibs: [11]cauxlib.luaL_Reg = .{
    .{ .name = cauxlib.LUA_GNAME, .func = &clualib.luaopen_base },
    .{ .name = clualib.LUA_LOADLIBNAME, .func = &clualib.luaopen_package },
    .{ .name = clualib.LUA_COLIBNAME, .func = &clualib.luaopen_coroutine },
    .{ .name = clualib.LUA_TABLIBNAME, .func = &clualib.luaopen_table },
    .{ .name = clualib.LUA_IOLIBNAME, .func = &clualib.luaopen_io },
    .{ .name = clualib.LUA_OSLIBNAME, .func = &clualib.luaopen_os },
    .{ .name = clualib.LUA_STRLIBNAME, .func = &clualib.luaopen_string },
    .{ .name = clualib.LUA_MATHLIBNAME, .func = &clualib.luaopen_math },
    .{ .name = clualib.LUA_UTF8LIBNAME, .func = &clualib.luaopen_utf8 },
    .{ .name = clualib.LUA_DBLIBNAME, .func = &clualib.luaopen_debug },
    .{ .name = null, .func = null },
};

pub export fn luaL_opeblibs(L: *clua.lua_State) void {
    // "require" functions from 'loadedlibs' and set results to global table
    for (loadedlibs) |lib| {
        // zig doesn't need this null terminator but that's how it was done in C code
        if (lib.func == null) break;
        cauxlib.luaL_requiref(L, lib.name, lib.func, 1);
        cauxlib.lua_pop(L, 1); // remove lib
    }
}
