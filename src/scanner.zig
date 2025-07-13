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

    pub fn scan_token(self: *Scanner) Token {
        self.skip_whitespace();
        self.start = self.current;

        if (self.is_at_end()) return self.make_token(.Eof);

        const c = self.advance();
        switch (c) {
            '(' => return self.make_token(.LeftParen),
            ')' => return self.make_token(.RightParen),
            '{' => return self.make_token(.LeftBrace),
            '}' => return self.make_token(.RightBrace),
            ';' => return self.make_token(.Semicolon),
            ',' => return self.make_token(.Comma),
            '.' => return self.make_token(.Dot),
            '-' => return self.make_token(.Minus),
            '+' => return self.make_token(.Plus),
            '/' => return self.make_token(.Slash),
            '*' => return self.make_token(.Star),
            '!' => {
                const token: TokenType = if (self.match('=')) .BangEqual else .Bang;
                return self.make_token(token);
            },
            '=' => {
                const token: TokenType = if (self.match('=')) .EqualEqual else .Equal;
                return self.make_token(token);
            },
            '<' => {
                const token: TokenType = if (self.match('=')) .LessEqual else .Less;
                return self.make_token(token);
            },
            '>' => {
                const token: TokenType = if (self.match('=')) .GreaterEqual else .Greater;
                return self.make_token(token);
            },
            '"' => return self.string(),
            else => {
                if (self.is_digit(c)) return self.number();
                if (self.is_alpha(c)) return self.identifier();
                return self.error_token("Unexpected character.");
            },
        }
    }

    fn is_digit(self: *const Scanner, c: u8) bool {
        _ = self;
        return c >= '0' and c <= '9';
    }

    fn is_alpha(self: *const Scanner, c: u8) bool {
        _ = self;
        return (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            c == '_';
    }

    fn peek_next(self: *const Scanner) u8 {
        if (self.is_at_end()) return 0;
        return self.current[1];
    }

    fn number(self: *Scanner) Token {
        while (self.is_digit(self.peek())) {
            _ = self.advance();
        }

        if (self.peek() == '.' and self.is_digit(self.peek_next())) {
            _ = self.advance(); // Consume the '.'.
            while (self.is_digit(self.peek())) {
                _ = self.advance();
            }
        }

        return self.make_token(.Number);
    }

    fn string(self: *Scanner) Token {
        while (self.peek() != '"' and !self.is_at_end()) {
            if (self.peek() == '\n') self.line += 1;
            _ = self.advance();
        }

        if (self.is_at_end()) return self.error_token("Unterminated string.");

        _ = self.advance(); // The closing quote.
        return self.make_token(.String);
    }

    fn identifier(self: *Scanner) Token {
        while (self.is_alpha(self.peek()) or self.is_digit(self.peek())) {
            _ = self.advance();
        }
        return self.make_token(self.identifier_type());
    }

    fn identifier_type(self: *const Scanner) TokenType {
        switch (self.start[0]) {
            'a' => return self.check_keyword(1, 2, "nd", .And),
            'c' => return self.check_keyword(1, 4, "lass", .Class),
            'e' => return self.check_keyword(1, 3, "lse", .Else),
            'f' => {
                if (self.current - self.start > 1) {
                    switch (self.start[1]) {
                        'a' => return self.check_keyword(2, 3, "lse", .False),
                        'o' => return self.check_keyword(2, 1, "r", .For),
                        'u' => return self.check_keyword(2, 1, "n", .Fun),
                        else => {},
                    }
                }
            },
            'i' => return self.check_keyword(1, 1, "f", .If),
            'n' => return self.check_keyword(1, 2, "il", .Nil),
            'o' => return self.check_keyword(1, 1, "r", .Or),
            'p' => return self.check_keyword(1, 4, "rint", .Print),
            'r' => return self.check_keyword(1, 5, "eturn", .Return),
            's' => return self.check_keyword(1, 4, "uper", .Super),
            't' => {
                if (self.current - self.start > 1) {
                    switch (self.start[1]) {
                        'h' => return self.check_keyword(2, 2, "is", .This),
                        'r' => return self.check_keyword(2, 2, "ue", .True),
                        else => {},
                    }
                }
            },
            'v' => return self.check_keyword(1, 2, "ar", .Var),
            'w' => return self.check_keyword(1, 4, "hile", .While),
            else => {},
        }

        return .Identifier;
    }

    fn check_keyword(self: *const Scanner, start: usize, length: usize, rest: []const u8, token_type: TokenType) TokenType {
        const current_length = @intFromPtr(self.current) - @intFromPtr(self.start);
        if (current_length == start + length and std.mem.eql(u8, self.start[start..current_length], rest)) {
            return token_type;
        }

        return .Identifier;
    }

    fn is_at_end(self: *const Scanner) bool {
        return self.current[0] == 0;
    }

    fn advance(self: *Scanner) u8 {
        const c = self.current[0];
        self.current += 1;
        return c;
    }

    fn match(self: *Scanner, expected: u8) bool {
        if (self.is_at_end()) return false;
        if (self.current[0] != expected) return false;
        self.current += 1;
        return true;
    }

    fn skip_whitespace(self: *Scanner) void {
        while (true) {
            switch (self.peek()) {
                ' ', '\r', '\t' => _ = self.advance(),
                '\n' => {
                    self.line += 1;
                    _ = self.advance();
                },
                '/' => {
                    if (self.peek_next() == '/') {
                        while (self.peek() != '\n' and !self.is_at_end()) {
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

    fn make_token(self: *const Scanner, tokenType: TokenType) Token {
        return Token{
            .type = tokenType,
            .start = self.start,
            .length = @intFromPtr(self.current) - @intFromPtr(self.start),
            .line = self.line,
        };
    }

    fn error_token(self: *const Scanner, message: []const u8) Token {
        return Token{
            .type = .Error,
            .start = message.ptr,
            .length = message.len,
            .line = self.line,
        };
    }
};
