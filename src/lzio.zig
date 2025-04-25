const clua = @import("lua_h");
const cmem = @import("lmem_h");
const climits = @import("llimits_h");

comptime {
    @export(&luaZ_fill, .{ .name = "luaZ_fill", .visibility = .hidden });
}

pub const EOZ = -1; // end of stream

pub const ZIO = extern struct {
    n: usize, // bytes still unread
    p: [*:0]const u8, // current position in buffer
    reader: clua.lua_Reader, // reader function
    data: ?*anyopaque, // additional data
    L: clua.lua_State, // Lua state (for reader)
};

pub const Mbuffer = extern struct {
    buffer: [*:0]const u8,
    n: usize,
    buffsize: usize,
};

pub fn zgetc(z: anytype) u8 {
    const n = z.n;
    z.n -= 1;
    if (n > 0) {
        const p = z.p;
        z.p += 1;
        return p[0];
    } else {
        return luaZ_fill(z);
    }
}

fn luaZ_fill(z: *ZIO) callconv(.c) c_int {
    const size: usize = undefined; // out param
    const L: *clua.lua_State = z.L;

    // lua_unlock(L)
    const buff: ?[:0]const u8 = z.reader.?(L, z.data, &size);
    // lua_lock(L)

    if (buff == null or size == 0) {
        return EOZ;
    }

    z.n = size - 1; // discount char being returned
    z.p = buff.?;

    const pout = z.p;
    z.p += 1;
    return pout[0];
}
