const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_readline = b.option(bool, "use-readline", "Linux: link with readline library") orelse false;

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

    const cflags: []const []const u8 = &.{
        "-std=gnu99",
        "-Wall",
        "-Wextra",
    };

    const modules: []*std.Build.Module = &.{
        base_mod,
        lib_mod,
        luac_mod,
    };

    for (modules) |m| {
        switch (target.result.os.tag) {
            .aix => {
                m.addCMacro("LUA_USE_POSIX", "");
                m.addCMacro("LUA_USE_DLOPEN", "");
                m.linkSystemLibrary("dl");
            },
            .freebsd, .netbsd, .openbsd => {
                m.addCMacro("LUA_USE_LINUX", "");
                m.addCMacro("LUA_USE_READLINE", "");
                m.addIncludePath(.{ .cwd_relative = "/usr/include/edit" });
                m.linkSystemLibrary("edit");
            },
            .ios => {
                m.addCMacro("LUA_USE_IOS", "");
            },
            .linux => {
                m.addCMacro("LUA_USE_LINUX", "");
                if (use_readline) {
                    m.addCMacro("LUA_USE_READLINE", "");
                    m.linkSystemLibrary("readline");
                }
                m.linkSystemLibrary("dl");
            },
            .macos => {
                m.addCMacro("LUA_USE_MACOSX", "");
                m.linkSystemLibrary("readline");
            },
            .solaris => {
                m.addCMacro("LUA_USE_POSIX", "");
                m.addCMacro("LUA_USE_DLOPEN", "");
                m.addCMacro("_REENTRANT", "");
                m.linkSystemLibrary("dl");
            },
            else => {
                @compileError("Unsupported target");
            },
        }
    }

    //TODO: Mingw

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
