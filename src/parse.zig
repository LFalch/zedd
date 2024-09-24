const std = @import("std");
const lexer = @import("lexer.zig");

const Token = lexer.Token;
const LexStream = lexer.LexStream;
const Lexeme = lexer.Lexeme;

pub const Err = struct {
    err: []const u8,
    location: lexer.SrcLocation,
};

pub const Error = std.mem.Allocator.Error;

const St = struct {
    stream: *LexStream,
    old_token: ?Token = null,
    cur_token: ?Token,
    alloc: std.mem.Allocator,
    errors: std.ArrayListUnmanaged(Err) = .{},

    const Self = @This();

    fn cur_lexeme(self: *const Self) ?Lexeme {
        const cur_t = self.cur_token orelse return null;
        return cur_t.lexeme;
    }

    fn init(alloc: std.mem.Allocator, stream: *LexStream) Self {
        return .{
            .cur_token = stream.nextLexeme(),
            .stream = stream,
            .alloc = alloc,
        };
    }
    fn finish(self: Self) ![]const Err {
        var st = self;
        return try st.errors.toOwnedSlice(st.alloc);
    }
    fn next(self: *Self) void {
        if (self.cur_token) |ct| {
            std.debug.print("nom: {any}\n", .{ct.lexeme});
        }
        self.cur_token = self.stream.nextLexeme();
    }
    fn err(self: *Self, es: []const u8) !void {
        const sub_string = meow: {
            const t = self.cur_token orelse {
                const src = self.stream.source_code;
                break :meow src[src.len..];
            };
            break :meow t.source;
        };
        const location = lexer.srcLocation(self.stream.source_code, sub_string);

        try self.errors.append(self.alloc, .{
            .err = es,
            .location = location,
        });
    }
    fn accept(ls: *Self, lexeme: ?Lexeme) bool {
        const cur_lex = ls.cur_lexeme();
        if (cur_lex == lexeme) {
            ls.old_token = ls.cur_token;
            ls.next();
            return true;
        }
        return false;
    }
    fn expect(ls: *Self, lexeme: ?Lexeme) !bool {
        if (ls.accept(lexeme))
            return true;
        try ls.err("unexpected symbol");
        return false;
    }

    fn createExpr(ls: *const Self, expr: Expr) !*Expr {
        const e = try ls.alloc.create(Expr);
        e.* = expr;
        return e;
    }
    fn invalid(ls: *const Self) !*Expr {
        const e = try ls.alloc.create(Expr);
        e.* = .invalid;
        return e;
    }
};

pub fn parse(alloc: std.mem.Allocator, lexemes: *lexer.LexStream, errors: *[]const Err) Error!*Expr {
    var ls = St.init(alloc, lexemes);
    const e = try parse_expr(&ls);
    if (!try ls.expect(null)) try ls.err("expected end of file");
    const ret = try ls.finish();
    errors.* = ret;
    return e;
}

fn parse_expr(ls: *St) Error!*Expr {
    return parse_expr_with_prec(ls, 0);
}
fn parse_expr_with_prec(ls: *St, prec: u8) Error!*Expr {
    const left = try parse_expr_non_left_recursive(ls, prec);
    if (ls.accept(Lexeme.OP_PLUS) and prec <= 1) {
        const right = try parse_expr_with_prec(ls, 1);
        return ls.createExpr(.{ .add = .{ .left = left, .right = right } });
    } else if (ls.accept(Lexeme.OP_MINUS) and prec <= 1) {
        const right = try parse_expr_with_prec(ls, 1);
        return ls.createExpr(.{ .sub = .{ .left = left, .right = right } });
    } else if (ls.accept(Lexeme.OP_MULT) and prec <= 2) {
        const right = try parse_expr_with_prec(ls, 2);
        return ls.createExpr(.{ .mul = .{ .left = left, .right = right } });
    } else return left;
}

fn parse_expr_non_left_recursive(ls: *St) !*Expr {
    if (ls.accept(Lexeme.INT_LIT)) {
        const src = ls.old_token.?.source;
        const i = std.fmt.parseInt(i64, src, 10) catch {
            try ls.err("invalid int literal");
            return try ls.invalid();
        };
        return try ls.createExpr(.{ .int_lit = i });
    } else if (ls.accept(Lexeme.LEFT_PAREN)) {
        const e = try parse_expr(ls);
        if (!try ls.expect(Lexeme.RIGHT_PAREN)) return try ls.invalid();
        return e;
    } else if (ls.accept(Lexeme.RIGHT_ARROW)) {
        const e = try ls.alloc.create(Expr);
        const out_e = try parse_expr_non_left_recursive(ls);
        e.* = .{ .out = out_e };
        return e;
    }
    try ls.err("expected expression");
    return try ls.invalid();
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

    invalid,

    pub fn destroy(self: *@This(), alloc: std.mem.Allocator) void {
        switch (self.*) {
            .invalid => {},
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
