const std = @import("std");
const testing = std.testing;

const lexer = @import("lexer.zig");
const parse = @import("parse.zig");

const Result = union(enum) {
    ok: *parse.Expr,
    err: []const parse.Err,
};

pub fn parseToAst(alloc: std.mem.Allocator, source: []const u8) !Result {
    var lexemes = lexer.LexStream.init(source);
    var errors: []const parse.Err = undefined;
    const e = try parse.parse(alloc, &lexemes, &errors);
    if (errors.len > 0) {
        e.destroy(alloc);
        return Result{ .err = errors };
    } else {
        return Result{ .ok = e };
    }
}

pub fn eval(e: *const parse.Expr, buf: anytype) !?i64 {
    switch (e.*) {
        .invalid => return null,
        .int_lit => |v| return v,
        .out => |ie| {
            const i = try eval(ie, buf) orelse return null;
            try buf.print("{d}\n", .{i});
            return i;
        },
        .add => |add| {
            const l = try eval(add.left, buf) orelse return null;
            const r = try eval(add.right, buf) orelse return null;
            return l + r;
        },
        .sub => |sub| {
            const l = try eval(sub.left, buf) orelse return null;
            const r = try eval(sub.right, buf) orelse return null;
            return l - r;
        },
        .mul => |mul| {
            const l = try eval(mul.left, buf) orelse return null;
            const r = try eval(mul.right, buf) orelse return null;
            return l * r;
        },
    }
}

test "meow" {
    const alloc = std.testing.allocator;
    const e = (try parseToAst(alloc, "(3 + 2 - 1) * -> (22 * 2) - 4")).ok;
    defer e.destroy(alloc);

    var buf = std.ArrayList(u8).init(alloc);
    defer buf.deinit();

    try testing.expect(try eval(e, buf.writer()) == 172);
    try testing.expect(std.mem.eql(u8, buf.items, "44\n"));
}
