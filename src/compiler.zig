const std = @import("std");
const scanner = @import("scanner.zig");
const chunk = @import("chunk.zig");
const value = @import("value.zig");
const object = @import("object.zig");
const debug = @import("debug.zig");
const config = @import("config");

const LOCAL_MAX = 256;

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
        .Colon => ParseRule.init(null, null, .None),
        .Semicolon => ParseRule.init(null, null, .None),
        .Slash => ParseRule.init(null, binary, .Factor),
        .Star => ParseRule.init(null, binary, .Factor),
        .Bang => ParseRule.init(unary, null, .None),
        .BangEqual => ParseRule.init(null, binary, .Equality),
        .Equal => ParseRule.init(null, null, .None),
        .EqualEqual => ParseRule.init(null, binary, .Equality),
        .Greater => ParseRule.init(null, binary, .Comparison),
        .GreaterEqual => ParseRule.init(null, binary, .Comparison),
        .Less => ParseRule.init(null, binary, .Comparison),
        .LessEqual => ParseRule.init(null, binary, .Comparison),
        .Identifier => ParseRule.init(variable, null, .None),
        .String => ParseRule.init(string, null, .None),
        .Number => ParseRule.init(number, null, .None),
        .And => ParseRule.init(null, and_, .And),
        .Break => ParseRule.init(null, null, .None),
        .Case => ParseRule.init(null, null, .None),
        .Class => ParseRule.init(null, null, .None),
        .Continue => ParseRule.init(null, null, .None),
        .Default => ParseRule.init(null, null, .None),
        .Else => ParseRule.init(null, null, .None),
        .False => ParseRule.init(literal, null, .None),
        .For => ParseRule.init(null, null, .None),
        .Fun => ParseRule.init(null, null, .None),
        .If => ParseRule.init(null, null, .None),
        .Nil => ParseRule.init(literal, null, .None),
        .Or => ParseRule.init(null, or_, .Or),
        .Print => ParseRule.init(null, null, .None),
        .Return => ParseRule.init(null, null, .None),
        .Super => ParseRule.init(null, null, .None),
        .Switch => ParseRule.init(null, null, .None),
        .This => ParseRule.init(null, null, .None),
        .True => ParseRule.init(literal, null, .None),
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
    fn init() Self {
        return Self{
            .current = undefined,
            .previous = undefined,
        };
    }
};

const Local = struct {
    name_index: u24,
    depth: i8,

    fn init(name_index: u24) Local {
        return Local{
            .name_index = name_index,
            .depth = -1,
        };
    }
};

