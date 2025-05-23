const clua = @import("lua_h");
const c = @import("c.zig");

comptime {
    @export(&luaZ_fill, .{ .name = "luaZ_fill", .visibility = .hidden });
    @export(&luaZ_init, .{ .name = "luaZ_init", .visibility = .hidden });
    @export(&luaZ_read, .{ .name = "luaZ_read", .visibility = .hidden });
}

pub const EOZ = -1; // end of stream

pub const ZIO = extern struct {
    n: usize, // bytes still unread
    p: ?[*:0]const u8, // current position in buffer
    reader: clua.lua_Reader, // reader function
    data: ?*anyopaque, // additional data
    L: *clua.lua_State, // Lua state (for reader)
};

pub const Mbuffer = extern struct {
    buffer: ?[*:0]const u8,
    n: usize,
    buffsize: usize,
};

pub fn zgetc(z: *ZIO) u8 {
    @compileLog(@src(), z);
    defer z.n -= 1;
    if (z.n > 0) {
        defer z.p.? += 1;
        return z.p.?[0];
    } else {
        return luaZ_fill(z);
    }
}

pub fn luaZ_initbuffer(L: *const clua.lua_State, buff: *Mbuffer) c_int {
    @compileLog(@src(), L, buff);
    // _ = L;
    buff.buffer = null;
    buff.buffsize = 0;
    return 0;
}

pub fn luaZ_buffer(buff: *const Mbuffer) ?[*:0]const u8 {
    @compileLog(@src(), buff);
    return buff.buffer;
}

pub fn luaZ_sizebuffer(buff: *const Mbuffer) usize {
    @compileLog(@src(), buff);
    return buff.buffsize;
}

pub fn luaZ_bufflen(buff: *const Mbuffer) usize {
    @compileLog(@src(), buff);
    return buff.n;
}

pub fn luaZ_buffremove(buff: *Mbuffer, i: comptime_int) void {
    @compileLog(@src(), buff);
    buff.n -= i;
}

pub fn luaZ_resizebuffer(L: *clua.lua_State, buff: *Mbuffer, size: comptime_int) void {
    @compileLog(@src(), L, buff, size);
    buff.buffer = clua.luaM_reallocvchar(L, buff.buffer, buff.buffsize, size);
}

pub fn luaZ_freebuffer(L: *clua.lua_State, buff: *Mbuffer) void {
    @compileLog(@src(), L, buff);
    luaZ_resizebuffer(L, buff, 0);
}

pub fn luaZ_fill(z: *ZIO) callconv(.c) c_int {
    var size: usize = undefined; // out param
    const L: *clua.lua_State = z.L;

    // TODO: figure out lua_unlock

    // lua_unlock(L)
    const buff: ?[*:0]const u8 = z.reader.?(L, z.data, &size);
    // lua_lock(L)

    if (buff == null or size == 0) {
        return EOZ;
    }

    z.n = size - 1; // discount char being returned
    z.p = buff.?;

    const pout = z.p;
    z.p.? += 1;
    return pout.?[0];
}

pub fn luaZ_init(L: *clua.lua_State, z: *ZIO, reader: clua.lua_Reader, data: ?*anyopaque) callconv(.c) void {
    z.L = L;
    z.reader = reader;
    z.data = data;
    z.n = 0;
    z.p = null;
}

/// read next n bytes
pub fn luaZ_read(z: *ZIO, arg_b: ?*anyopaque, arg_n: usize) callconv(.c) usize {
    var b = arg_b;
    var n = arg_n;

    while (n != 0) {
        if (z.n == 0) { // no bytes in buffer?
            if (luaZ_fill(z) == EOZ) { // try to read more
                return n; // no more input; return number of missing bytes
            } else {
                z.n +%= 1; // luaZ_fill consumed first byte; put it back
                z.p.? -= 1;
            }
        }

        const m = if (n <= z.n) n else z.n; // min. between n and z.n

        _ = c.memcpy(b, z.p, m);
        z.n -%= m;
        z.p.? += m;

        const ptr: ?[*]u8 = @ptrCast(@alignCast(b));
        b = ptr.? + m;
        n -%= m;
    }

    return 0;
}
