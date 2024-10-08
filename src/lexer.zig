const std = @import("std");

pub const Lexeme = enum {
    INT_LIT,
    OP_PLUS,
    OP_MINUS,
    OP_MULT,
    RIGHT_ARROW,

    LEFT_PAREN,
    RIGHT_PAREN,

    pub fn precedence(lex: Lexeme) u8 {
        return switch (lex) {
            .OP_PLUS => 1,
            .OP_MINUS => 1,
            .OP_MULT => 2,
            else => unreachable,
        };
    }
};

pub const Token = struct {
    lexeme: Lexeme,
    source: []const u8,
};

pub const SrcLocation = struct {
    start_col: u32,
    start_line: u32,
    end_col: u32,
    end_line: u32,

    pub fn format(
        self: SrcLocation,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("{d}:{d}-{d}.{d}", .{ self.start_line, self.start_col, self.end_line, self.end_col });
    }
};

pub fn srcLocation(source_code: []const u8, substring: []const u8) SrcLocation {
    const start_index = @intFromPtr(substring.ptr) - @intFromPtr(source_code.ptr);
    const end_index = start_index + substring.len;
    var i: usize = 0;
    var start_line: u32 = 1;
    var start_col: u32 = 1;
    while (i < start_index) : (i += 1) {
        if (source_code[i] == '\n') {
            start_line += 1;
            start_col = 1;
        } else start_col += 1;
    }
    var end_line: u32 = start_line;
    var end_col: u32 = start_col;
    while (i < end_index) : (i += 1) {
        if (source_code[i] == '\n') {
            end_line += 1;
            start_col = 1;
        } else end_col += 1;
    }
    return .{
        .start_line = start_line,
        .start_col = start_col,
        .end_line = end_line,
        .end_col = end_col,
    };
}

pub const LexStream = struct {
    source_code: []const u8,
    index: usize = 0,

    const Self = @This();

    fn getByte(self: *Self) ?u8 {
        if (self.index >= self.source_code.len) return null;

        const b = self.source_code[self.index];
        self.index += 1;
        return b;
    }
    fn rewind(self: *Self) void {
        self.index -= 1;
    }

    pub fn init(source_code: []const u8) Self {
        return .{
            .source_code = source_code,
        };
    }
    pub fn nextLexeme(self: *Self) ?Token {
        const start_index = self.index;

        const byte = self.getByte() orelse return null;

        if (std.ascii.isWhitespace(byte)) return self.nextLexeme();

        switch (byte) {
            '0'...'9' => {
                while (self.getByte()) |b| {
                    switch (b) {
                        '0'...'9' => {},
                        else => {
                            self.rewind();
                            break;
                        },
                    }
                }
                return .{
                    .lexeme = .INT_LIT,
                    .source = self.source_code[start_index..self.index],
                };
            },
            '+' => return .{
                .lexeme = .OP_PLUS,
                .source = self.source_code[start_index..self.index],
            },
            '*' => return .{
                .lexeme = .OP_MULT,
                .source = self.source_code[start_index..self.index],
            },
            '(' => return .{
                .lexeme = .LEFT_PAREN,
                .source = self.source_code[start_index..self.index],
            },
            ')' => return .{
                .lexeme = .RIGHT_PAREN,
                .source = self.source_code[start_index..self.index],
            },
            '-' => {
                if (self.getByte() == '>') {
                    return .{
                        .lexeme = .RIGHT_ARROW,
                        .source = self.source_code[start_index..self.index],
                    };
                }
                return .{
                    .lexeme = .OP_MINUS,
                    .source = self.source_code[start_index..self.index],
                };
            },
            else => {},
        }
        // throw error
        return null;
    }
};
