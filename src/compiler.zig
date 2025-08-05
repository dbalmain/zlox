const std = @import("std");
const scanner = @import("scanner.zig");
const chunk = @import("chunk.zig");
const value = @import("value.zig");
const debug = @import("debug.zig");
const config = @import("config");

const Precedence = enum {
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

    fn next(self: Precedence) Precedence {
        return @enumFromInt(@intFromEnum(self) + 1);
    }

    fn le(self: Precedence, other: Precedence) bool {
        return @intFromEnum(self) <= @intFromEnum(other);
    }
};

const ParseFn = *const fn (c: *Compiler) CompileError!void;
const ParseRule = struct {
    prefix: ?ParseFn,
    infix: ?ParseFn,
    precedence: Precedence,

    fn init(comptime prefix: ?ParseFn, comptime infix: ?ParseFn, comptime precedence: Precedence) ParseRule {
        return ParseRule{ .prefix = prefix, .infix = infix, .precedence = precedence };
    }
};

fn getRule(token_type: scanner.TokenType) ParseRule {
    return switch (token_type) {
        .LeftParen => ParseRule.init(grouping, null, .None),
        .RightParen => ParseRule.init(null, null, .None),
        .LeftBrace => ParseRule.init(null, null, .None),
        .RightBrace => ParseRule.init(null, null, .None),
        .Comma => ParseRule.init(null, null, .None),
        .Dot => ParseRule.init(null, null, .None),
        .Minus => ParseRule.init(unary, binary, .Term),
        .Plus => ParseRule.init(null, binary, .Term),
        .Semicolon => ParseRule.init(null, null, .None),
        .Slash => ParseRule.init(null, binary, .Factor),
        .Star => ParseRule.init(null, binary, .Factor),
        .Bang => ParseRule.init(null, null, .None),
        .BangEqual => ParseRule.init(null, null, .None),
        .Equal => ParseRule.init(null, null, .None),
        .EqualEqual => ParseRule.init(null, null, .None),
        .Greater => ParseRule.init(null, null, .None),
        .GreaterEqual => ParseRule.init(null, null, .None),
        .Less => ParseRule.init(null, null, .None),
        .LessEqual => ParseRule.init(null, null, .None),
        .Identifier => ParseRule.init(null, null, .None),
        .String => ParseRule.init(null, null, .None),
        .Number => ParseRule.init(number, null, .None),
        .And => ParseRule.init(null, null, .None),
        .Class => ParseRule.init(null, null, .None),
        .Else => ParseRule.init(null, null, .None),
        .False => ParseRule.init(null, null, .None),
        .For => ParseRule.init(null, null, .None),
        .Fun => ParseRule.init(null, null, .None),
        .If => ParseRule.init(null, null, .None),
        .Nil => ParseRule.init(null, null, .None),
        .Or => ParseRule.init(null, null, .None),
        .Print => ParseRule.init(null, null, .None),
        .Return => ParseRule.init(null, null, .None),
        .Super => ParseRule.init(null, null, .None),
        .This => ParseRule.init(null, null, .None),
        .True => ParseRule.init(null, null, .None),
        .Var => ParseRule.init(null, null, .None),
        .While => ParseRule.init(null, null, .None),
        .Error => ParseRule.init(null, null, .None),
        .Eof => ParseRule.init(null, null, .None),
    };
}

const CompileError = error{
    CompileError,
    UnexpectedEof,
    ParseError,
    UnexpectedError,
    OutOfMemory,
};

const Parser = struct {
    const Self = @This();
    current: scanner.Token,
    previous: scanner.Token,
    err: ?CompileError,
    fn init() Self {
        return Self{
            .current = undefined,
            .previous = undefined,
            .err = null,
        };
    }
};

