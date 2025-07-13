const std = @import("std");
const scanner = @import("scanner.zig");
const chunk = @import("chunk.zig");
const value = @import("value.zig");
const object = @import("object.zig");
const table = @import("table.zig");

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

fn get_rule(token_type: scanner.TokenType) ParseRule {
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
        .Bang => .{ .prefix = unary, .infix = null, .precedence = .None },
        .BangEqual => .{ .prefix = null, .infix = binary, .precedence = .Equality },
        .Equal => .{ .prefix = null, .infix = null, .precedence = .None },
        .EqualEqual => .{ .prefix = null, .infix = binary, .precedence = .Equality },
        .Greater => .{ .prefix = null, .infix = binary, .precedence = .Comparison },
        .GreaterEqual => .{ .prefix = null, .infix = binary, .precedence = .Comparison },
        .Less => .{ .prefix = null, .infix = binary, .precedence = .Comparison },
        .LessEqual => .{ .prefix = null, .infix = binary, .precedence = .Comparison },
        .Identifier => .{ .prefix = null, .infix = null, .precedence = .None },
        .String => .{ .prefix = string, .infix = null, .precedence = .None },
        .Number => .{ .prefix = number, .infix = null, .precedence = .None },
        .And => .{ .prefix = null, .infix = null, .precedence = .None },
        .Class => .{ .prefix = null, .infix = null, .precedence = .None },
        .Else => .{ .prefix = null, .infix = null, .precedence = .None },
        .False => .{ .prefix = literal(chunk.OpCode.False), .infix = null, .precedence = .None },
        .For => .{ .prefix = null, .infix = null, .precedence = .None },
        .Fun => .{ .prefix = null, .infix = null, .precedence = .None },
        .If => .{ .prefix = null, .infix = null, .precedence = .None },
        .Nil => .{ .prefix = literal(chunk.OpCode.Nil), .infix = null, .precedence = .None },
        .Or => .{ .prefix = null, .infix = null, .precedence = .None },
        .Print => .{ .prefix = null, .infix = null, .precedence = .None },
        .Return => .{ .prefix = null, .infix = null, .precedence = .None },
        .Super => .{ .prefix = null, .infix = null, .precedence = .None },
        .This => .{ .prefix = null, .infix = null, .precedence = .None },
        .True => .{ .prefix = literal(chunk.OpCode.True), .infix = null, .precedence = .None },
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
    allocator: Allocator,
    parser: Parser,
    scanner: scanner.Scanner,
    compilingChunk: *chunk.Chunk,
    strings: *table.Table,

    pub fn init(allocator: Allocator, source: []const u8, chk: *chunk.Chunk, strings: *table.Table) Compiler {
        return .{
            .allocator = allocator,
            .parser = Parser.init(),
            .scanner = scanner.Scanner.init(source),
            .compilingChunk = chk,
            .strings = strings,
        };
    }

    fn advance(self: *Compiler) void {
        self.parser.previous = self.parser.current;

        while (true) {
            self.parser.current = self.scanner.scan_token();
            if (self.parser.current.type != .Error) break;

            self.error_at_current(self.parser.current.start[0..self.parser.current.length]);
        }
    }

    fn consume(self: *Compiler, token_type: scanner.TokenType, message: []const u8) void {
        if (self.parser.current.type == token_type) {
            self.advance();
            return;
        }

        self.error_at_current(message);
    }

    fn current_chunk(self: *Compiler) *chunk.Chunk {
        return self.compilingChunk;
    }

    fn emit_byte(self: *Compiler, byte: u8) void {
        self.current_chunk().write(byte, self.parser.previous.line) catch |err| {
            std.debug.print("Should not fail: {any}\n", .{err});
        };
    }

    fn emit_bytes(self: *Compiler, byte1: u8, byte2: u8) void {
        self.emit_byte(byte1);
        self.emit_byte(byte2);
    }

    fn emit_return(self: *Compiler) void {
        self.emit_byte(@intFromEnum(chunk.OpCode.Return));
    }

    fn make_constant(self: *Compiler, val: value.Value) !u8 {
        try self.current_chunk().addConstant(val);
        return @intCast(self.current_chunk().constants.values.items.len - 1);
    }

    fn emit_constant(self: *Compiler, val: value.Value) !void {
        const constant = try self.make_constant(val);
        self.emit_bytes(@intFromEnum(chunk.OpCode.Constant), constant);
    }

    fn end(self: *Compiler) void {
        self.emit_return();
    }

    fn parse_precedence(self: *Compiler, precedence: Precedence) !void {
        self.advance();
        const prefixRule = get_rule(self.parser.previous.type).prefix;
        if (prefixRule == null) {
            self.compile_error("Expect expression.");
            return;
        }

        try prefixRule.?(self);

        while (@intFromEnum(precedence) <= @intFromEnum(get_rule(self.parser.current.type).precedence)) {
            self.advance();
            const infixRule = get_rule(self.parser.previous.type).infix.?;
            try infixRule(self);
        }
    }

    fn expression(self: *Compiler) !void {
        try self.parse_precedence(.Assignment);
    }

    fn error_at_current(self: *Compiler, message: []const u8) void {
        self.error_at(&self.parser.current, message);
    }

    fn compile_error(self: *Compiler, message: []const u8) void {
        self.error_at(&self.parser.previous, message);
    }

    fn error_at(self: *Compiler, token: *const scanner.Token, message: []const u8) void {
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
    try c.emit_constant(value.number_val(val));
}

fn literal(comptime op_code: chunk.OpCode) ParseFn {
    return struct {
        fn emit_op_code(c: *Compiler) !void {
            return c.emit_byte(@intFromEnum(op_code));
        }
    }.emit_op_code;
}

fn string(c: *Compiler) !void {
    // The +1 and -2 trim the leading and trailing quotation marks.
    const string_literal = c.parser.previous.start[1 .. c.parser.previous.length - 1];
    const obj = try object.copy_string(c.allocator, string_literal, &c.compilingChunk.objects, c.strings);
    try c.emit_constant(value.object_val(&obj.obj));
}

fn unary(c: *Compiler) !void {
    const operatorType = c.parser.previous.type;

    // Compile the operand.
    try c.parse_precedence(.Unary);

    // Emit the operator instruction.
    switch (operatorType) {
        .Bang => c.emit_byte(@intFromEnum(chunk.OpCode.Not)),
        .Minus => c.emit_byte(@intFromEnum(chunk.OpCode.Negate)),
        else => unreachable,
    }
}

fn binary(c: *Compiler) !void {
    const operatorType = c.parser.previous.type;
    const rule = get_rule(operatorType);
    try c.parse_precedence(@as(Precedence, @enumFromInt(@intFromEnum(rule.precedence) + 1)));

    switch (operatorType) {
        .BangEqual => c.emit_bytes(@intFromEnum(chunk.OpCode.Equal), @intFromEnum(chunk.OpCode.Not)),
        .EqualEqual => c.emit_byte(@intFromEnum(chunk.OpCode.Equal)),
        .Greater => c.emit_byte(@intFromEnum(chunk.OpCode.Greater)),
        .GreaterEqual => c.emit_bytes(@intFromEnum(chunk.OpCode.Less), @intFromEnum(chunk.OpCode.Not)),
        .Less => c.emit_byte(@intFromEnum(chunk.OpCode.Less)),
        .LessEqual => c.emit_bytes(@intFromEnum(chunk.OpCode.Greater), @intFromEnum(chunk.OpCode.Not)),
        .Plus => c.emit_byte(@intFromEnum(chunk.OpCode.Add)),
        .Minus => c.emit_byte(@intFromEnum(chunk.OpCode.Subtract)),
        .Star => c.emit_byte(@intFromEnum(chunk.OpCode.Multiply)),
        .Slash => c.emit_byte(@intFromEnum(chunk.OpCode.Divide)),
        else => unreachable,
    }
}

pub fn compile(allocator: Allocator, source: []const u8, chk: *chunk.Chunk, strings: *table.Table) bool {
    var c = Compiler.init(allocator, source, chk, strings);
    c.advance();
    c.expression() catch |err| {
        std.debug.print("Unhandled compile error: {any}\n", .{err});
        return false;
    };
    c.consume(.Eof, "Expect end of expression.");
    c.end();
    return !c.parser.hadError;
}

test "compile true" {
    const allocator = std.testing.allocator;
    var chk = chunk.Chunk.init(allocator);
    defer chk.deinit();

    const source = "true";
    var strings = table.Table.init(allocator);
    defer strings.deinit();
    const result = compile(allocator, source, &chk, &strings);

    try std.testing.expect(result);
    try std.testing.expectEqual(@as(u8, @intFromEnum(chunk.OpCode.True)), chk.code.items[0]);
    try std.testing.expectEqual(@as(u8, @intFromEnum(chunk.OpCode.Return)), chk.code.items[1]);
}

test "compile false" {
    const allocator = std.testing.allocator;
    var chk = chunk.Chunk.init(allocator);
    defer chk.deinit();

    const source = "false";
    var strings = table.Table.init(allocator);
    defer strings.deinit();
    const result = compile(allocator, source, &chk, &strings);

    try std.testing.expect(result);
    try std.testing.expectEqual(@as(u8, @intFromEnum(chunk.OpCode.False)), chk.code.items[0]);
    try std.testing.expectEqual(@as(u8, @intFromEnum(chunk.OpCode.Return)), chk.code.items[1]);
}

test "compile nil" {
    const allocator = std.testing.allocator;
    var chk = chunk.Chunk.init(allocator);
    defer chk.deinit();

    const source = "nil";
    var strings = table.Table.init(allocator);
    defer strings.deinit();
    const result = compile(allocator, source, &chk, &strings);

    try std.testing.expect(result);
    try std.testing.expectEqual(@as(u8, @intFromEnum(chunk.OpCode.Nil)), chk.code.items[0]);
    try std.testing.expectEqual(@as(u8, @intFromEnum(chunk.OpCode.Return)), chk.code.items[1]);
}

test "compile string" {
    const allocator = std.testing.allocator;
    var chk = chunk.Chunk.init(allocator);
    defer chk.deinit();

    const source = "\"hello\" + \"world\"";
    var strings = table.Table.init(allocator);
    defer strings.deinit();
    const result = compile(allocator, source, &chk, &strings);

    {
        try std.testing.expect(result);
        try std.testing.expectEqual(@as(u8, @intFromEnum(chunk.OpCode.Constant)), chk.code.items[0]);
        const constant_index = chk.code.items[1];
        const constant_value = chk.constants.values.items[constant_index];
        try std.testing.expect(value.is_string(constant_value));
        const string_obj = value.as_object(constant_value);
        try std.testing.expectEqualSlices(u8, "hello", object.as_string_bytes(string_obj));
    }

    {
        try std.testing.expectEqual(@as(u8, @intFromEnum(chunk.OpCode.Constant)), chk.code.items[2]);
        const constant_index = chk.code.items[3];
        const constant_value = chk.constants.values.items[constant_index];
        try std.testing.expect(value.is_string(constant_value));
        const string_obj = value.as_object(constant_value);
        try std.testing.expectEqualSlices(u8, "world", object.as_string_bytes(string_obj));
    }

    try std.testing.expectEqual(@as(u8, @intFromEnum(chunk.OpCode.Add)), chk.code.items[4]);
    try std.testing.expectEqual(@as(u8, @intFromEnum(chunk.OpCode.Return)), chk.code.items[5]);
}
