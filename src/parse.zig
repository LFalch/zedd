const std = @import("std");
const lexer = @import("lexer.zig");

pub fn parse(alloc: std.mem.Allocator, lexemes: *lexer.LexStream) !*Expr {
    const token = lexemes.nextLexeme() orelse return error.UnexpectedEnd;
    switch (token.lexeme) {
        .INT_LIT => {
            const i = try std.fmt.parseInt(i64, token.source, 10);
            const e = try alloc.create(Expr);
            e.* = .{ .int_lit = i };

            if (lexemes.nextLexeme()) |op_token| {
                switch (op_token.lexeme) {
                    .OP_PLUS => {
                        const add_e = try alloc.create(Expr);
                        add_e.* = .{ .add = .{ .left = e, .right = try parse(alloc, lexemes) } };
                        return add_e;
                    },
                    .OP_MINUS => {
                        const sub_e = try alloc.create(Expr);
                        sub_e.* = .{ .sub = .{ .left = e, .right = try parse(alloc, lexemes) } };
                        return sub_e;
                    },
                    .OP_MULT => {
                        const mul_e = try alloc.create(Expr);
                        mul_e.* = .{ .mul = .{ .left = e, .right = try parse(alloc, lexemes) } };
                        return mul_e;
                    },
                    else => return error.ExpectedOp,
                }
            } else {
                return e;
            }
        },
        .RIGHT_ARROW => {
            const e = try alloc.create(Expr);
            e.* = .{ .out = try parse(alloc, lexemes) };
            return e;
        },
        else => return error.ExpectedValue,
    }
}

pub const Expr = union(enum) {
    int_lit: i64,
    add: struct {
        left: *Expr,
        right: *Expr,
    },
    sub: struct {
        left: *Expr,
        right: *Expr,
    },
    mul: struct {
        left: *Expr,
        right: *Expr,
    },
    out: *Expr,

    pub fn destroy(self: *@This(), alloc: std.mem.Allocator) void {
        switch (self.*) {
            .int_lit => {},
            .add => |v| {
                v.left.destroy(alloc);
                v.right.destroy(alloc);
            },
            .sub => |v| {
                v.left.destroy(alloc);
                v.right.destroy(alloc);
            },
            .mul => |v| {
                v.left.destroy(alloc);
                v.right.destroy(alloc);
            },
            .out => |v| {
                v.destroy(alloc);
            },
        }
        self.* = undefined;
        alloc.destroy(self);
    }
};
