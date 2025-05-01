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
