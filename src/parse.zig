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
    cur_token: ?Token,
    alloc: std.mem.Allocator,
    errors: std.ArrayListUnmanaged(Err) = .{},

    const Self = @This();

    fn cur_lexeme(self: *const Self) ?Lexeme {
        const cur_t = self.cur_token orelse return null;
        return cur_t.lexeme;
    }
    fn cur_source(self: *const Self) []const u8 {
        const cur_t = self.cur_token orelse return "";
        return cur_t.source;
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
    fn accept(ls: *Self, lexeme: ?Lexeme) ?[]const u8 {
        const cur_lex = ls.cur_lexeme();
        if (cur_lex == lexeme) {
            const cur_src = ls.cur_source();
            ls.next();
            return cur_src;
        }
        return null;
    }
    fn accept_if_prec(ls: *Self, lexeme: Lexeme, prec: u8) ?[]const u8 {
        return if (prec <= lexeme.precedence())
            ls.accept(lexeme)
        else
            null;
    }
    fn expect(ls: *Self, lexeme: ?Lexeme, err_msg: []const u8) !void {
        if (ls.accept(lexeme) == null) {
            try ls.err("unexpected symbol");
            try ls.err(err_msg);
        }
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
    try ls.expect(null, "expected end of file");

    // collect errors and return resulting expression
    const ret = try ls.finish();
    errors.* = ret;
    return e;
}

fn parse_expr(ls: *St) Error!*Expr {
    return parse_expr_with_prec(ls, 0);
}
fn parse_expr_with_prec(ls: *St, prec: u8) Error!*Expr {
    var left = try parse_expr_non_left_recursive(ls);
    while (true) {
        if (ls.accept_if_prec(Lexeme.OP_PLUS, prec)) |_| {
            left = try ls.createExpr(.{ .add = .{ .left = left, .right = undefined } });
            left.add.right = try parse_expr_with_prec(ls, 1);
        } else if (ls.accept_if_prec(Lexeme.OP_MINUS, prec)) |_| {
            left = try ls.createExpr(.{ .sub = .{ .left = left, .right = undefined } });
            left.sub.right = try parse_expr_with_prec(ls, 1);
        } else if (ls.accept_if_prec(Lexeme.OP_MULT, prec)) |_| {
            left = try ls.createExpr(.{ .mul = .{ .left = left, .right = undefined } });
            left.mul.right = try parse_expr_with_prec(ls, 2);
        } else break;
    }
    return left;
}

fn parse_expr_non_left_recursive(ls: *St) !*Expr {
    if (ls.accept(Lexeme.INT_LIT)) |src| {
        const i = std.fmt.parseInt(i64, src, 10) catch {
            try ls.err("invalid int literal");
            return try ls.invalid();
        };
        return try ls.createExpr(.{ .int_lit = i });
    } else if (ls.accept(Lexeme.LEFT_PAREN)) |_| {
        const e = try parse_expr(ls);
        try ls.expect(Lexeme.RIGHT_PAREN, "expected closing bracket");
        return e;
    } else if (ls.accept(Lexeme.RIGHT_ARROW)) |_| {
        const e = try ls.createExpr(.{ .out = undefined });
        e.out = try parse_expr_non_left_recursive(ls);
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
