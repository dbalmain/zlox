const std = @import("std");
const value = @import("value.zig");

pub const OpCode = enum(u8) {
    Constant,
    ConstantLong,
    Add,
    Subtract,
    Multiply,
    Divide,
    Negate,
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

    pub fn init(allocator: std.mem.Allocator) Chunk {
        return .{
            .code = std.ArrayList(u8).init(allocator),
            .constants = value.ValueArray.init(allocator),
            .lines = std.ArrayList(CodeLine).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.code.deinit();
        self.constants.deinit();
        self.lines.deinit();
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

    pub fn writeConstant(self: *Self, val: value.Value, line: u24) !void {
        const index = try self.constants.writeValue(val);
        if (index > 255) {
            try self.writeCode(.ConstantLong, line);
            try self.writeByte(@intCast(index & 0xFF));
            try self.writeByte(@intCast((index >> 8) & 0xFF));
            try self.writeByte(@intCast((index >> 16) & 0xFF));
        } else {
            try self.writeCode(.Constant, line);
            try self.writeByte(@intCast(index));
        }
    }

    pub fn getLine(self: *Self, offset: u24) u24 {
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