const Compiler = struct {
    const Self = @This();
    heap: *object.Heap,
    scanner: scanner.Scanner,
    chunk: *chunk.Chunk,
    parser: Parser,
    can_assign: bool,
    panic_mode: bool,
    err: ?CompileError,
    names: std.StringHashMap(u24),
    locals: [LOCAL_MAX]Local,
    local_top: u9,
    scope_depth: u7,
    loop_start: ?usize,
    break_address: ?usize,

    fn init(heap: *object.Heap, source: []const u8, chk: *chunk.Chunk) Self {
        return Compiler{
            .heap = heap,
            .scanner = scanner.Scanner.init(source),
            .parser = Parser.init(),
            .chunk = chk,
            .can_assign = true,
            .err = null,
            .panic_mode = false,
            .names = std.StringHashMap(u24).init(heap.allocator),
            .locals = undefined,
            .local_top = 0,
            .scope_depth = 0,
            .loop_start = null,
            .break_address = null,
        };
    }

    fn deinit(self: *Self) void {
        self.names.deinit();
    }

    fn parsePrecedence(self: *Self, precedence: Precedence) CompileError!void {
        self.advance();
        const prefixRule = getRule(self.parser.previous.type).prefix;
        if (prefixRule == null) {
            return self.compileError("Expect expression.");
        }
        if (self.can_assign and !precedence.le(.Assignment)) self.can_assign = false;
        try prefixRule.?(self);
        while (precedence.le(getRule(self.parser.current.type).precedence)) {
            self.advance();
            const infixRule = getRule(self.parser.previous.type).infix.?;
            try infixRule(self);
        }
        if (precedence.le(.Assignment) and self.match(.Equal)) {
            self.compileError("Invalid assignment target.");
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

    fn consume(self: *Self, comptime token_type: scanner.TokenType, message: []const u8) void {
        if (self.parser.current.type == token_type) {
            self.advance();
        } else {
            self.errorAtCurrent(message);
        }
    }

    fn match(self: *Self, comptime token_type: scanner.TokenType) bool {
        if (!self.check(token_type)) return false;
        self.advance();
        return true;
    }

    fn check(self: *Self, comptime token_type: scanner.TokenType) bool {
        return self.parser.current.type == token_type;
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

    fn emitCodes(self: *Self, code1: chunk.OpCode, code2: chunk.OpCode) CompileError!void {
        self.chunk.writeCode(code1, self.parser.previous.line) catch {
            return CompileError.OutOfMemory;
        };
        self.chunk.writeCode(code2, self.parser.previous.line) catch {
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
        if (self.panic_mode) return;
        self.panic_mode = true;
        const stderr = std.io.getStdErr().writer();
        stderr.print("[line {d}] Error", .{token.line}) catch {};
        if (token.type == .Eof) {
            stderr.print(" at end", .{}) catch unreachable;
            self.err = CompileError.UnexpectedEof;
        } else if (token.type == .Error) {
            self.err = CompileError.ParseError;
        } else {
            stderr.print(" at '{s}'", .{token.start[0..token.len]}) catch unreachable;
            self.err = CompileError.CompileError;
        }
        stderr.print(" {s}\n", .{message}) catch unreachable;
    }

    fn compileError(self: *Self, message: []const u8) void {
        self.errorAt(&self.parser.previous, message);
    }

    fn synchronise(self: *Self) void {
        self.panic_mode = false;
        while (self.parser.current.type != .Eof) {
            if (self.parser.previous.type == .Semicolon) return;
            switch (self.parser.current.type) {
                .Class,
                .Fun,
                .Var,
                .For,
                .If,
                .While,
                .Print,
                .Return,
                .Continue,
                .Break,
                .Switch,
                .Case,
                .Default,
                => return,
                else => {},
            }

            self.advance();
        }
    }

    fn declaration(self: *Self) CompileError!void {
        self.can_assign = true;
        if (self.match(.Var)) {
            try self.varDeclaration();
        } else {
            try self.statement();
        }
        if (self.panic_mode) self.synchronise();
    }

    fn varDeclaration(self: *Self) CompileError!void {
        const global = try self.parseVariable("Expect variable name.");

        if (self.match(.Equal)) {
            try self.expression();
        } else {
            try self.emitCode(.Nil);
        }
        self.consume(.Semicolon, "Expect ';' after variable declaration.");

        try self.defineVariable(global);
    }

    fn defineVariable(self: *Self, index: u24) CompileError!void {
        if (self.scope_depth > 0) {
            self.markInitialised();
            return;
        }
        self.chunk.defineVariable(index, self.parser.previous.line) catch
            return CompileError.OutOfMemory;
    }

    fn markInitialised(self: *Self) void {
        self.locals[self.local_top - 1].depth = self.scope_depth;
    }

    fn statement(self: *Self) CompileError!void {
        if (self.match(.Print)) {
            try self.printStatement();
        } else if (self.match(.If)) {
            try self.ifStatement();
        } else if (self.match(.While)) {
            try self.whileStatement();
        } else if (self.match(.For)) {
            try self.forStatement();
        } else if (self.match(.Continue)) {
            try self.continueStatement();
        } else if (self.match(.Break)) {
            try self.breakStatement();
        } else if (self.match(.Switch)) {
            try self.switchStatement();
        } else if (self.match(.LeftBrace)) {
            self.beginScope();
            try self.block();
            try self.endScope();
        } else {
            try self.expressionStatement();
        }
    }

    fn ifStatement(self: *Self) CompileError!void {
        self.consume(.LeftParen, "Expect '(' after 'if'.");
        try self.expression();
        self.consume(.RightParen, "Expect ')' after 'if' condition.");
        const then_jump = try self.emitJump(.JumpIfFalse);
        try self.statement();
        if (self.match(.Else)) {
            const else_jump = try self.emitJump(.Jump);
            try self.patchJump(then_jump);
            try self.statement();
            try self.patchJump(else_jump);
        } else {
            try self.patchJump(then_jump);
        }
    }

    fn whileStatement(self: *Self) CompileError!void {
        self.consume(.LeftParen, "Expect '(' after 'while'.");
        const previous_loop_start = self.loop_start;
        const loop_start = self.currentOffset();
        self.loop_start = loop_start;
        try self.expression();
        self.consume(.RightParen, "Expect ')' after 'while' condition.");
        const exit_jump = try self.emitJump(.JumpIfFalse);
        const previous_break_address = self.break_address;
        self.break_address = exit_jump;
        try self.statement();
        try self.emitLoop(loop_start);
        try self.patchJump(exit_jump);
        self.loop_start = previous_loop_start;
        self.break_address = previous_break_address;
    }

    fn forStatement(self: *Self) CompileError!void {
        self.beginScope();
        self.consume(.LeftParen, "Expect '(' after 'for'.");
        if (self.match(.Semicolon)) {
            // no initialiser
        } else if (self.match(.Var)) {
            try self.varDeclaration();
        } else {
            try self.expressionStatement();
        }
        var loop_start = self.currentOffset();
        var exit_jump: ?usize = null;
        const previous_break_address = self.break_address;
        if (!self.match(.Semicolon)) {
            try self.expression();
            self.consume(.Semicolon, "Expect ';' after 'for' condition.");
            exit_jump = try self.emitJump(.JumpIfFalse);
            self.break_address = exit_jump;
        }
        if (!self.match(.RightParen)) {
            const increment_jump = try self.emitJump(.Jump);
            const loop_increment = self.currentOffset();
            self.can_assign = true;
            try self.expression();
            try self.emitCode(.Pop);
            self.consume(.RightParen, "Expect ')' after 'for' clauses.");
            try self.emitLoop(loop_start);
            loop_start = loop_increment;
            try self.patchJump(increment_jump);
        }
        const previous_loop_start = self.loop_start;
        self.loop_start = loop_start;
        try self.statement();
        try self.emitLoop(loop_start);
        if (exit_jump) |offset| {
            try self.patchJump(offset);
            self.break_address = previous_break_address;
        }
        try self.endScope();
        self.loop_start = previous_loop_start;
    }

    fn switchStatement(self: *Self) CompileError!void {
        self.consume(.LeftParen, "Expect '(' after 'switch'.");
        try self.expression();
        self.consume(.RightParen, "Expect ')' after 'switch'-on expression.");
        self.consume(.LeftBrace, "Expect '{' after 'switch'-on expression closing ')'.");
        var case_jump = try self.emitJump(.Jump);
        const break_address = self.currentOffset();
        const break_jump = try self.emitJump(.Jump);

        while (self.match(.Case)) {
            try self.patchJump(case_jump);
            try self.expression();
            self.consume(.Colon, "Expect ':' after switch 'case' expression.");
            try self.emitCode(.Matches);
            case_jump = try self.emitJump(.JumpIfFalse);
            try self.statement();
            try self.emitLoop(break_address);
        }
        try self.patchJump(case_jump);
        if (self.match(.Default)) {
            self.consume(.Colon, "Expect ':' after switch 'default'.");
            try self.statement();
        }
        try self.patchJump(break_jump);
        // pop switch-on value
        try self.emitCode(.Pop);
        self.consume(.RightBrace, "Expect '}' to close switch statement.");
    }

    fn continueStatement(self: *Self) CompileError!void {
        if (self.loop_start) |loop_start| {
            self.consume(.Semicolon, "Expect ';' after 'continue'.");
            try self.emitLoop(loop_start);
        } else {
            self.compileError("Cannot use 'continue' outside of a loop.");
        }
    }

    fn breakStatement(self: *Self) CompileError!void {
        if (self.break_address) |break_address| {
            self.consume(.Semicolon, "Expect ';' after 'break'.");
            try self.emitBreak(break_address);
        } else {
            self.compileError("Cannot use 'break' outside of a loop.");
        }
    }

    fn currentOffset(self: *Self) usize {
        return self.chunk.code.items.len;
    }

    /// Emits a jump instruction with placeholder 16-bit offset that will be patched later.
    /// Jump distance is limited to 65,535 bytes (64KB) due to 16-bit encoding.
    /// This affects maximum function size and loop body size in practice.
    fn emitJump(self: *Self, code: chunk.OpCode) CompileError!usize {
        try self.emitCode(code);
        try self.emitByte(0xff);
        try self.emitByte(0xff);
        return self.chunk.code.items.len - 2;
    }

    /// Emits a backward jump instruction for loops with 16-bit distance encoding.
    /// Jump distance limited to 65,535 bytes (64KB). Large loop bodies may exceed
    /// this limit, particularly in complex nested structures or very long functions.
    fn emitLoop(self: *Self, loop_start: usize) CompileError!void {
        const jump = self.chunk.code.items.len - loop_start + 3;
        if (jump > std.math.maxInt(u16)) {
            self.compileError("Too much code to jump over");
        }
        try self.emitCode(.Loop);
        try self.emitByte(@intCast(jump >> 8));
        try self.emitByte(@intCast(jump));
    }

    fn emitBreak(self: *Self, break_address: usize) CompileError!void {
        const jump = self.chunk.code.items.len - break_address + 3;
        if (jump > std.math.maxInt(u16)) {
            self.compileError("Too much code to jump over");
        }
        try self.emitCode(.Break);
        try self.emitByte(@intCast(jump >> 8));
        try self.emitByte(@intCast(jump));
    }

    /// Patches a previously emitted jump instruction with the actual 16-bit distance.
    /// Forward jump distance limited to 65,535 bytes (64KB). This constrains the
    /// maximum size of if-statement bodies, function definitions, and other forward jumps.
    fn patchJump(self: *Self, offset: usize) CompileError!void {
        const jump = self.chunk.code.items.len - offset - 2;
        if (jump > std.math.maxInt(u16)) {
            self.compileError("Too much code to jump over");
        }
        self.chunk.code.items[offset] = @intCast(jump >> 8);
        self.chunk.code.items[offset + 1] = @intCast(jump);
    }

    fn block(self: *Self) CompileError!void {
        while (!self.check(.RightBrace) and !self.check(.Eof)) {
            try self.declaration();
        }

        self.consume(.RightBrace, "Expect '}' after block.");
    }

    fn beginScope(self: *Self) void {
        self.scope_depth += 1;
    }

    fn endScope(self: *Self) CompileError!void {
        self.scope_depth -= 1;
        while (self.local_top > 0 and self.locals[self.local_top - 1].depth > self.scope_depth) {
            try self.emitCode(.Pop);
            self.local_top -= 1;
        }
    }

    fn parseVariable(self: *Self, error_message: []const u8) CompileError!u24 {
        self.consume(.Identifier, error_message);
        const name_index = try self.makeIdentifier(&self.parser.previous);
        if (self.scope_depth > 0) {
            self.declareVariable(name_index);
        }
        return name_index;
    }

    fn declareVariable(self: *Self, name_index: u24) void {
        if (self.local_top == LOCAL_MAX) {
            self.compileError("Too many local variables in function");
            return;
        }
        var i = self.local_top;
        while (i > 0) {
            i -= 1;
            const local = self.locals[i];
            if (local.depth != -1 and local.depth < self.scope_depth) break;
            if (local.name_index == name_index) {
                self.compileError("Can't redeclare local variable.");
            }
        }
        self.locals[self.local_top] = Local.init(name_index);
        self.local_top += 1;
    }

    fn resolveLocal(self: *Self, name_index: u24) ?u8 {
        var i = self.local_top;
        while (i > 0) {
            i -= 1;
            const local = self.locals[i];
            if (local.name_index == name_index) {
                if (local.depth == -1) {
                    self.compileError("Can't read local variable in its own initialiser.");
                }
                return @intCast(i);
            }
        }
        return null;
    }

    fn makeIdentifier(self: *Self, name_token: *scanner.Token) CompileError!u24 {
        const name = name_token.start[0..name_token.len];
        if (self.names.get(name)) |index| {
            return index;
        } else {
            const index: u24 = @intCast(self.chunk.names.items.len);
            self.chunk.names.append(name) catch return CompileError.OutOfMemory;
            self.names.put(name, index) catch return CompileError.OutOfMemory;
            return index;
        }
    }

    fn namedVariable(self: *Self, name: *scanner.Token) CompileError!void {
        const index = try self.makeIdentifier(name);
        const local_index = self.resolveLocal(index);
        if (self.can_assign and self.match(.Equal)) {
            try expression(self);
            if (local_index) |i| {
                try self.emitCodeAndByte(.SetLocal, i);
            } else {
                try self.setGlobal(index);
            }
        } else {
            if (local_index) |i| {
                try self.emitCodeAndByte(.GetLocal, i);
            } else {
                try self.getGlobal(index);
            }
        }
    }

    fn setGlobal(self: *Self, index: u24) CompileError!void {
        self.chunk.setGlobal(index, self.parser.previous.line) catch
            return CompileError.OutOfMemory;
    }

    fn getGlobal(self: *Self, index: u24) CompileError!void {
        self.chunk.getGlobal(index, self.parser.previous.line) catch
            return CompileError.OutOfMemory;
    }

    fn printStatement(self: *Self) CompileError!void {
        try expression(self);
        self.consume(.Semicolon, "Expect ';' after print statement.");
        try self.emitCode(.Print);
    }

    fn expressionStatement(self: *Self) CompileError!void {
        try expression(self);
        self.consume(.Semicolon, "Expect ';' after expression.");
        try self.emitCode(.Pop);
    }

    pub fn run(self: *Self) CompileError!void {
        self.advance();
        while (!self.match(.Eof)) {
            try self.declaration();
        }
        try self.endCompiler();
        if (self.err) |err| {
            debug.disassembleChunk(self.chunk, "source") catch {
                std.debug.print("Error disassembling chunk", .{});
            };
            return err;
        }
    }
};

fn number(c: *Compiler) CompileError!void {
    const token = c.parser.previous;
    const val = std.fmt.parseFloat(f64, token.start[0..token.len]) catch {
        c.errorAtCurrent("Unable to parse 64bit float.");
        return;
    };
    try c.emitConstant(value.asNumber(val));
}

fn grouping(c: *Compiler) CompileError!void {
    try c.expression();
    c.consume(.RightParen, "Expect ')' after expression.");
}

fn literal(c: *Compiler) CompileError!void {
    switch (c.parser.previous.type) {
        .False => try c.emitCode(.False),
        .True => try c.emitCode(.True),
        .Nil => try c.emitCode(.Nil),
        else => unreachable,
    }
}

fn unary(c: *Compiler) CompileError!void {
    const op_type = c.parser.previous.type;
    try c.parsePrecedence(.Unary);
    switch (op_type) {
        .Minus => try c.emitCode(.Negate),
        .Bang => try c.emitCode(.Not),
        else => unreachable,
    }
}

fn binary(c: *Compiler) CompileError!void {
    const op_type = c.parser.previous.type;
    const rule = getRule(op_type);
    try c.parsePrecedence(rule.precedence.next());

    switch (op_type) {
        .BangEqual => try c.emitCodes(.Equal, .Not),
        .EqualEqual => try c.emitCode(.Equal),
        .Greater => try c.emitCode(.Greater),
        .GreaterEqual => try c.emitCodes(.Less, .Not),
        .Less => try c.emitCode(.Less),
        .LessEqual => try c.emitCodes(.Greater, .Not),
        .Plus => try c.emitCode(.Add),
        .Minus => try c.emitCode(.Subtract),
        .Star => try c.emitCode(.Multiply),
        .Slash => try c.emitCode(.Divide),
        else => unreachable,
    }
}

fn string(c: *Compiler) CompileError!void {
    const str = c.parser.previous.start[1 .. c.parser.previous.len - 1];
    const strObj = c.heap.copyString(str) catch return CompileError.OutOfMemory;
    try c.emitConstant(value.asObject(strObj));
}

fn variable(c: *Compiler) CompileError!void {
    try c.namedVariable(&c.parser.previous);
}

fn and_(c: *Compiler) CompileError!void {
    const andJump = try c.emitJump(.And);
    try c.emitCode(.Pop);
    try c.parsePrecedence(.And);
    try c.patchJump(andJump);
}

fn or_(c: *Compiler) CompileError!void {
    const orJump = try c.emitJump(.Or);
    try c.emitCode(.Pop);
    try c.parsePrecedence(.Or);
    try c.patchJump(orJump);
}

pub fn compile(heap: *object.Heap, source: []const u8) CompileError!chunk.Chunk {
    var chk = chunk.Chunk.init(heap.allocator);
    errdefer chk.deinit();
    var compiler = Compiler.init(heap, source, &chk);
    defer compiler.deinit();
    try compiler.run();
    if (compiler.err) |err| return err;

    return chk;
}
