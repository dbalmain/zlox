const std = @import("std");

pub const TokenType = enum {
    // Single-character Tokens
    LeftParen,
    RightParen,
    LeftBrace,
    RightBrace,
    Colon,
    Comma,
    Dot,
    Minus,
    Plus,
    Semicolon,
    Slash,
    Star,
    // One or two character tokens.
    Bang,
    BangEqual,
    Equal,
    EqualEqual,
    Greater,
    GreaterEqual,
    Less,
    LessEqual,
    // Literals.
    Identifier,
    String,
    Number,
    // Keywords.
    And,
    Break,
    Case,
    Class,
    Continue,
    Default,
    Else,
    False,
    For,
    Fun,
    If,
    Nil,
    Or,
    Print,
    Return,
    Super,
    Switch,
    This,
    True,
    Var,
    While,

    Error,
    Eof,
};

pub const Token = struct {
    type: TokenType,
    start: [*]const u8,
    len: u24,
    line: u24,
};

pub const Scanner = struct {
    const Self = @This();
    start: [*]const u8,
    end: [*]const u8,
    current: [*]const u8,
    line: u24,

    pub fn init(source: []const u8) Self {
        return Self{
            .start = source.ptr,
            .current = source.ptr,
            .end = source.ptr + source.len,
            .line = 1,
        };
    }

    pub fn next(self: *Self) Token {
        self.skipWhitespace();
        self.start = self.current;
        if (self.isAtEnd()) return self.makeToken(.Eof);

        const c = self.getAndAdvance();

        return switch (c) {
            '(' => self.makeToken(.LeftParen),
            ')' => self.makeToken(.RightParen),
            '{' => self.makeToken(.LeftBrace),
            '}' => self.makeToken(.RightBrace),
            ':' => self.makeToken(.Colon),
            ';' => self.makeToken(.Semicolon),
            ',' => self.makeToken(.Comma),
            '.' => self.makeToken(.Dot),
            '-' => self.makeToken(.Minus),
            '+' => self.makeToken(.Plus),
            '/' => self.makeToken(.Slash),
            '*' => self.makeToken(.Star),
            '!' => self.makeToken(if (self.match('=')) .BangEqual else .Bang),
            '=' => self.makeToken(if (self.match('=')) .EqualEqual else .Equal),
            '>' => self.makeToken(if (self.match('=')) .GreaterEqual else .Greater),
            '<' => self.makeToken(if (self.match('=')) .LessEqual else .Less),
            '"' => self.string(),
            '0'...'9' => self.number(),
            'a'...'z', 'A'...'Z', '_' => self.identifier(),
            else => self.errorToken("Unexpected character."),
        };
    }

    fn getAndAdvance(self: *Self) u8 {
        const char = self.current[0];
        self.advance();
        return char;
    }

    fn advance(self: *Self) void {
        self.current += 1;
    }

    fn peek(self: *Self) u8 {
        return self.current[0];
    }

    fn peekNext(self: *Self) u8 {
        if (self.isAtEnd() or self.current + 1 == self.end) return 0;
        return self.current[1];
    }

    fn match(self: *Self, expected: u8) bool {
        if (self.isAtEnd() or (self.current[0] != expected)) return false;
        self.current += 1;
        return true;
    }

    fn isAtEnd(self: *Self) bool {
        return self.current == self.end;
    }

    fn skipWhitespace(self: *Self) void {
        while (!self.isAtEnd()) {
            const c = self.peek();
            switch (c) {
                ' ', '\r', '\t' => self.advance(),
                '\n' => {
                    self.line += 1;
                    self.advance();
                },
                '/' => {
                    if (self.peekNext() == '/') {
                        while (self.peek() != '\n' and !self.isAtEnd()) self.advance();
                    } else {
                        return;
                    }
                },
                else => return,
            }
        }
    }

    fn makeToken(self: *Self, token_type: TokenType) Token {
        return Token{
            .type = token_type,
            .start = self.start,
            .len = @intCast(self.current - self.start),
            .line = self.line,
        };
    }

    fn errorToken(self: *Self, comptime message: []const u8) Token {
        return Token{
            .type = .Error,
            .start = message.ptr,
            .len = message.len,
            .line = self.line,
        };
    }

    fn string(self: *Self) Token {
        while (self.peek() != '"' and !self.isAtEnd()) {
            if (self.peek() == '\n') self.line += 1;
            self.advance();
        }

        if (self.isAtEnd()) return self.errorToken("Unterminated string.");

        self.advance();
        return self.makeToken(.String);
    }

    fn number(self: *Self) Token {
        while (isDigit(self.peek())) self.advance();
        if (self.peek() == '.' and isDigit(self.peekNext())) {
            self.advance();
            while (isDigit(self.peek())) self.advance();
        }
        return self.makeToken(.Number);
    }

    fn identifier(self: *Self) Token {
        while (isAlphanumeric(self.peek())) self.advance();
        return self.makeToken(self.identifierType());
    }

    fn identifierType(self: *Self) TokenType {
        return switch (self.start[0]) {
            'a' => self.checkKeyword(1, 3, "nd", .And),
            'b' => self.checkKeyword(1, 5, "reak", .Break),
            'c' => if (self.current - self.start > 1) switch (self.start[1]) {
                'a' => self.checkKeyword(2, 4, "se", .Case),
                'l' => self.checkKeyword(2, 5, "ass", .Class),
                'o' => self.checkKeyword(2, 8, "ntinue", .Continue),
                else => .Identifier,
            } else .Identifier,
            'd' => self.checkKeyword(1, 7, "efault", .Default),
            'e' => self.checkKeyword(1, 4, "lse", .Else),
            'f' => if (self.current - self.start > 1) switch (self.start[1]) {
                'a' => self.checkKeyword(2, 5, "lse", .False),
                'o' => self.checkKeyword(2, 3, "r", .For),
                'u' => self.checkKeyword(2, 3, "n", .Fun),
                else => .Identifier,
            } else .Identifier,
            'i' => self.checkKeyword(1, 2, "f", .If),
            'n' => self.checkKeyword(1, 3, "il", .Nil),
            'o' => self.checkKeyword(1, 2, "r", .Or),
            'p' => self.checkKeyword(1, 5, "rint", .Print),
            'r' => self.checkKeyword(1, 6, "eturn", .Return),
            's' => if (self.current - self.start > 1) switch (self.start[1]) {
                'u' => self.checkKeyword(2, 5, "per", .Super),
                'w' => self.checkKeyword(2, 6, "itch", .Switch),
                else => .Identifier,
            } else .Identifier,
            't' => if (self.current - self.start > 1) switch (self.start[1]) {
                'h' => self.checkKeyword(2, 4, "is", .This),
                'r' => self.checkKeyword(2, 4, "ue", .True),
                else => .Identifier,
            } else .Identifier,
            'v' => return self.checkKeyword(1, 3, "ar", .Var),
            'w' => return self.checkKeyword(1, 5, "hile", .While),
            else => .Identifier,
        };
    }

    fn checkKeyword(self: *Self, start: usize, end: usize, rest: []const u8, token_type: TokenType) TokenType {
        if (self.current - self.start == end and std.mem.eql(u8, self.start[start..end], rest)) {
            return token_type;
        }
        return .Identifier;
    }
};

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isAlphanumeric(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
        (c >= '0' and c <= '9') or c == '_';
}
