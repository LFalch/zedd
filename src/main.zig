const std = @import("std");
const lexer = @import("lexer.zig");
const parse = @import("parse.zig");

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

        break :meow try file.readToEndAllocOptions(gpa, 1024 * 1024 * 1024, null, 1, 0);
    };
    defer gpa.free(source_code);

    var tokens = lexer.LexStream.init(source_code);
    const expr = try parse.parse(gpa, &tokens);
    defer expr.destroy(gpa);

    const res = eval(expr);
    std.debug.print("Result {d}\n", .{res});
}

fn eval(e: *const parse.Expr) i64 {
    switch (e.*) {
        .int_lit => |v| return v,
        .out => |ie| {
            const i = eval(ie);
            std.debug.print("{d}\n", .{i});
            return i;
        },
        .add => |add| {
            const l = eval(add.left);
            const r = eval(add.right);
            return l + r;
        },
        .sub => |sub| {
            const l = eval(sub.left);
            const r = eval(sub.right);
            return l - r;
        },
        .mul => |mul| {
            const l = eval(mul.left);
            const r = eval(mul.right);
            return l * r;
        },
    }
}
