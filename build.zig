const std = @import("std");

const base_name = "lua";
const version: std.SemanticVersion = .{ .major = 5, .minor = 4, .patch = 7 };

const core_src: []const []const u8 = &.{
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
};

const lib_src: []const []const u8 = &.{
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
};

const lib_include: []const []const u8 = &.{
    "lua.h",
    "lua.hpp",
    "luaconf.h",
    "lualib.h",
    "lauxlib.h",
};

const base_src = core_src ++ lib_src;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_readline = b.option(bool, "use-readline", "Build with readline for linux") orelse false;
    const build_shared = b.option(bool, "shared", "Build as a shared library. Always true for MinGW") orelse target.result.isMinGW();

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

    const modules: [3]*std.Build.Module = .{
        base_mod,
        lib_mod,
        luac_mod,
    };

    for (modules) |m| {
        // Not necessary but included to match original Makefile
        if (!target.result.isMinGW()) {
            m.linkSystemLibrary("m", .{});
        }

        switch (target.result.os.tag) {
            .aix => {
                m.addCMacro("LUA_USE_POSIX", "");
                m.addCMacro("LUA_USE_DLOPEN", "");
                m.linkSystemLibrary("dl", .{});
            },
            .freebsd, .netbsd, .openbsd => {
                m.addCMacro("LUA_USE_LINUX", "");
                m.addCMacro("LUA_USE_READLINE", "");
                m.addIncludePath(.{ .cwd_relative = "/usr/include/edit" });
                m.linkSystemLibrary("edit", .{});
            },
            .ios => {
                m.addCMacro("LUA_USE_IOS", "");
            },
            .linux => {
                m.addCMacro("LUA_USE_LINUX", "");
                if (use_readline) {
                    m.addCMacro("LUA_USE_READLINE", "");
                    m.linkSystemLibrary("readline", .{});
                }
                m.linkSystemLibrary("dl", .{});
            },
            .macos => {
                m.addCMacro("LUA_USE_MACOSX", "");
                m.linkSystemLibrary("readline", .{});
            },
            .solaris => {
                m.addCMacro("LUA_USE_POSIX", "");
                m.addCMacro("LUA_USE_DLOPEN", "");
                m.addCMacro("_REENTRANT", "");
                m.linkSystemLibrary("dl", .{});
            },
            else => {
                if (target.result.isMinGW()) {
                    m.addCMacro("LUA_BUILD_AS_DLL", "");
                } else {
                    std.debug.panic(
                        "Unsupported target: arch: {}, os: {}, abi: {}",
                        .{
                            target.result.cpu.arch,
                            target.result.os.tag,
                            target.result.abi,
                        },
                    );
                }
            },
        }
    }

    base_mod.addCSourceFiles(.{
        .flags = cflags,
        .files = base_src,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = if (target.result.isMinGW()) base_name ++ "54" else base_name,
        .root_module = base_mod,
    });

    const shared = b.addLibrary(.{
        .linkage = .dynamic,
        .name = if (target.result.isMinGW()) base_name ++ "54" else base_name,
        .root_module = base_mod,
    });

    lib.installHeadersDirectory(
        b.path("src"),
        "",
        .{ .include_extensions = lib_include },
    );

    const lua = b.addExecutable(.{
        .name = base_name,
        .root_module = lib_mod,
    });

    if (build_shared) {
        lua.linkLibrary(shared);
    } else {
        lua.linkLibrary(lib);
    }
    lua.addCSourceFile(.{ .flags = cflags, .file = b.path("src/lua.c") });

    const luac = b.addExecutable(.{
        .name = base_name ++ "c",
        .root_module = luac_mod,
    });

    luac.linkLibrary(lib);
    luac.addCSourceFile(.{ .flags = cflags, .file = b.path("src/luac.c") });

    b.installDirectory(.{
        .install_dir = .{ .custom = "man" },
        .install_subdir = "man1",
        .source_dir = b.path("doc"),
        .include_extensions = &.{".1"},
    });

    b.installArtifact(lib);
    b.installArtifact(lua);
    b.installArtifact(luac);
}
