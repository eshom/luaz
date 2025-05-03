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

    // Options
    const use_readline = b.option(bool, "use-readline", "Build with readline for linux") orelse false;
    const build_shared = b.option(bool, "shared", "Build as a shared library. Always true for MinGW") orelse target.result.isMinGW();

    // Steps
    const test_suite_libs = b.step("test-suite-libs", "Compile lua test suite libraries");
    const run_test_suite = b.step("test-suite", "Run lua test suite");
    const check = b.step("check", "Check step for LSP");

    // Modules
    const lib_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const lua_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const luac_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const modules: [3]*std.Build.Module = .{
        lua_mod,
        lib_mod,
        luac_mod,
    };

    // C flags
    const cflags: []const []const u8 = &.{
        "-std=gnu99",
        "-Wall",
        "-Wextra",
    };

    // Compile steps
    const lib_name = if (target.result.isMinGW()) base_name ++ "54" else base_name;

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = lib_name,
        .root_module = lib_mod,
    });

    const shared = b.addLibrary(.{
        .linkage = .dynamic,
        .name = lib_name,
        .root_module = lib_mod,
    });

    const lua = b.addExecutable(.{
        .name = base_name,
        .root_module = lua_mod,
    });

    const luac = b.addExecutable(.{
        .name = base_name ++ "c",
        .root_module = luac_mod,
    });

    // Ported objects (temporary until all is in zig)
    // Objects are added to the library module that the executables then link
    const zig_lzio = zigObject(b, "lzio", &translated_imports, target, optimize);
    const zig_lopcodes = zigObject(b, "lopcodes", &translated_imports, target, optimize);
    const zig_linit = zigObject(b, "linit", &translated_imports, target, optimize);
    lib_mod.addObject(zig_lzio);
    lib_mod.addObject(zig_lopcodes);
    lib_mod.addObject(zig_linit);

    // Only the library needs the base source files
    lib_mod.addCSourceFiles(.{
        .flags = cflags,
        .files = base_src,
    });

    // Lua exe source file
    lua_mod.addCSourceFile(.{ .flags = cflags, .file = b.path("src/lua.c") });

    // Luac exe source file
    luac_mod.addCSourceFile(.{ .flags = cflags, .file = b.path("src/luac.c") });

    // This part is common among all modules
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
                if (target.result.isMinGW()) {} else {
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

    if (target.result.isMinGW()) {
        lib_mod.addCMacro("LUA_BUILD_AS_DLL", "");
        lua_mod.addCMacro("LUA_BUILD_AS_DLL", "");
    }

    lib.installHeadersDirectory(
        b.path("src"),
        "",
        .{ .include_extensions = lib_include },
    );

    if (build_shared) {
        const shared_install = b.addInstallArtifact(shared, .{});
        lua.step.dependOn(&shared_install.step);

        // See: https://github.com/ziglang/zig/issues/17373
        switch (target.result.os.tag) {
            .windows => {}, // dll would be next to the exe
            .macos => {
                lua.addLibraryPath(shared.getEmittedBinDirectory());
                lua.linkSystemLibrary2(shared.name, .{ .use_pkg_config = .no });
                lua.root_module.addRPathSpecial("@loader_path/../lib");
            },
            else => {
                lua.addLibraryPath(shared.getEmittedBinDirectory());
                lua.linkSystemLibrary2(shared.name, .{ .use_pkg_config = .no });
                lua.root_module.addRPathSpecial("$ORIGIN/../lib");
            },
        }
    } else {
        b.installArtifact(lib);
        lua.linkLibrary(lib);
    }

    luac.linkLibrary(lib);
    b.installArtifact(lua);
    b.installArtifact(luac);

    // Manuals
    b.installDirectory(.{
        .install_dir = .{ .custom = "man" },
        .install_subdir = "man1",
        .source_dir = b.path("doc"),
        .include_extensions = &.{".1"},
    });

    // Test Suite
    // TODO: Re-write
    // Fix complete suite
    // Fix Windows (I wish)
    // Implement internal test suite

    const ts_level = b.option(TestSuiteLevel, "test-suite-level", "Lua test suite level (default = basic)") orelse .basic;
    if (ts_level == .internal) @panic("Not Implemented");

    const ts_lib_names: []const []const u8 = &.{ "1", "11", "2", "21", "2-v2" };
    const ts_source_names: []const []const u8 = &.{ "lib1.c", "lib11.c", "lib2.c", "lib21.c", "lib22.c" };

    const ts_run = D: switch (ts_level) {
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

    ts_run.setCwd(b.path("tests"));
    ts_run.step.dependOn(b.getInstallStep());

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
            ts_run.step.dependOn(&run_copy_files.step);
        },
        else => {},
    }

    run_test_suite.dependOn(&ts_run.step);

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
