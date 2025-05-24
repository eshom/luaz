const clua = @import("lua_h");
const utils = @import("utils.zig");

/// Increments 'L->top.p', checking for stack overflows
pub fn api_incr_top(L: *clua.lua_State) void {
    L.top.p += 1;
    utils.api_check(L, L.top.p <= L.ci.?.*.top.p, "stack overflow");
}

/// If a call returns too many multiple returns, the callee may not have
/// stack space to accommodate all results. In this case, this macro
/// increases its stack space ('L->ci->top.p').
pub fn adjustresults(L: *clua.lua_State, nres: anytype) void {
    @compileLog(@src(), nres);
    if (nres <= clua.LUA_MULTRET and L.ci.?.*.top.p < L.top.p) {
        L.ci.?.*.top.p = L.top.p;
    }
}

/// Ensure the stack has at least 'n' elements
pub fn api_checknelems(L: *clua.lua_State, n: c_int) void {
    utils.api_check(L, n < (L.top.p - L.ci.?.*.func.p), "not enough elements in the stack");
}

// To reduce the overhead of returning from C functions, the presence of
// to-be-closed variables in these functions is coded in the CallInfo's
// field 'nresults', in a way that functions with no to-be-closed variables
// with zero, one, or "all" wanted results have no overhead. Functions
// with other number of wanted results, as well as functions with
// variables to be closed, have an extra check.

pub fn hastocloseCfunc(n: c_short) bool {
    return n < clua.LUA_MULTRET;
}

/// Map [-1, inf) (range of 'nresults') into (-inf, -2] */
pub fn codeNresults(n: anytype) @TypeOf(n) {
    @compileLog(@src(), n);
    return -n - 3;
}

