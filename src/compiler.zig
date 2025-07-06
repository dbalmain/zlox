const std = @import("std");
const scanner = @import("scanner.zig");
const chunk = @import("chunk.zig");
const value = @import("value.zig");

const Allocator = std.mem.Allocator;

const Precedence = enum(u8) {
    None,
    Assignment, // =
    Or, // or
    And, // and
    Equality, // == !=
    Comparison, // < > <= >=
    Term, // + -
    Factor, // * /
    Unary, // ! -
    Call, // . ()
    Primary,
};

const ParseFn = *const fn (o: *Compiler) anyerror!void;

const ParseRule = struct {
    prefix: ?ParseFn,
    infix: ?ParseFn,
    precedence: Precedence,
};

fn getRule(token_type: scanner.TokenType) ParseRule {
    return switch (token_type) {
        .LeftParen => .{ .prefix = grouping, .infix = null, .precedence = .None },
        .RightParen => .{ .prefix = null, .infix = null, .precedence = .None },
        .LeftBrace => .{ .prefix = null, .infix = null, .precedence = .None },
        .RightBrace => .{ .prefix = null, .infix = null, .precedence = .None },
        .Comma => .{ .prefix = null, .infix = null, .precedence = .None },
        .Dot => .{ .prefix = null, .infix = null, .precedence = .None },
        .Minus => .{ .prefix = unary, .infix = binary, .precedence = .Term },
        .Plus => .{ .prefix = null, .infix = binary, .precedence = .Term },
        .Semicolon => .{ .prefix = null, .infix = null, .precedence = .None },
        .Slash => .{ .prefix = null, .infix = binary, .precedence = .Factor },
        .Star => .{ .prefix = null, .infix = binary, .precedence = .Factor },
        .Bang => .{ .prefix = null, .infix = null, .precedence = .None },
        .BangEqual => .{ .prefix = null, .infix = null, .precedence = .None },
        .Equal => .{ .prefix = null, .infix = null, .precedence = .None },
        .EqualEqual => .{ .prefix = null, .infix = null, .precedence = .None },
        .Greater => .{ .prefix = null, .infix = null, .precedence = .None },
        .GreaterEqual => .{ .prefix = null, .infix = null, .precedence = .None },
        .Less => .{ .prefix = null, .infix = null, .precedence = .None },
        .LessEqual => .{ .prefix = null, .infix = null, .precedence = .None },
        .Identifier => .{ .prefix = null, .infix = null, .precedence = .None },
        .String => .{ .prefix = null, .infix = null, .precedence = .None },
        .Number => .{ .prefix = number, .infix = null, .precedence = .None },
        .And => .{ .prefix = null, .infix = null, .precedence = .None },
        .Class => .{ .prefix = null, .infix = null, .precedence = .None },
        .Else => .{ .prefix = null, .infix = null, .precedence = .None },
        .False => .{ .prefix = literal, .infix = null, .precedence = .None },
        .For => .{ .prefix = null, .infix = null, .precedence = .None },
        .Fun => .{ .prefix = null, .infix = null, .precedence = .None },
        .If => .{ .prefix = null, .infix = null, .precedence = .None },
        .Nil => .{ .prefix = literal, .infix = null, .precedence = .None },
        .Or => .{ .prefix = null, .infix = null, .precedence = .None },
        .Print => .{ .prefix = null, .infix = null, .precedence = .None },
        .Return => .{ .prefix = null, .infix = null, .precedence = .None },
        .Super => .{ .prefix = null, .infix = null, .precedence = .None },
        .This => .{ .prefix = null, .infix = null, .precedence = .None },
        .True => .{ .prefix = literal, .infix = null, .precedence = .None },
        .Var => .{ .prefix = null, .infix = null, .precedence = .None },
        .While => .{ .prefix = null, .infix = null, .precedence = .None },
        .Error => .{ .prefix = null, .infix = null, .precedence = .None },
        .Eof => .{ .prefix = null, .infix = null, .precedence = .None },
    };
}

const Parser = struct {
    current: scanner.Token,
    previous: scanner.Token,
    hadError: bool,
    panicMode: bool,

    pub fn init() Parser {
        return .{
            .current = undefined,
            .previous = undefined,
            .hadError = false,
            .panicMode = false,
        };
    }
};

