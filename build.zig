const std = @import("std");

// TODO: Cross platform + configuation

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const cflags: []const []const u8 = &.{
        "-std=gnu99",
        "-Wall",
        "-Wextra",
    };

    const base_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const lib_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const luac_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // core
    base_mod.addCSourceFiles(.{
        .flags = cflags,
        .files = &.{
            "src/lapi.c",
            "src/lcode.c",
            "src/lctype.c",
            "src/ldebug.c",
            "src/ldo.c",
            "src/ldump.c",
            "src/lfunc.c",
            "src/lgc.c",
            "src/llex.c",
            "src/lmem.c",
            "src/lobject.c",
            "src/lopcodes.c",
            "src/lparser.c",
            "src/lstate.c",
            "src/lstring.c",
            "src/ltable.c",
            "src/ltm.c",
            "src/lundump.c",
            "src/lvm.c",
            "src/lzio.c",
        },
    });

    // lib
    base_mod.addCSourceFiles(.{
        .flags = cflags,
        .files = &.{
            "src/lauxlib.c",
            "src/lbaselib.c",
            "src/lcorolib.c",
            "src/ldblib.c",
            "src/liolib.c",
            "src/lmathlib.c",
            "src/loadlib.c",
            "src/loslib.c",
            "src/lstrlib.c",
            "src/ltablib.c",
            "src/lutf8lib.c",
            "src/linit.c",
        },
    });

    base_mod.addCMacro("LUA_COMPAT_5_3", "");
    base_mod.addCMacro("LUA_USE_LINUX", "");

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "lua",
        .root_module = base_mod,
    });

    const lua = b.addExecutable(.{
        .name = "lua",
        .root_module = lib_mod,
    });

    lua.linkLibrary(lib);
    lua.addCSourceFile(.{ .flags = cflags, .file = b.path("src/lua.c") });
    lua.root_module.addCMacro("LUA_USE_READLINE", "");
    lua.linkSystemLibrary("readline");

    const luac = b.addExecutable(.{
        .name = "luac",
        .root_module = luac_mod,
    });

    luac.linkLibrary(lib);
    luac.addCSourceFile(.{ .flags = cflags, .file = b.path("src/luac.c") });

    b.installArtifact(lib);
    b.installArtifact(lua);
    b.installArtifact(luac);
}
