const std = @import("std");

const program = "podman";
const fallback = "docker";
const tag = "luatests";

pub fn main() !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var pathbuf: [std.posix.PATH_MAX]u8 = undefined;
    const cwd = try std.posix.getcwd(&pathbuf);

    var build_image = std.process.Child.init(
        &.{ program, "build", "-t", tag, "." },
        gpa,
    );

    const build_image_term = build_image.spawnAndWait() catch |err| switch (err) {
        error.FileNotFound => {
            // Docker path
            var build_image2 = std.process.Child.init(
                &.{ fallback, "build", "-t", tag, "." },
                gpa,
            );

            const build_image_term2 = try build_image2.spawnAndWait();

            if (build_image_term2.Exited != 0) {
                return error.ChildNonZeroExit;
            }

            var run_suite2 = std.process.Child.init(
                &.{
                    fallback,
                    "run",
                    "-it",
                    "--rm",
                    "--volume",
                    try std.fs.path.join(gpa, &.{ cwd, "zig-out:/home/lua/out" }),
                    tag ++ ":latest",
                },
                gpa,
            );

            const run_suite_term2 = try run_suite2.spawnAndWait();

            if (run_suite_term2.Exited != 0) {
                return error.ChildNonZeroExit;
            }

            return;
        },
        else => return err,
    };

    if (build_image_term.Exited != 0) {
        return error.ChildNonZeroExit;
    }

    var run_suite = std.process.Child.init(
        &.{
            program,
            "run",
            "-it",
            "--rm",
            "--volume",
            try std.fs.path.join(gpa, &.{ cwd, "zig-out:/home/lua/out" }),
            tag ++ ":latest",
        },
        gpa,
    );

    const run_suite_term = try run_suite.spawnAndWait();

    if (run_suite_term.Exited != 0) {
        return error.ChildNonZeroExit;
    }
}
