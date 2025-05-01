const std = @import("std");
const builtin = @import("builtin");

// TODO: verify this is correct for each target in build.zig
const ext = switch (builtin.target.os.tag) {
    .windows => ".dll",
    .macos => ".dylib",
    else => ".so",
};

const pre = switch (builtin.target.os.tag) {
    .windows => "",
    else => "lib",
};

const libs: []const []const u8 = &.{
    "1",
    "11",
    "2",
    "21",
    "2-v2",
};

pub fn main() !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const dest_dir_path = try std.fs.path.resolve(gpa, &.{ "tests", "libs" });
    var dest_dir = try std.fs.cwd().openDir(dest_dir_path, .{});
    defer dest_dir.close();

    inline for (libs) |lib| {
        const libname = pre ++ lib ++ ext;
        const source_path = try std.fs.path.resolve(gpa, &.{ "zig-out", "tests", "libs", libname });
        try std.fs.cwd().copyFile(source_path, dest_dir, libname, .{});

        if (builtin.os.tag == .windows) {
            try std.fs.cwd().copyFile(source_path, dest_dir, lib ++ ".pdb", .{});
        }
    }
}
