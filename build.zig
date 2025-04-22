const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libmod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    libmod.linkSystemLibrary("m", .{});

    const cflags: []const []const u8 = &.{
        "-std=gnu99",
        "-Wall",
        "-Wextra",
    };

    // core
    libmod.addCSourceFiles(.{
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
    libmod.addCSourceFiles(.{
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

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "lua",
        .root_module = libmod,
    });

    b.installArtifact(lib);
}
