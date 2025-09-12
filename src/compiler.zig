const std = @import("std");
const scanner = @import("scanner.zig");
const chunk = @import("chunk.zig");
const value = @import("value.zig");
const object = @import("object.zig");
const debug = @import("debug.zig");
const config = @import("config");
const types = @import("types.zig");

const SCRIPT_NAME = "<script>";

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
        .LeftParen => ParseRule.init(grouping, call, .Call),
        .RightParen => ParseRule.init(null, null, .None),
        .LeftBrace => ParseRule.init(null, null, .None),
        .RightBrace => ParseRule.init(null, null, .None),
        .Comma => ParseRule.init(null, null, .None),
        .Dot => ParseRule.init(null, dot, .Call),
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
        .Super => ParseRule.init(super, null, .None),
        .Switch => ParseRule.init(null, null, .None),
        .This => ParseRule.init(this, null, .None),
        .True => ParseRule.init(literal, null, .None),
        .Var => ParseRule.init(null, null, .None),
        .While => ParseRule.init(null, null, .None),
        .Error => ParseRule.init(null, null, .None),
        .Eof => ParseRule.init(null, null, .None),
    };
}

const CompileError = types.CompileError;

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

const ClassCompiler = struct {
    enclosing: ?*ClassCompiler,
    has_super: bool,
};

