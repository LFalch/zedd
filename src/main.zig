const std = @import("std");
const lib = @import("root.zig");

pub fn main() !void {
    var gpa_std = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_std.deinit();
    const gpa = gpa_std.allocator();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    if (args.len < 2) {
        return error.NoSourceFileArgument;
    }

    const source_file = args[1];

    const source_code = meow: {
        var file = try std.fs.cwd().openFile(source_file, .{});
        defer file.close();

        break :meow try file.readToEndAlloc(gpa, 1024 * 1024 * 1024);
    };
    defer gpa.free(source_code);

    switch (try lib.parseToAst(gpa, source_code)) {
        .err => |errors| {
            defer gpa.free(errors);
            for (errors) |err| {
                std.debug.print("Error @ {s}:{s}: {s}\n", .{ source_file, err.location, err.err });
            }
        },
        .ok => |expr| {
            defer expr.destroy(gpa);
            const res = try lib.eval(expr, std.io.getStdOut().writer());
            std.debug.print("Result {?d}\n", .{res});
        },
    }
}
