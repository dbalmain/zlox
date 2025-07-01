const std = @import("std");

pub const TokenType = enum {
    // Single-character tokens.
    LeftParen,
    RightParen,
    LeftBrace,
    RightBrace,
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
    Class,
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
    length: usize,
    line: usize,
};

pub const Scanner = struct {
    start: [*]const u8,
    current: [*]const u8,
    line: usize,

    pub fn init(source: []const u8) Scanner {
        return .{
            .start = source.ptr,
            .current = source.ptr,
            .line = 1,
        };
    }

    pub fn scanToken(self: *Scanner) Token {
        self.skipWhitespace();
        self.start = self.current;

        if (self.isAtEnd()) return self.makeToken(.Eof);

        const c = self.advance();
        switch (c) {
            '(' => return self.makeToken(.LeftParen),
            ')' => return self.makeToken(.RightParen),
            '{' => return self.makeToken(.LeftBrace),
            '}' => return self.makeToken(.RightBrace),
            ';' => return self.makeToken(.Semicolon),
            ',' => return self.makeToken(.Comma),
            '.' => return self.makeToken(.Dot),
            '-' => return self.makeToken(.Minus),
            '+' => return self.makeToken(.Plus),
            '/' => return self.makeToken(.Slash),
            '*' => return self.makeToken(.Star),
            '!' => {
                const token: TokenType = if (self.match('=')) .BangEqual else .Bang;
                return self.makeToken(token);
            },
            '=' => {
                const token: TokenType = if (self.match('=')) .EqualEqual else .Equal;
                return self.makeToken(token);
            },
            '<' => {
                const token: TokenType = if (self.match('=')) .LessEqual else .Less;
                return self.makeToken(token);
            },
            '>' => {
                const token: TokenType = if (self.match('=')) .GreaterEqual else .Greater;
                return self.makeToken(token);
            },
            else => {
                if (self.isDigit(c)) return self.number();
                if (self.isAlpha(c)) return self.identifier();
                return self.errorToken("Unexpected character.");
            },
        }
    }

    fn isDigit(self: *const Scanner, c: u8) bool {
        _ = self;
        return c >= '0' and c <= '9';
    }

    fn isAlpha(self: *const Scanner, c: u8) bool {
        _ = self;
        return (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            c == '_';
    }

    fn peekNext(self: *const Scanner) u8 {
        if (self.isAtEnd()) return 0;
        return self.current[1];
    }

    fn number(self: *Scanner) Token {
        while (self.isDigit(self.peek())) {
            _ = self.advance();
        }

        if (self.peek() == '.' and self.isDigit(self.peekNext())) {
            _ = self.advance(); // Consume the '.'.
            while (self.isDigit(self.peek())) {
                _ = self.advance();
            }
        }

        return self.makeToken(.Number);
    }

    fn string(self: *Scanner) Token {
        while (self.peek() != '"' and !self.isAtEnd()) {
            if (self.peek() == '\n') self.line += 1;
            _ = self.advance();
        }

        if (self.isAtEnd()) return self.errorToken("Unterminated string.");

        _ = self.advance(); // The closing quote.
        return self.makeToken(.String);
    }

    fn identifier(self: *Scanner) Token {
        while (self.isAlpha(self.peek()) or self.isDigit(self.peek())) {
            _ = self.advance();
        }
        return self.makeToken(self.identifierType());
    }

    fn identifierType(self: *const Scanner) TokenType {
        switch (self.start[0]) {
            'a' => return self.checkKeyword(1, 2, "nd", .And),
            'c' => return self.checkKeyword(1, 4, "lass", .Class),
            'e' => return self.checkKeyword(1, 3, "lse", .Else),
            'f' => {
                if (self.current - self.start > 1) {
                    switch (self.start[1]) {
                        'a' => return self.checkKeyword(2, 3, "lse", .False),
                        'o' => return self.checkKeyword(2, 1, "r", .For),
                        'u' => return self.checkKeyword(2, 1, "n", .Fun),
                        else => {},
                    }
                }
            },
            'i' => return self.checkKeyword(1, 1, "f", .If),
            'n' => return self.checkKeyword(1, 2, "il", .Nil),
            'o' => return self.checkKeyword(1, 1, "r", .Or),
            'p' => return self.checkKeyword(1, 4, "rint", .Print),
            'r' => return self.checkKeyword(1, 5, "eturn", .Return),
            's' => return self.checkKeyword(1, 4, "uper", .Super),
            't' => {
                if (self.current - self.start > 1) {
                    switch (self.start[1]) {
                        'h' => return self.checkKeyword(2, 2, "is", .This),
                        'r' => return self.checkKeyword(2, 2, "ue", .True),
                        else => {},
                    }
                }
            },
            'v' => return self.checkKeyword(1, 2, "ar", .Var),
            'w' => return self.checkKeyword(1, 4, "hile", .While),
            else => {},
        }

        return .Identifier;
    }

    fn checkKeyword(self: *const Scanner, start: usize, length: usize, rest: []const u8, token_type: TokenType) TokenType {
        const current_length = @intFromPtr(self.current) - @intFromPtr(self.start);
        if (current_length == start + length and std.mem.eql(u8, self.start[start..current_length], rest)) {
            return token_type;
        }

        return .Identifier;
    }

    fn isAtEnd(self: *const Scanner) bool {
        return self.current[0] == 0;
    }

    fn advance(self: *Scanner) u8 {
        const c = self.current[0];
        self.current += 1;
        return c;
    }

    fn match(self: *Scanner, expected: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.current[0] != expected) return false;
        self.current += 1;
        return true;
    }

    fn skipWhitespace(self: *Scanner) void {
        while (true) {
            switch (self.peek()) {
                ' ', '\r', '\t' => _ = self.advance(),
                '\n' => {
                    self.line += 1;
                    _ = self.advance();
                },
                '/' => {
                    if (self.peekNext() == '/') {
                        while (self.peek() != '\n' and !self.isAtEnd()) {
                            _ = self.advance();
                        }
                    } else {
                        return;
                    }
                },
                else => return,
            }
        }
    }

    fn peek(self: *const Scanner) u8 {
        return self.current[0];
    }

    fn makeToken(self: *const Scanner, tokenType: TokenType) Token {
        return Token{
            .type = tokenType,
            .start = self.start,
            .length = @intFromPtr(self.current) - @intFromPtr(self.start),
            .line = self.line,
        };
    }

    fn errorToken(self: *const Scanner, message: []const u8) Token {
        return Token{
            .type = .Error,
            .start = message.ptr,
            .length = message.len,
            .line = self.line,
        };
    }
};