const Compiler = struct {
    const Self = @This();
    break_address: ?usize,
    can_assign: bool,
    err: ?CompileError,
    fun: *object.Function,
    heap: *object.Heap,
    loop_start: ?usize,
    panic_mode: bool,
    parser: Parser,
    scanner: scanner.Scanner,
    scope_depth: u7,
    current_class: ?*ClassCompiler,

    fn init(
        heap: *object.Heap,
        source: []const u8,
        fun: *object.Function,
    ) CompileError!Self {
        // We put the script name into the heap so it can be printed
        return Compiler{
            .break_address = null,
            .can_assign = true,
            .err = null,
            .fun = fun,
            .heap = heap,
            .loop_start = null,
            .panic_mode = false,
            .parser = Parser.init(),
            .scanner = scanner.Scanner.init(source),
            .scope_depth = 0,
            .current_class = null,
        };
    }

    fn deinit(self: *Self) void {
        _ = self;
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
        self.fun.chunk.writeByte(byte) catch {
            return CompileError.OutOfMemory;
        };
    }

    fn emitCode(self: *Self, code: chunk.OpCode) CompileError!void {
        self.fun.chunk.writeCode(code, self.parser.previous.line) catch {
            return CompileError.OutOfMemory;
        };
    }

    fn emitCodes(self: *Self, code1: chunk.OpCode, code2: chunk.OpCode) CompileError!void {
        self.fun.chunk.writeCode(code1, self.parser.previous.line) catch {
            return CompileError.OutOfMemory;
        };
        self.fun.chunk.writeCode(code2, self.parser.previous.line) catch {
            return CompileError.OutOfMemory;
        };
    }

    fn emitCodeAndByte(self: *Self, code: chunk.OpCode, byte: u8) CompileError!void {
        try self.emitCode(code);
        try self.emitByte(byte);
    }

    fn emitConstant(self: *Self, val: value.Value) CompileError!void {
        self.fun.chunk.writeConstant(val, self.parser.previous.line) catch {
            return CompileError.OutOfMemory;
        };
    }

    fn emitClosure(self: *Self, val: value.Value) CompileError!void {
        self.fun.chunk.writeClosure(val, self.parser.previous.line) catch {
            return CompileError.OutOfMemory;
        };
    }

    fn endCompiler(self: *Self) CompileError!void {
        try self.emitReturn();
    }

    fn emitReturn(self: *Self) CompileError!void {
        if (self.fun.function_type == .Initialiser) {
            try self.emitCodeAndByte(.GetLocal, 0);
        } else {
            try self.emitCode(.Nil);
        }
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
            stderr.print(" at end:", .{}) catch unreachable;
            self.err = CompileError.UnexpectedEof;
        } else if (token.type == .Error) {
            stderr.print(":", .{}) catch unreachable;
            self.err = CompileError.ParseError;
        } else {
            stderr.print(" at '{s}':", .{token.start[0..token.len]}) catch unreachable;
            self.err = CompileError.CompileError;
        }
        stderr.print(" {s}\n", .{message}) catch unreachable;
    }

    fn compileError(self: *Self, message: []const u8) void {
        self.errorAt(&self.parser.previous, message);
    }

    fn handleFunctionError(self: *Self, err: object.FunctionError) void {
        switch (err) {
            error.TooManyClosureVariables,
            => self.compileError("Too many closure variables in function."),
            error.TooManyLocalVariables,
            => self.compileError("Too many local variables in function."),
            error.VariableDeclarationSelfReference,
            => self.compileError("Can't read local variable in its own initializer."),
        }
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
        } else if (self.match(.Fun)) {
            try self.funDeclaration();
        } else if (self.match(.Class)) {
            try self.classDeclaration();
        } else {
            try self.statement();
        }
        if (self.panic_mode) self.synchronise();
    }

    fn varDeclaration(self: *Self) CompileError!void {
        const name = try self.parseVariable("Expect variable name.");

        if (self.match(.Equal)) {
            try self.expression();
        } else {
            try self.emitCode(.Nil);
        }
        self.consume(.Semicolon, "Expect ';' after variable declaration.");

        try self.defineVariable(name);
    }

    fn funDeclaration(self: *Self) CompileError!void {
        const name = try self.parseVariable("Expect function name.");
        self.markInitialised();
        try self.function(.Function, name);
        try self.defineVariable(name);
    }

    fn classDeclaration(self: *Self) CompileError!void {
        const name = try self.parseVariable("Expect class name.");
        self.fun.chunk.defineClass(name, self.parser.previous.line) catch
            return CompileError.OutOfMemory;
        try self.defineVariable(name);
        var class_compiler = ClassCompiler{
            .enclosing = self.current_class,
            .has_super = false,
        };
        self.current_class = &class_compiler;
        if (self.match(.Less)) {
            self.consume(.Identifier, "Expect superclass name.");
            self.can_assign = false;
            const super_class_name = try self.makeIdentifier(&self.parser.previous);
            if (super_class_name == name) {
                return self.compileError("A class can't inherit from itself.");
            }
            try self.namedVariable(super_class_name);

            // Create a new scope to bind 'super' as a local variable.
            // This allows methods in the subclass to reference the superclass
            // via the 'super' keyword, even in closures created within methods.
            // The superclass object will be stored in local slot 0 of this scope.
            self.beginScope();
            self.fun.addLocal(object.SUPER) catch |err|
                return self.handleFunctionError(err);
            try self.defineVariable(0); // 'super' is now a local variable pointing to superclass

            try self.namedVariable(name);
            try self.emitCode(.Inherit); // Copy methods from superclass to subclass
            class_compiler.has_super = true;
        }
        try self.namedVariable(name);
        self.consume(.LeftBrace, "Expect '{' before class body.");
        while (!self.check(.RightBrace) and !self.check(.Eof)) {
            try self.method();
        }
        self.consume(.RightBrace, "Expect '}' after class body.");
        try self.emitCode(.Pop);

        // Clean up the 'super' scope when exiting the class declaration.
        // This ensures 'super' is only available within methods of classes that have a superclass.
        if (class_compiler.has_super) {
            try self.endScope(); // Pops the 'super' local variable from scope
        }
        self.current_class = self.current_class.?.enclosing;
    }

    fn method(self: *Self) CompileError!void {
        self.consume(.Identifier, "Expect method name.");
        const name = try self.makeIdentifier(&self.parser.previous);
        try self.function(if (name == object.INIT) .Initialiser else .Method, name);
        self.fun.chunk.defineMethod(name, self.parser.previous.line) catch
            return CompileError.OutOfMemory;
    }

    fn function(self: *Self, function_type: object.FunctionType, name: u24) CompileError!void {
        const outer_fun = self.fun;
        self.consume(.LeftParen, "Expect '(' after function name.");
        const fun_obj = self.heap.makeFunction(function_type, name, 0, outer_fun) catch return CompileError.OutOfMemory;
        self.fun = fun_obj.asFunction();
        var inner_fun = self.fun;
        self.beginScope();
        if (!self.check(.RightParen)) {
            while (true) {
                if (inner_fun.arity == std.math.maxInt(u8)) {
                    return self.errorAtCurrent("Can't have more than 255 parameters.");
                }
                inner_fun.arity += 1;
                const param = try self.parseVariable("Expect parameter name.");
                try self.defineVariable(param);
                if (!self.match(.Comma)) break;
            }
        }
        self.consume(.RightParen, "Expect ')' after parameters.");
        self.consume(.LeftBrace, "Expect '{' before function body.");
        try self.block();
        try self.endScope();

        try self.emitReturn();

        self.fun = outer_fun;
        const is_closure = inner_fun.upvalue_top > 0;
        if (is_closure) {
            try self.emitClosure(value.fromObject(fun_obj));
        } else {
            try self.emitConstant(value.fromObject(fun_obj));
        }
        for (inner_fun.upvalues[0..inner_fun.upvalue_top]) |upvalue| {
            try self.emitByte(if (upvalue.is_local) 1 else 0);
            try self.emitByte(upvalue.index);
        }
    }

    fn defineVariable(self: *Self, index: u24) CompileError!void {
        if (self.scope_depth > 0) {
            self.markInitialised();
            return;
        }
        self.fun.chunk.defineVariable(index, self.parser.previous.line) catch
            return CompileError.OutOfMemory;
    }

    fn markInitialised(self: *Self) void {
        if (self.scope_depth == 0) return;
        self.fun.locals[self.fun.local_top - 1].depth = self.scope_depth;
    }

    fn statement(self: *Self) CompileError!void {
        self.can_assign = true;
        if (self.match(.Print)) {
            try self.printStatement();
        } else if (self.match(.If)) {
            try self.ifStatement();
        } else if (self.match(.While)) {
            try self.whileStatement();
        } else if (self.match(.For)) {
            try self.forStatement();
        } else if (self.match(.Switch)) {
            try self.switchStatement();
        } else if (self.match(.Continue)) {
            try self.continueStatement();
        } else if (self.match(.Break)) {
            try self.breakStatement();
        } else if (self.match(.Return)) {
            try self.returnStatement();
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

    fn returnStatement(self: *Self) CompileError!void {
        if (self.fun.function_type == .Script) {
            self.compileError("Can't return from top-level code.");
        }
        if (self.match(.Semicolon)) {
            try self.emitReturn();
        } else {
            if (self.fun.function_type == .Initialiser) {
                self.compileError("Can't return a value from an initializer.");
            }

            try self.expression();
            self.consume(.Semicolon, "Expect ';' after return value.");
            try self.emitCode(.Return);
        }
    }

    fn currentOffset(self: *Self) usize {
        return self.fun.chunk.code.items.len;
    }

    /// Emits a jump instruction with placeholder 16-bit offset that will be patched later.
    /// Jump distance is limited to 65,535 bytes (64KB) due to 16-bit encoding.
    /// This affects maximum function size and loop body size in practice.
    fn emitJump(self: *Self, code: chunk.OpCode) CompileError!usize {
        try self.emitCode(code);
        try self.emitByte(0xff);
        try self.emitByte(0xff);
        return self.fun.chunk.code.items.len - 2;
    }

    /// Emits a backward jump instruction for loops with 16-bit distance encoding.
    /// Jump distance limited to 65,535 bytes (64KB). Large loop bodies may exceed
    /// this limit, particularly in complex nested structures or very long functions.
    fn emitLoop(self: *Self, loop_start: usize) CompileError!void {
        const jump = self.fun.chunk.code.items.len - loop_start + 3;
        if (jump > std.math.maxInt(u16)) {
            return self.compileError("Loop body too large.");
        }
        try self.emitCode(.Loop);
        try self.emitByte(@intCast(jump >> 8));
        try self.emitByte(@intCast(jump));
    }

    fn emitBreak(self: *Self, break_address: usize) CompileError!void {
        const jump = self.fun.chunk.code.items.len - break_address + 3;
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
        const jump = self.fun.chunk.code.items.len - offset - 2;
        if (jump > std.math.maxInt(u16)) {
            return self.compileError("Too much code to jump over");
        }
        self.fun.chunk.code.items[offset] = @intCast(jump >> 8);
        self.fun.chunk.code.items[offset + 1] = @intCast(jump);
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
        while (self.fun.local_top > 0) {
            self.fun.local_top -= 1;
            const local = self.fun.locals[self.fun.local_top];
            if (local.depth <= self.scope_depth) break;
            try self.emitCode(if (local.is_captured) .CloseUpvalue else .Pop);
        }
        self.fun.local_top += 1; // local_top points at the next available slot
    }

    fn parseVariable(self: *Self, error_message: []const u8) CompileError!u24 {
        self.consume(.Identifier, error_message);
        const name_index = try self.makeIdentifier(&self.parser.previous);
        if (self.scope_depth > 0) {
            try self.declareVariable(name_index);
        }
        return name_index;
    }

    fn declareVariable(self: *Self, name_index: u24) CompileError!void {
        var i = self.fun.local_top;
        while (i > 0) {
            i -= 1;
            const local = self.fun.locals[i];
            if (local.depth != -1 and local.depth < self.scope_depth) break;
            if (local.name_index == name_index) {
                self.compileError("Already a variable with this name in this scope.");
            }
        }
        self.fun.addLocal(name_index) catch |err|
            return self.handleFunctionError(err);
    }

    fn makeIdentifier(self: *Self, name_token: *scanner.Token) CompileError!u24 {
        const name = name_token.start[0..name_token.len];
        return self.heap.makeIdentifier(name) catch CompileError.OutOfMemory;
    }

    fn namedVariable(self: *Self, name: u24) CompileError!void {
        const local_index = self.fun.resolveLocal(name) catch |err|
            return self.handleFunctionError(err);

        if (self.can_assign and self.match(.Equal)) {
            try self.expression();
            if (local_index) |i| {
                try self.emitCodeAndByte(.SetLocal, i);
            } else if (self.fun.resolveUpvalue(name) catch |err|
                return self.handleFunctionError(err)) |i|
            {
                try self.emitCodeAndByte(.SetUpvalue, i);
            } else {
                try self.setGlobal(name);
            }
        } else {
            if (local_index) |i| {
                try self.emitCodeAndByte(.GetLocal, i);
            } else if (self.fun.resolveUpvalue(name) catch |err|
                return self.handleFunctionError(err)) |i|
            {
                try self.emitCodeAndByte(.GetUpvalue, i);
            } else {
                try self.getGlobal(name);
            }
        }
    }

    fn setGlobal(self: *Self, index: u24) CompileError!void {
        self.fun.chunk.setGlobal(index, self.parser.previous.line) catch
            return CompileError.OutOfMemory;
    }

    fn getGlobal(self: *Self, index: u24) CompileError!void {
        self.fun.chunk.getGlobal(index, self.parser.previous.line) catch
            return CompileError.OutOfMemory;
    }

    fn setProperty(self: *Self, index: u24) CompileError!void {
        self.fun.chunk.setProperty(index, self.parser.previous.line) catch
            return CompileError.OutOfMemory;
    }

    fn getProperty(self: *Self, index: u24) CompileError!void {
        self.fun.chunk.getProperty(index, self.parser.previous.line) catch
            return CompileError.OutOfMemory;
    }

    fn invoke(self: *Self, index: u24) CompileError!void {
        self.fun.chunk.invoke(index, self.parser.previous.line) catch
            return CompileError.OutOfMemory;
    }

    fn emitSuper(self: *Self, index: u24) CompileError!void {
        self.fun.chunk.emitSuper(index, self.parser.previous.line) catch
            return CompileError.OutOfMemory;
    }

    fn emitSuperInvoke(self: *Self, index: u24) CompileError!void {
        self.fun.chunk.emitSuperInvoke(index, self.parser.previous.line) catch
            return CompileError.OutOfMemory;
    }

    fn argumentList(self: *Self) CompileError!u8 {
        var arg_count: u8 = 0;
        if (!self.check(.RightParen)) {
            while (true) {
                try self.expression();
                if (arg_count == std.math.maxInt(u8)) {
                    self.compileError("Can't have more than 255 arguments.");
                    return CompileError.CompileError;
                }
                arg_count += 1;
                if (!self.match(.Comma)) break;
            }
        }
        self.consume(.RightParen, "Expect ')' after arguments.");
        return arg_count;
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
        if (config.trace) {
            if (self.err) |err| {
                debug.disassembleChunk(&self.fun.chunk, self.fun.heap.names.items[self.fun.name_index]) catch {
                    std.debug.print("Error disassembling chunk", .{});
                };
                return err;
            }
        }
    }
};

fn number(c: *Compiler) CompileError!void {
    const token = c.parser.previous;
    const val = std.fmt.parseFloat(f64, token.start[0..token.len]) catch {
        c.errorAtCurrent("Unable to parse 64bit float.");
        return;
    };
    try c.emitConstant(value.fromNumber(val));
}

fn grouping(c: *Compiler) CompileError!void {
    c.can_assign = true;
    try c.expression();
    c.consume(.RightParen, "Expect ')' after expression.");
}

fn call(c: *Compiler) CompileError!void {
    const arg_count = try c.argumentList();
    try c.emitCodeAndByte(.Call, arg_count);
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
    try c.emitConstant(value.fromObject(strObj));
}

fn variable(c: *Compiler) CompileError!void {
    const name = try c.makeIdentifier(&c.parser.previous);
    try c.namedVariable(name);
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

fn dot(c: *Compiler) CompileError!void {
    c.consume(.Identifier, "Expect property name after '.'.");
    const name = try c.makeIdentifier(&c.parser.previous);
    if (c.can_assign and c.match(.Equal)) {
        try c.expression();
        try c.setProperty(name);
    } else if (c.match(.LeftParen)) {
        const arg_count = try c.argumentList();
        try c.invoke(name);
        try c.emitByte(arg_count);
    } else {
        try c.getProperty(name);
    }
}

fn this(c: *Compiler) CompileError!void {
    if (c.current_class == null) {
        return c.compileError("Can't use 'this' outside of a class.");
    }
    const can_assign = c.can_assign;
    c.can_assign = false;
    try variable(c);
    c.can_assign = can_assign;
}

fn super(c: *Compiler) CompileError!void {
    if (c.current_class) |current_class| {
        if (!current_class.has_super) {
            return c.compileError("Can't use 'super' in a class with no superclass.");
        }
        c.consume(.Dot, "Expect '.' after 'super'.");
        c.consume(.Identifier, "Expect superclass method name.");
        const name = try c.makeIdentifier(&c.parser.previous);
        c.can_assign = false;
        try c.namedVariable(object.THIS);
        if (c.match(.LeftParen)) {
            const arg_count = try c.argumentList();
            try c.namedVariable(object.SUPER);
            try c.emitSuperInvoke(name);
            try c.emitByte(arg_count);
        } else {
            try c.namedVariable(object.SUPER);
            try c.emitSuper(name);
        }
    } else {
        return c.compileError("Can't use 'super' outside of a class.");
    }
}

pub fn compile(heap: *object.Heap, source: []const u8) CompileError!*object.Obj {
    const script_name: u24 = heap.makeIdentifier(SCRIPT_NAME) catch return CompileError.OutOfMemory;
    const function_obj = heap.makeFunction(.Script, script_name, 0, null) catch return CompileError.OutOfMemory;
    const function = function_obj.asFunction();
    var compiler = try Compiler.init(heap, source, function);
    defer compiler.deinit();
    try compiler.run();
    if (compiler.err) |err| return err;

    return function_obj;
}