const Compiler = struct {
    const Self = @This();
    scanner: scanner.Scanner,
    chunk: *chunk.Chunk,
    parser: Parser,

    fn init(source: []const u8, chk: *chunk.Chunk) Self {
        return Compiler{
            .scanner = scanner.Scanner.init(source),
            .parser = Parser.init(),
            .chunk = chk,
        };
    }

    fn parsePrecedence(self: *Self, precedence: Precedence) CompileError!void {
        self.advance();
        const prefixRule = getRule(self.parser.previous.type).prefix;
        if (prefixRule == null) {
            return self.compileError("Expect expression.");
        }
        try prefixRule.?(self);
        while (precedence.le(getRule(self.parser.current.type).precedence)) {
            self.advance();
            const infixRule = getRule(self.parser.previous.type).infix.?;
            try infixRule(self);
        }
    }

    fn expression(self: *Self) CompileError!void {
        try self.parsePrecedence(.Assignment);
    }

    fn advance(self: *Self) void {
        self.parser.previous = self.parser.current;
        while (true) {
            self.parser.current = self.scanner.next();
            if (self.parser.current.type != .Error) break;

            self.errorAtCurrent(self.parser.current.start[0..self.parser.current.len]);
        }
    }

    fn consume(self: *Self, token_type: scanner.TokenType, message: []const u8) void {
        if (self.parser.current.type == token_type) {
            self.advance();
        } else {
            self.errorAtCurrent(message);
        }
    }

    fn emitByte(self: *Self, byte: u8) CompileError!void {
        self.chunk.writeByte(byte) catch {
            return CompileError.OutOfMemory;
        };
    }

    fn emitCode(self: *Self, code: chunk.OpCode) CompileError!void {
        self.chunk.writeCode(code, self.parser.previous.line) catch {
            return CompileError.OutOfMemory;
        };
    }

    fn emitCodeAndByte(self: *Self, code: chunk.OpCode, byte: u8) CompileError!void {
        try self.emitCode(code);
        try self.emitByte(byte);
    }

    fn emitConstant(self: *Self, val: value.Value) CompileError!void {
        self.chunk.writeConstant(val, self.parser.previous.line) catch {
            return CompileError.OutOfMemory;
        };
    }

    fn endCompiler(self: *Self) CompileError!void {
        try self.emitReturn();
    }

    fn emitReturn(self: *Self) CompileError!void {
        try self.emitCode(.Return);
    }

    fn errorAtCurrent(self: *Self, message: []const u8) void {
        self.errorAt(&self.parser.current, message);
    }

    fn errorAt(self: *Self, token: *scanner.Token, message: []const u8) void {
        const stderr = std.io.getStdErr().writer();
        stderr.print("[line {d}] Error", .{token.line}) catch {};
        if (token.type == .Eof) {
            stderr.print(" at end", .{}) catch unreachable;
            self.parser.err = CompileError.UnexpectedEof;
        } else if (token.type == .Error) {
            self.parser.err = CompileError.ParseError;
        } else {
            stderr.print(" at '{s}'", .{token.start[0..token.len]}) catch unreachable;
            self.parser.err = CompileError.CompileError;
        }
        stderr.print("{s}\n", .{message}) catch unreachable;
    }

    fn compileError(self: *Self, message: []const u8) void {
        self.errorAt(&self.parser.previous, message);
    }
};

pub fn compile(allocator: std.mem.Allocator, source: []const u8) CompileError!chunk.Chunk {
    var chk = chunk.Chunk.init(allocator);
    var compiler = Compiler.init(source, &chk);
    compiler.advance();
    compiler.expression() catch |err| {
        chk.deinit();
        return err;
    };
    compiler.consume(.Eof, "Expect end of expression");
    compiler.endCompiler() catch |err| {
        chk.deinit();
        return err;
    };
    if (compiler.parser.err) |err| {
        if (config.trace) {
            debug.disassembleChunk(&chk, "source") catch {
                std.debug.print("Error disassembling chunk", .{});
            };
        }
        chk.deinit();
        return err;
    }
    return chk;
}

fn number(c: *Compiler) CompileError!void {
    const token = c.parser.previous;
    const val = std.fmt.parseFloat(f64, token.start[0..token.len]) catch {
        c.errorAtCurrent("Unable to parse 64bit float.");
        return;
    };
    try c.emitConstant(val);
}

fn grouping(c: *Compiler) CompileError!void {
    try c.expression();
    c.consume(.RightParen, "Expect ')' after expression.");
}

fn unary(c: *Compiler) CompileError!void {
    const op_type = c.parser.previous.type;
    try c.parsePrecedence(.Unary);
    switch (op_type) {
        .Minus => try c.emitCode(.Negate),
        else => unreachable,
    }
}

fn binary(c: *Compiler) CompileError!void {
    const op_type = c.parser.previous.type;
    const rule = getRule(op_type);
    try c.parsePrecedence(rule.precedence.next());

    switch (op_type) {
        .Plus => try c.emitCode(.Add),
        .Minus => try c.emitCode(.Subtract),
        .Star => try c.emitCode(.Multiply),
        .Slash => try c.emitCode(.Divide),
        else => unreachable,
    }
}
