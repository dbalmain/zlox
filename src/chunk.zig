const std = @import("std");
const value = @import("value.zig");

pub const OpCode = enum(u8) {
    OpConstant,
    OpAdd,
    OpSubtract,
    OpMultiply,
    OpDivide,
    OpNegate,
    OpReturn,
};

pub const Chunk = struct {
    code: std.ArrayList(u8),
    constants: value.ValueArray,
    lines: std.ArrayList(usize),

    pub fn init(allocator: std.mem.Allocator) Chunk {
        return .{
            .code = std.ArrayList(u8).init(allocator),
            .constants = value.ValueArray.init(allocator),
            .lines = std.ArrayList(usize).init(allocator),
        };
    }

    pub fn deinit(self: *Chunk) void {
        self.code.deinit();
        self.constants.deinit();
        self.lines.deinit();
    }

    pub fn write(self: *Chunk, byte: u8, line: usize) !void {
        try self.code.append(byte);
        try self.lines.append(line);
    }

    pub fn addConstant(self: *Chunk, val: value.Value) !void {
        try self.constants.write(val);
    }

    pub fn disassemble(self: *const Chunk, name: []const u8) void {
        std.debug.print("== {s} ==\n", .{name});

        var offset: usize = 0;
        while (offset < self.code.items.len) {
            offset = self.disassembleInstruction(offset);
        }
    }

    fn disassembleInstruction(self: *const Chunk, offset: usize) usize {
        std.debug.print("{d:0>4} ", .{offset});
        if (offset > 0 and self.lines.items[offset] == self.lines.items[offset - 1]) {
            std.debug.print("   | ", .{});
        } else {
            std.debug.print("{d:>4} ", .{self.lines.items[offset]});
        }

        const instruction: OpCode = @enumFromInt(self.code.items[offset]);
        switch (instruction) {
            .OpConstant => {
                return constantInstruction("OP_CONSTANT", self, offset);
            },
            .OpAdd => {
                return simpleInstruction("OP_ADD", offset);
            },
            .OpSubtract => {
                return simpleInstruction("OP_SUBTRACT", offset);
            },
            .OpMultiply => {
                return simpleInstruction("OP_MULTIPLY", offset);
            },
            .OpDivide => {
                return simpleInstruction("OP_DIVIDE", offset);
            },
            .OpNegate => {
                return simpleInstruction("OP_NEGATE", offset);
            },
            .OpReturn => {
                return simpleInstruction("OP_RETURN", offset);
            }
        }
    }
};

fn constantInstruction(name: []const u8, chunk: *const Chunk, offset: usize) usize {
    const constant = chunk.code.items[offset + 1];
    std.debug.print("{s:<16} {d:>4} ", .{ name, constant });
    std.debug.print("'{any}'\n", .{chunk.constants.values.items[constant]});
    return offset + 2;
}

fn simpleInstruction(name: []const u8, offset: usize) usize {
    std.debug.print("{s}\n", .{name});
    return offset + 1;
}

test "init and deinit chunk" {
    const allocator = std.testing.allocator;
    var chunk = Chunk.init(allocator);
    defer chunk.deinit();

    try std.testing.expect(chunk.code.items.len == 0);
}

test "write to chunk" {
    const allocator = std.testing.allocator;
    var chunk = Chunk.init(allocator);
    defer chunk.deinit();

    const return_opcode = @intFromEnum(OpCode.OpReturn);
    try chunk.write(return_opcode, 123);
    try std.testing.expect(chunk.code.items.len == 1);
    try std.testing.expect(chunk.code.items[0] == return_opcode);
    try std.testing.expect(chunk.lines.items[0] == 123);
}
