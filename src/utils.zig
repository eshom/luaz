//! Utils that should have been translated automatically
//! but failed for some reason or another

const clua = @import("lua_h");

pub inline fn settt_(o: anytype, t: anytype) void {
    @compileLog(o, t);
    o.tt_ = t;
}

// main function to copy values (from 'obj2' to 'obj1') */
pub inline fn setobj(L: clua.lua_State, obj1: anytype, obj2: anytype) void {
    @compileLog(obj1, obj2);
    const io1: *clua.TValue = obj1;
    const io2: *clua.TValue = obj2;
    io1.value_ = io2.value_;
    settt_(io1, io2.tt_);
    clua.checkliveness(L, io1);
    clua.lua_assert(!clua.isnonstrictnil(io1));
}