const Compiler = struct {
    parser: Parser,
    scanner: scanner.Scanner,
    compilingChunk: *chunk.Chunk,

    pub fn init(source: []const u8, chk: *chunk.Chunk) Compiler {
        return .{
            .parser = Parser.init(),
            .scanner = scanner.Scanner.init(source),
            .compilingChunk = chk,
        };
    }

    fn advance(self: *Compiler) void {
        self.parser.previous = self.parser.current;

        while (true) {
            self.parser.current = self.scanner.scanToken();
            if (self.parser.current.type != .Error) break;

            self.errorAtCurrent(self.parser.current.start[0..self.parser.current.length]);
        }
    }

    fn consume(self: *Compiler, token_type: scanner.TokenType, message: []const u8) void {
        if (self.parser.current.type == token_type) {
            self.advance();
            return;
        }

        self.errorAtCurrent(message);
    }

    fn currentChunk(self: *Compiler) *chunk.Chunk {
        return self.compilingChunk;
    }

    fn emitByte(self: *Compiler, byte: u8) void {
        self.currentChunk().write(byte, self.parser.previous.line) catch |err| {
            std.debug.print("Should not fail: {any}\n", .{err});
        };
    }

    fn emitBytes(self: *Compiler, byte1: u8, byte2: u8) void {
        self.emitByte(byte1);
        self.emitByte(byte2);
    }

    fn emitReturn(self: *Compiler) void {
        self.emitByte(@intFromEnum(chunk.OpCode.OpReturn));
    }

    fn makeConstant(self: *Compiler, val: value.Value) !u8 {
        try self.currentChunk().addConstant(val);
        return @intCast(self.currentChunk().constants.values.items.len - 1);
    }

    fn emitConstant(self: *Compiler, val: value.Value) !void {
        const constant = try self.makeConstant(val);
        self.emitBytes(@intFromEnum(chunk.OpCode.OpConstant), constant);
    }

    fn end(self: *Compiler) void {
        self.emitReturn();
    }

    fn parsePrecedence(self: *Compiler, precedence: Precedence) !void {
        self.advance();
        const prefixRule = getRule(self.parser.previous.type).prefix;
        if (prefixRule == null) {
            self.compileError("Expect expression.");
            return;
        }

        try prefixRule.?(self);

        while (@intFromEnum(precedence) <= @intFromEnum(getRule(self.parser.current.type).precedence)) {
            self.advance();
            const infixRule = getRule(self.parser.previous.type).infix.?;
            try infixRule(self);
        }
    }

    fn expression(self: *Compiler) !void {
        try self.parsePrecedence(.Assignment);
    }

    fn errorAtCurrent(self: *Compiler, message: []const u8) void {
        self.errorAt(&self.parser.current, message);
    }

    fn compileError(self: *Compiler, message: []const u8) void {
        self.errorAt(&self.parser.previous, message);
    }

    fn errorAt(self: *Compiler, token: *const scanner.Token, message: []const u8) void {
        if (self.parser.panicMode) return;
        self.parser.panicMode = true;

        std.debug.print("[line {d}] Error", .{token.line});

        if (token.type == .Eof) {
            std.debug.print(" at end", .{});
        } else if (token.type == .Error) {
            // Nothing.
        } else {
            std.debug.print(" at '{s}'", .{token.start[0..token.length]});
        }

        std.debug.print(": {s}\n", .{message});
        self.parser.hadError = true;
    }
};

fn grouping(c: *Compiler) !void {
    try c.expression();
    c.consume(.RightParen, "Expect ')' after expression.");
}

fn number(c: *Compiler) !void {
    const val = std.fmt.parseFloat(f64, c.parser.previous.start[0..c.parser.previous.length]) catch unreachable;
    try c.emitConstant(value.number_val(val));
}

fn literal(c: *Compiler) !void {
    switch (c.parser.previous.type) {
        .False => c.emitByte(@intFromEnum(chunk.OpCode.OpFalse)),
        .Nil => c.emitByte(@intFromEnum(chunk.OpCode.OpNil)),
        .True => c.emitByte(@intFromEnum(chunk.OpCode.OpTrue)),
        else => unreachable,
    }
}

fn unary(c: *Compiler) !void {
    const operatorType = c.parser.previous.type;

    // Compile the operand.
    try c.parsePrecedence(.Unary);

    // Emit the operator instruction.
    switch (operatorType) {
        .Minus => c.emitByte(@intFromEnum(chunk.OpCode.OpNegate)),
        else => unreachable,
    }
}

fn binary(c: *Compiler) !void {
    const operatorType = c.parser.previous.type;
    const rule = getRule(operatorType);
    try c.parsePrecedence(@as(Precedence, @enumFromInt(@intFromEnum(rule.precedence) + 1)));

    switch (operatorType) {
        .Plus => c.emitByte(@intFromEnum(chunk.OpCode.OpAdd)),
        .Minus => c.emitByte(@intFromEnum(chunk.OpCode.OpSubtract)),
        .Star => c.emitByte(@intFromEnum(chunk.OpCode.OpMultiply)),
        .Slash => c.emitByte(@intFromEnum(chunk.OpCode.OpDivide)),
        else => unreachable,
    }
}

pub fn compile(source: []const u8, chk: *chunk.Chunk) bool {
    var c = Compiler.init(source, chk);
    c.advance();
    c.expression() catch |err| {
        std.debug.print("Unhandled compile error: {any}\n", .{err});
        return false;
    };
    c.consume(.Eof, "Expect end of expression.");
    c.end();
    return !c.parser.hadError;
}
