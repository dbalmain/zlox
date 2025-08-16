const std = @import("std");
const value = @import("value.zig");

pub const OpCode = enum(u8) {
    Constant,
    ConstantLong,
    DefineGlobal,
    DefineGlobalLong,
    GetGlobal,
    GetGlobalLong,
    SetGlobal,
    SetGlobalLong,
    SetLocal,
    GetLocal,
    Nil,
    True,
    False,
    Pop,
    Equal,
    Matches,
    Greater,
    Less,
    Add,
    Subtract,
    Multiply,
    Divide,
    Not,
    Negate,
    Class,
    Fun,
    Var,
    For,
    If,
    While,
    Print,
    Loop,
    Jump,
    JumpIfFalse,
    Or,
    And,
    Break,
    Return,
};

// Skiplist for mapping the code index to the line index
const CodeLine = struct {
    chunk_offset: u24,
    line: u24,
};

pub const Chunk = struct {
    const Self = @This();

    code: std.ArrayList(u8),
    constants: value.ValueArray,
    lines: std.ArrayList(CodeLine),
    names: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) Chunk {
        return .{
            .code = std.ArrayList(u8).init(allocator),
            .constants = value.ValueArray.init(allocator),
            .lines = std.ArrayList(CodeLine).init(allocator),
            .names = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.code.deinit();
        self.constants.deinit();
        self.lines.deinit();
        self.names.deinit();
    }

    pub fn writeByte(self: *Self, byte: u8) !void {
        try self.code.append(byte);
    }

    pub fn writeCode(self: *Self, code: OpCode, line: u24) !void {
        if (self.lines.items.len == 0 or line != self.lines.items[self.lines.items.len - 1].line) {
            try self.lines.append(CodeLine{
                .chunk_offset = @intCast(self.code.items.len),
                .line = line,
            });
        }
        try self.code.append(@intFromEnum(code));
    }

    pub fn makeConstant(self: *Self, val: value.Value) !u24 {
        return self.constants.writeValue(val);
    }

    fn writeMaybeLongArg(self: *Self, index: u24, line: u24, comptime shortCode: OpCode, comptime longCode: OpCode) !void {
        if (index > 255) {
            try self.writeCode(longCode, line);
            try self.writeByte(@intCast(index & 0xFF));
            try self.writeByte(@intCast((index >> 8) & 0xFF));
            try self.writeByte(@intCast((index >> 16) & 0xFF));
        } else {
            try self.writeCode(shortCode, line);
            try self.writeByte(@intCast(index));
        }
    }

    pub fn writeConstant(self: *Self, val: value.Value, line: u24) !void {
        const index = try self.makeConstant(val);
        try self.writeMaybeLongArg(index, line, .Constant, .ConstantLong);
    }

    pub fn defineName(self: *Self, name: []u8) !void {
        try self.names.append(name);
    }

    pub fn defineVariable(self: *Self, index: u24, line: u24) !void {
        try self.writeMaybeLongArg(index, line, .DefineGlobal, .DefineGlobalLong);
    }

    pub fn getGlobal(self: *Self, index: u24, line: u24) !void {
        try self.writeMaybeLongArg(index, line, .GetGlobal, .GetGlobalLong);
    }

    pub fn setGlobal(self: *Self, index: u24, line: u24) !void {
        try self.writeMaybeLongArg(index, line, .SetGlobal, .SetGlobalLong);
    }

    pub fn getLine(self: *const Self, offset: u24) u24 {
        var line: u24 = 0;
        for (self.lines.items) |code_line| {
            if (offset < code_line.chunk_offset) {
                return line;
            }
            line = code_line.line;
        }
        return line;
    }
};
