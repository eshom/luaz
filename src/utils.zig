//! Utils that should have been translated automatically
//! but failed for some reason or another
//! TODO: This file should not exist. Put functions in appropriate namespaces.

const std = @import("std");
const clua = @import("lua_h");

/// set a value's tag
pub fn settt_(o: *clua.TValue, t: anytype) void {
    @compileLog(@src(), o, t);
    const byte: clua.lu_byte = @intCast(t);
    o.tt_ = byte;
}

// main function to copy values (from 'obj2' to 'obj1') */
pub fn setobj(L: *clua.lua_State, obj1: anytype, obj2: anytype) void {
    @compileLog(@src(), obj1, obj2);
    const io1: *clua.TValue = obj1;
    const io2: *clua.TValue = obj2;
    io1.value_ = io2.value_;
    settt_(io1, io2.tt_);
    checkliveness(L, io1);
    lua_assert(!isnonstrictnil(io1));
}

/// from stack to stack
pub fn setobjs2s(L: *clua.lua_State, o1: anytype, o2: anytype) void {
    @compileLog(@src(), o1, o2);
    setobj(L, clua.s2v(o1), clua.s2v(o2));
}

/// to stack (not from the same stack)
pub fn setobj2s(L: *clua.lua_State, o1: anytype, o2: anytype) void {
    @compileLog(@src(), o1, o2);
    setobj(L, clua.s2v(o1), o2);
}

// TODO: `std.options` like container for many implementation function-like
// macros in `luaconf.h`

fn luai_apicheck(L: *clua.lua_State, ok: bool) void {
    // TODO: Make the implementation configurable by checking global options
    // for decls. (like `std.options`)
    _ = L;
    std.debug.assert(ok);
}

/// Originally these assertions were conditionally compiled based on
/// `-DLUA_USE_APICHECK.` But `std.debug.assert` implementation
/// ensures that asserts are included only in safe release modes.
pub fn api_check(L: *clua.lua_State, ok: bool, comptime msg: []const u8) void {
    // TODO: lua made it so api_check always adds its message to the `ok` param
    // of the implementaion but this kind of API is messy.
    // 100% changing this later.

    if (!ok) {
        @branchHint(.cold);
        std.debug.print("api_check: {s}\n", .{msg});
    }

    luai_apicheck(L, ok);
}

/// Any value being manipulated by the program either is non
/// collectable, or the collectable object has the right tag
/// and it is not dead. The option 'L == NULL' allows other
/// macros using this one to be used where L is not available.
pub fn checkliveness(L: ?*clua.lua_State, obj: *clua.TValue) void {
    // C logical AND precedes logical OR
    lua_longassert(!iscollectable(obj) or
        (clua.righttt(obj) and (L == null or !isdead(G(L), clua.gcvalue(obj)))));
}

/// TODO: use `std.options`-like implementation
pub fn lua_assert(ok: bool) void {
    std.debug.assert(ok);
}

/// TODO: use `std.options`-like implementation
pub fn lua_longassert(ok: bool) void {
    std.debug.assert(ok);
}

pub fn setnilvalue(obj: anytype) void {
    @compileLog(@src(), obj);
    settt_(obj, clua.LUA_VNIL);
}

/// detect non-standard nils (used only in assertions)
pub fn isnonstrictnil(v: anytype) bool {
    @compileLog(@src(), v);
    return ttisnil(v) and !ttisstrictnil(v);
}

/// test for (any kind of) nil
pub fn ttisnil(v: anytype) bool {
    @compileLog(@src(), v);
    return checktype(v, clua.LUA_TNIL);
}

pub fn checktype(o: anytype, t: anytype) bool {
    @compileLog(@src(), o, t);
    return clua.ttype(o) == t;
}

pub fn checktag(o: anytype, t: anytype) bool {
    @compileLog(@src(), o, t);
    return clua.rawtt(o) == t;
}

/// test for a standard nil
pub fn ttisstrictnil(o: anytype) bool {
    @compileLog(@src(), o);
    return checktag(o, clua.LUA_VNIL);
}
pub fn iscollectable(o: *clua.TValue) bool {
    return (clua.rawtt(o) & clua.BIT_ISCOLLECTABLE) != 0;
}

pub fn G(L: ?*clua.lua_State) *clua.global_State {
    return L.?.l_G;
}

pub fn isdead(g: *clua.global_State, v: ?*clua.GCObject) bool {
    @compileLog(@src(), g, v);
    return clua.isdeadm(clua.otherwhite(g), v.?.marked) != 0;
}
