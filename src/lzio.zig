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
    L: *clua.lua_State, // Lua state (for reader)
};

pub const Mbuffer = extern struct {
    buffer: ?[*:0]const u8,
    n: usize,
    buffsize: usize,
};

pub inline fn zgetc(z: *ZIO) u8 {
    defer z.n -= 1;
    if (z.n > 0) {
        defer z.p += 1;
        return z.p[0];
    } else {
        return luaZ_fill(z);
    }
}

fn luaZ_fill(z: *ZIO) callconv(.c) c_int {
    var size: usize = undefined; // out param
    const L: *clua.lua_State = z.L;

    // lua_unlock(L)
    const buff: ?[*:0]const u8 = z.reader.?(L, z.data, &size);
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

pub inline fn luaZ_initbuffer(L: *const clua.lua_State, buff: *Mbuffer) c_int {
    _ = L;
    buff.buffer = null;
    buff.buffsize = 0;
    return 0;
}

pub inline fn luaZ_buffer(buff: *const Mbuffer) ?[*:0]const u8 {
    return buff.buffer;
}

pub inline fn luaZ_sizebuffer(buff: *const Mbuffer) usize {
    return buff.buffsize;
}

pub inline fn luaZ_bufflen(buff: *const Mbuffer) usize {
    return buff.n;
}

pub inline fn luaZ_buffremove(buff: *Mbuffer, i: comptime_int) void {
    buff.n -= i;
}

pub inline fn luaZ_resizebuffer(L: *clua.lua_State, buff: *Mbuffer, size: comptime_int) void {
    buff.buffer = cmem.luaM_reallocvchar(L, buff.buffer, buff.buffsize, size);
}

pub inline fn luaZ_freebuffer(L: *clua.lua_State, buff: *Mbuffer) void {
    luaZ_resizebuffer(L, buff, 0);
}