pub fn decodeNresults(n: anytype) @TypeOf(n) {
    @compileLog(@src(), n);
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
fn isvalid(L: *clua.lua_State, o: anytype) bool {
    @compileLog(@src(), o);
    return !clua.ttisnil(o) or o != &utils.G(L).nilvalue;
}

/// test for pseudo index
fn ispseudo(i: c_int) bool {
    return i <= clua.LUA_REGISTRYINDEX;
}

/// test for upvalue
fn isupvalue(i: c_int) bool {
    return i < clua.LUA_REGISTRYINDEX;
}

/// Convert an acceptable index to a pointer to its respective value.
/// Non-valid indices return the special nil value 'G(L)->nilvalue'.
fn index2value(L: *clua.lua_State, idx: c_int) *clua.TValue {
    const ci: *clua.CallInfo = L.ci.?;

    if (idx > 0) {
        const idx_usize: usize = @intCast(idx);
        const o: clua.StkId = ci.func.p + idx_usize;
        utils.api_check(L, idx <= ci.top.p - (ci.func.p + 1), "unacceptable index");

        if (o >= L.top.p) {
            return &utils.G(L).nilvalue;
        } else {
            return clua.s2v(o);
        }
    } else if (!ispseudo(idx)) { // negative index
        utils.api_check(L, idx != 0 and -idx <= L.top.p - (ci.func.p + 1), "invalid index");
        // TODO: Consolidate branches with twos-complement addition
        const idx_abs: usize = @abs(idx);
        return clua.s2v(L.top.p - idx_abs);
    } else if (idx == clua.LUA_REGISTRYINDEX) {
        return &utils.G(L).l_registry;
    } else { // upvalues
        const jdx = clua.LUA_REGISTRYINDEX - idx;
        utils.api_check(L, jdx <= clua.MAXUPVAL + 1, "upvalue index too large");

        if (clua.ttisCclosure(clua.s2v(ci.func.p))) { // C closure?
            const func: *clua.CClosure = clua.clCvalue(clua.s2v(ci.func.p));
            const idx_usize: usize = @intCast(idx);
            return if (jdx <= func.nupvalues) &func.upvalue[idx_usize - 1] else &utils.G(L).nilvalue;
        } else { // light C function or Lua function (through a hook)?
            utils.api_check(L, clua.ttislcf(clua.s2v(ci.func.p)), "caller not a C function");
            return &utils.G(L).nilvalue; // no upvalues
        }
    }
}

/// Convert a valid actual index (not a pseudo-index) to its address.
fn index2stack(L: *clua.lua_State, idx: c_int) clua.StkId {
    // TODO: The two branches get be consolidated (thank you Protty):
    // idx: c_int = ...;
    // // sign extend to usize-bits then bitcast to twos-complement
    // delta: usize = @bitCast(@as(isize, idx));
    // // use wrapping addition, which should do old_ptr - idx if idx is negative
    // return old_ptr +% delta;
    const ci: *clua.CallInfo = L.ci.?;

    if (idx > 0) {
        const idx_usize: usize = @intCast(idx);
        const o: clua.StkId = ci.func.p + idx_usize;
        utils.api_check(L, o < L.top.p, "invalid index");
        return o;
    } else { // non-positive index
        utils.api_check(L, idx != 0 and -idx <= L.top.p - (ci.func.p + 1), "invalid index");
        utils.api_check(L, !ispseudo(idx), "invalid index");
        const idx_abs: usize = @abs(idx);
        return L.top.p - idx_abs;
    }
}

pub export fn lua_checkstack(L: *clua.lua_State, n: c_int) c_int {
    // lua_lock(L);
    const ci: *clua.CallInfo = L.ci.?;
    utils.api_check(L, n >= 0, "negative 'n'");

    var res: c_int = undefined;

    if (L.stack_last.p - L.top.p > n) { // stack large enough?
        res = 1;
    } else { // need to grow stack
        res = clua.luaD_growstack(L, n, 0);
    }

    const n_usize: usize = @intCast(n);
    if (res != 0 and ci.top.p < L.top.p + n_usize) {
        ci.top.p = L.top.p + n_usize;
    }

    // lua_unlock(L);
    return res;
}

pub export fn lua_xmove(from: *clua.lua_State, to: *clua.lua_State, n: c_int) void {
    if (from == to) return;
    // lua_lock(to);
    api_checknelems(from, n);
    utils.api_check(from, utils.G(from) == clua.G(to), "moving among independent states");
    utils.api_check(from, to.ci.?.*.top.p - to.top.p >= n, "stack overflow");
    const n_usize: usize = @intCast(n);
    from.top.p -= n_usize;

    for (0..n_usize) |i| {
        utils.setobjs2s(to, to.top.p, from.top.p + i);
        to.top.p += 1; // stack already checked by previous 'api_check'
    }
    // lua_unlock(to);
}

pub export fn lua_atpanic(L: *clua.lua_State, panicf: clua.lua_CFunction) clua.lua_CFunction {
    // lua_lock(L);
    const old = utils.G(L).*.panic;
    utils.G(L).*.panic = panicf;
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
    const func = ci.func.p;

    var diff: clua.ptrdiff_t = undefined; // difference for new top

    if (idx >= 0) {
        utils.api_check(L, idx <= ci.top.p - (func + 1), "new top too large");
        const idx_usize: usize = @intCast(idx);
        diff = @intCast(((func + 1) + idx_usize) - L.top.p);

        while (diff > 0) : (diff -= 1) {
            utils.setnilvalue(clua.s2v(L.top.p)); // clear new slots
            L.top.p += 1;
        }
    } else {
        utils.api_check(L, -(idx + 1) <= (L.top.p - (func + 1)), "invalid new top");
        diff = idx + 1;
    }

    utils.api_check(L, L.tbclist.p < L.top.p, "previous pop of an unclosed slot");
    var newtop: clua.StkId = L.top.p + @as(usize, @intCast(diff));

    if (diff < 0 and L.tbclist.p >= newtop) {
        utils.lua_assert(hastocloseCfunc(ci.nresults));
        newtop = clua.luaF_close(L, newtop, clua.CLOSEKTOP, 0);
    }

    L.top.p = newtop; // correct top only after closing any upvalue
    // lua_unlock(L);
}

pub export fn lua_closeslot(L: *clua.lua_State, idx: c_int) void {
    // lua_lock(L);
    var level = index2stack(L, idx);
    utils.api_check(
        L,
        hastocloseCfunc(L.ci.?.*.nresults) and L.tbclist.p == level,
        "no variable to close at given level",
    );
    level = clua.luaF_close(L, level, clua.CLOSEKTOP, 0);
    utils.setnilvalue(clua.s2v(level));
    // lua_unlock(L);
}

/// Reverse the stack segment from 'from' to 'to'
/// (auxiliary to 'lua_rotate')
/// Note that we move(copy) only the value inside the stack.
/// (We do not move additional fields that may exist.)
fn reverse(L: *clua.lua_State, from: clua.StkId, to: clua.StkId) void {
    const from_maybe: ?[*]clua.StackValue = from;
    var from_mut: [*]clua.StackValue = from_maybe.?;

    const to_maybe: ?[*]clua.StackValue = to;
    var to_mut: [*]clua.StackValue = to_maybe.?;

    while (from_mut < to) : ({
        from_mut += 1;
        to_mut -= 1;
    }) {
        var temp: clua.TValue = undefined;
        utils.setobj(L, &temp, clua.s2v(from));
        utils.setobjs2s(L, from, to);
        utils.setobj2s(L, to, &temp);
    }
}

/// Let x = AB, where A is a prefix of length 'n'. Then,
/// rotate x n == BA. But BA == (A^r . B^r)^r.
pub export fn lua_rotate(L: *clua.lua_State, idx: c_int, n: c_int) void {
    // lua_lock(L)
    const t: clua.StkId = L.top.p - 1; // end of stack segment being rotated
    const p: clua.StkId = index2stack(L, idx); // start segment
    const n_usize: usize = @intCast(n);
    utils.api_check(L, @abs(n) <= (t - p + 1), "invalid 'n'");
    const m: clua.StkId = if (n >= 0) t - n_usize else p - n_usize - 1; // end of prefix
    reverse(L, p, m); // reverse the prefix with length 'n'
    reverse(L, m + 1, t); // reverse the suffix
    reverse(L, p, t); // reverse the entire segment
    // lua_unlock(L)
}

pub export fn lua_copy(L: *clua.lua_State, fromidx: c_int, toidx: c_int) void {
    // lua_lock(L)
    const fr: *clua.TValue = index2value(L, fromidx);
    const to: *clua.TValue = index2value(L, toidx);

    utils.api_check(L, isvalid(L, to), "invalid index");
    utils.setobj(L, to, fr);

    if (isupvalue(toidx)) { // function upvalue?
        utils.luaC_barrier(L, utils.clCvalue(clua.s2v(L.ci.?.*.func.p)), fr);
        // LUA_REGISTRYINDEX does not need gc barrier
        //  (collector revisits it before finishing collection)
    }
    // lua_unlock(L)
}
