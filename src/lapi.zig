const clua = @import("lua_h");
const util = @import("utils.zig");

/// Increments 'L->top.p', checking for stack overflows
pub inline fn api_incr_top(L: *clua.lua_State) void {
    L.top.p += 1;
    clua.api_check(L, L.top.p <= L.ci.?.*.top.p, "stack overflow");
}

/// If a call returns too many multiple returns, the callee may not have
/// stack space to accommodate all results. In this case, this macro
/// increases its stack space ('L->ci->top.p').
pub inline fn adjustresults(L: *clua.lua_State, nres: anytype) void {
    @compileLog(nres);
    if (nres <= clua.LUA_MULTRET and L.ci.?.*.top.p < L.top.p) {
        L.ci.?.*.top.p = L.top.p;
    }
}

/// Ensure the stack has at least 'n' elements
pub inline fn api_checknelems(L: *clua.lua_State, n: anytype) void {
    @compileLog(n);
    clua.api_check(L, n < (L.top.p - L.ci.?.*.func.p), "not enough elements in the stack");
}

// To reduce the overhead of returning from C functions, the presence of
// to-be-closed variables in these functions is coded in the CallInfo's
// field 'nresults', in a way that functions with no to-be-closed variables
// with zero, one, or "all" wanted results have no overhead. Functions
// with other number of wanted results, as well as functions with
// variables to be closed, have an extra check.

pub inline fn hastocloseCfunc(n: anytype) bool {
    @compileLog(n);
    return n < clua.LUA_MULTRET;
}

/// Map [-1, inf) (range of 'nresults') into (-inf, -2] */
pub inline fn codeNresults(n: anytype) @TypeOf(n) {
    @compileLog(n);
    return -n - 3;
}

pub inline fn decodeNresults(n: anytype) @TypeOf(n) {
    @compileLog(n);
    return -n - 3;
}

// defines
pub const LUA_CORE = 1;
pub const lapi_c = 1;

const lua_ident = "$LuaVersion: " ++ clua.LUA_COPYRIGHT ++ " $" ++
    "$LuaAuthors: " ++ clua.LUA_AUTHORS ++ " $";

/// Test for a valid index (one that is not the 'nilvalue').
/// '!ttisnil(o)' implies 'o != &G(L)->nilvalue', so it is not needed.
/// However, it covers the most common cases in a faster way.
inline fn isvalid(L: *clua.lua_State, o: anytype) bool {
    @compileLog(o);
    return !clua.ttisnil(o) or o != &clua.G(L).nilvalue;
}

/// test for pseudo index
inline fn ispseudo(i: c_int) bool {
    return i <= clua.LUA_REGISTRYINDEX;
}

/// test for upvalue
inline fn isupvalue(i: c_int) bool {
    return i < clua.LUA_REGISTRYINDEX;
}

/// Convert an acceptable index to a pointer to its respective value.
/// Non-valid indices return the special nil value 'G(L)->nilvalue'.
fn index2value(L: *clua.lua_State, idx: c_int) *clua.TValue {
    const ci: *clua.CallInfo = L.ci.?;

    if (idx > 0) {
        const o: clua.StkId = ci.func.p + idx;
        clua.api_check(L, idx <= ci.top.p - (ci.func.p + 1), "unacceptable index");

        if (o >= L.top.p) {
            return &clua.G(L).nilvalue;
        } else {
            return clua.s2v(o);
        }
    } else if (!ispseudo(idx)) { // negative index
        clua.api_check(L, idx != 0 and -idx <= L.top.p - (ci.func.p + 1), "invalid index");
        return clua.s2v(L.top.p + idx);
    } else if (idx == clua.LUA_REGISTRYINDEX) {
        return &clua.G(L).l_registry;
    } else { // upvalues
        const jdx = clua.LUA_REGISTRYINDEX - idx;
        clua.api_check(L, jdx <= clua.MAXUPVAL + 1, "upvalue index too large");

        if (clua.ttisCclosure(clua.s2v(ci.func.p))) { // C closure?
            const func: *clua.CClosure = clua.clCvalue(clua.s2v(ci.func.p));
            return if (jdx <= func.nupvalues) &func.upvalue[idx - 1] else &clua.G().nilvalue;
        } else { // light C function or Lua function (through a hook)?
            clua.api_check(L, clua.ttislcf(clua.s2v(ci.func.p)), "caller not a C function");
            return &clua.G(L).nilvalue; // no upvalues
        }
    }
}

/// Convert a valid actual index (not a pseudo-index) to its address.
fn index2stack(L: *clua.lua_State, idx: c_int) clua.StkId {
    const ci: *clua.CallInfo = L.ci.?;

    if (idx > 0) {
        const idx_usize: usize = @intCast(idx);
        const o: clua.StkId = ci.func.p + idx_usize;
        clua.api_check(L, o < L.top.p, "invalid index");
        return o;
    } else { // non-positive index
        clua.api_check(L, idx != 0 and -idx <= L.top.p - (ci.func.p + 1), "invalid index");
        clua.api_check(L, !ispseudo(idx), "invalid index");
        return L.top.p + idx;
    }
}

