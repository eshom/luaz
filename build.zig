const std = @import("std");

const base_name = "lua";
const version: std.SemanticVersion = .{ .major = 5, .minor = 4, .patch = 7 };

const TestSuiteLevel = enum {
    basic,
    complete,
    internal,
};

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
    // "src/lopcodes.c",
    "src/lparser.c",
    "src/lstate.c",
    "src/lstring.c",
    "src/ltable.c",
    "src/ltm.c",
    "src/lundump.c",
    "src/lvm.c",
    //"src/lzio.c",
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
    // "src/linit.c",
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

    var translated_imports: [1]std.Build.Module.Import = .{
        .{
            .name = "lua_h",
            .module = translateHeader(b, b.path("src/megaheader.h"), target, optimize),
        },
    };

    const use_readline = b.option(bool, "use-readline", "Build with readline for linux") orelse false;
    const build_shared = b.option(bool, "shared", "Build as a shared library. Always true for MinGW") orelse target.result.isMinGW();

    const base_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const zig_lzio = zigObject(b, "lzio", &translated_imports, target, optimize);
    const zig_lopcodes = zigObject(b, "lopcodes", &translated_imports, target, optimize);
    const zig_linit = zigObject(b, "linit", &translated_imports, target, optimize);
    base_mod.addObject(zig_lzio);
    base_mod.addObject(zig_lopcodes);
    base_mod.addObject(zig_linit);

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

    // Complete Test Suite Libs
    // TODO: Add internal tests, Windows support? Better step dependencies?

    const ts_level = b.option(TestSuiteLevel, "test-suite-level", "Lua test suite level (default = basic)") orelse .basic;
    if (ts_level == .internal) @panic("Not Implemented");

    const ts_lib_names: []const []const u8 = &.{ "1", "11", "2", "21", "2-v2" };
    const ts_source_names: []const []const u8 = &.{ "lib1.c", "lib11.c", "lib2.c", "lib21.c", "lib22.c" };

    const test_suite_libs = b.step("test-suite-libs", "Compile lua test suite libraries");

    const run_test_suite = D: switch (ts_level) {
        .basic => {
            break :D b.addSystemCommand(&.{
                "../zig-out/bin/lua",
                "-e _U=true",
                "all.lua",
            });
        },
        else => {
            break :D b.addSystemCommand(&.{
                "../zig-out/bin/lua",
                "all.lua",
            });
        },
    };

    run_test_suite.setCwd(b.path("tests"));
    run_test_suite.step.dependOn(b.getInstallStep());

    switch (ts_level) {
        .complete => {
            inline for (ts_lib_names, ts_source_names) |libname, source| {
                const ts_mod = b.createModule(.{
                    .target = target,
                    .optimize = optimize,
                    .link_libc = true,
                    .pic = true,
                });

                ts_mod.addIncludePath(b.path("zig-out/include"));

                if (build_shared) {
                    ts_mod.linkLibrary(shared);
                } else {
                    ts_mod.linkLibrary(lib);
                }

                ts_mod.addCSourceFile(.{
                    .file = b.path("tests/libs/" ++ source),
                    .flags = cflags,
                });

                const ts_lib = b.addLibrary(.{
                    .linkage = .dynamic,
                    .name = libname,
                    .root_module = ts_mod,
                });

                const install = b.addInstallArtifact(ts_lib, .{
                    .dest_dir = .{
                        .override = .{ .custom = "tests/libs" },
                    },
                });

                test_suite_libs.dependOn(&install.step);
            }

            const run_copy_files = b.addRunArtifact(b.addExecutable(
                .{
                    .name = "install_test_libs",
                    .root_module = b.createModule(.{
                        .root_source_file = b.path("install_test_libs.zig"),
                        .target = target,
                        .optimize = optimize,
                    }),
                },
            ));
            run_copy_files.step.dependOn(test_suite_libs);
            run_test_suite.step.dependOn(&run_copy_files.step);
        },
        else => {},
    }

    b.step("test-suite", "Run lua test suite").dependOn(&run_test_suite.step);

    // LSP check step
    const check = b.step("check", "Check step for LSP");
    check.dependOn(&zig_lzio.step);
    check.dependOn(&zig_lopcodes.step);
    check.dependOn(&zig_linit.step);
}

fn zigObject(
    b: *std.Build,
    comptime object_name: []const u8,
    imports: []std.Build.Module.Import,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    return b.addObject(.{
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/" ++ object_name ++ ".zig"),
            .imports = imports,
        }),
        .name = object_name,
    });
}

fn translateHeader(
    b: *std.Build,
    header: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return b.addTranslateC(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = header,
    }).createModule();
}