pub export fn lua_checkstack(L: *clua.lua_State, n: c_int) c_int {
    // lua_lock(L);
    const ci: *clua.CallInfo = L.ci.?;
    clua.api_check(L, n >= 0, "negative 'n'");

    var res: c_int = undefined;

    if (L.stack_last.p - L.top.p > n) { // stack large enough?
        res = 1;
    } else { // need to grow stack
        res = clua.luaD_growstack(L, n, 0);
    }

    if (res and ci.top.p < L.top.p + n) {
        ci.top.p = L.top.p + n;
    }

    // lua_unlock(L);
    return res;
}

pub export fn lua_xmove(from: *clua.lua_State, to: *clua.lua_State, n: c_int) void {
    if (from == to) return;
    // lua_lock(to);
    clua.api_checknelems(from, n);
    clua.api_check(from, clua.G(from) == clua.G(to), "moving among independent states");
    clua.api_check(from, to.ci.?.*.top.p - to.top.p >= n, "stack overflow");
    from.top.p -= n;

    for (0..n) |i| {
        clua.setobjs2s(to, to.top.p, from.top.p + i);
        to.top.p += 1; // stack already checked by previous 'api_check'
    }
    // lua_unlock(to);
}

pub export fn lua_atpanic(L: *clua.lua_State, panicf: clua.lua_CFunction) clua.lua_CFunction {
    // lua_lock(L);
    const old = clua.G(L).?.*.panic;
    clua.G(L).?.*.panic = panicf;
    // lua_unlock(L);
    return old;
}

pub export fn lua_version(L: *clua.lua_State) clua.lua_Number {
    clua.UNUSED(L);
    return clua.LUA_VERSION_NUM;
}

// basic stack manipulation

/// convert an acceptable stack index into an absolute index
pub export fn lua_absindex(L: *clua.lua_State, idx: c_int) c_int {
    if (idx > 0 or ispseudo(idx)) {
        return idx;
    } else {
        const diff = @intFromPtr(L.top.p) - @intFromPtr(L.ci.?.*.func.p);
        const idx_usize: usize = @intCast(idx);
        return @intCast(diff + idx_usize);
    }
}

pub export fn lua_gettop(L: *clua.lua_State) c_int {
    return @intCast(@intFromPtr(L.top.p) - @intFromPtr(L.ci.?.*.func.p + 1));
}

pub export fn lua_settop(L: *clua.lua_State, idx: c_int) void {
    // lua_lock(L);
    const ci: *clua.CallInfo = L.ci.?;
    const func = ci.func;

    var diff: clua.ptrdiff_t = undefined; // difference for new top

    if (idx >= 0) {
        // NOTE:
        // - (func + 1)
        // + (func.p + 1)
        clua.api_check(L, idx <= ci.top.p - (func.p + 1), "new top too large");
        diff = ((func + 1) + idx) - L.top.p;

        while (diff > 0) : (diff -= 1) {
            clua.setnilvalue(clua.s2v(L.top.p)); // clear new slots
            L.top.p += 1;
        }
    } else {
        clua.api_check(L, -(idx + 1) <= (L.top.p - (func + 1)), "invalid new top");
        diff = idx + 1;
    }

    clua.api_check(L, L.tbclist.p < L.top.p, "previous pop of an unclosed slot");
    var newtop: clua.StkId = L.top.p + diff;

    if (diff < 0 and L.tbclist.p >= newtop) {
        clua.lua_assert(hastocloseCfunc(ci.nresults));
        newtop = clua.luaF_close(L, newtop, clua.CLOSEKTOP, 0);
    }

    L.top.p = newtop; // correct top only after closing any upvalue
    // lua_unlock(L);
}

pub export fn lua_closeslot(L: *clua.lua_State, idx: c_int) void {
    // lua_lock(L);
    const level = index2stack(L, idx);
    clua.api_check(
        L,
        hastocloseCfunc(L.ci.?.*.nresults) and L.tbclist.p == level,
        "no variable to close at given level",
    );
    level = clua.luaF_close(L, level, clua.CLOSEKTOP, 0);
    clua.setnilvalue(clua.s2v(level));
    // lua_unlock(L);
}

/// Reverse the stack segment from 'from' to 'to'
/// (auxiliary to 'lua_rotate')
/// Note that we move(copy) only the value inside the stack.
/// (We do not move additional fields that may exist.)
fn reverse(L: *clua.lua_State, from: clua.StkId, to: clua.StkId) void {
    while (from < to) : ({
        from += 1;
        to -= 1;
    }) {
        var temp: clua.TValue = undefined;
        util.setobj(L, &temp, clua.s2v(from));
        clua.setobjs2s(L, from, to);
        clua.setobj2s(L, to, &temp);
    }
}

/// Let x = AB, where A is a prefix of length 'n'. Then,
/// rotate x n == BA. But BA == (A^r . B^r)^r.
pub export fn lua_rotate(L: *clua.lua_State, idx: c_int, n: c_int) void {
    // lua_lock(L)
    const t: clua.StkId = L.top.p - 1; // end of stack segment being rotated
    const p: clua.StkId = index2stack(L, idx); // start segment
    const n_usize: usize = @intCast(n);
    clua.api_check(L, @abs(n) <= (t - p + 1), "invalid 'n'");
    const m: clua.StkId = if (n >= 0) t - n_usize else p - n_usize - 1; // end of prefix
    reverse(L, p, m); // reverse the prefix with length 'n'
    reverse(L, m + 1, t); // reverse the suffix
    reverse(L, p, t); // reverse the entire segment
    // lua_unlock(L)
}
