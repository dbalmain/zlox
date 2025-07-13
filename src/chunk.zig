const std = @import("std");
const value = @import("value.zig");
const object = @import("object.zig");

pub const OpCode = enum(u8) {
    Constant,
    Nil,
    True,
    False,
    Equal,
    Greater,
    Less,
    Add,
    Subtract,
    Multiply,
    Divide,
    Not,
    Negate,
    Print,
    Return,
    DefineGlobal,
    GetGlobal,
    SetGlobal,
    Pop,
};

pub const Chunk = struct {
    code: std.ArrayList(u8),
    constants: value.ValueArray,
    lines: std.ArrayList(usize),
    objects: ?*object.Obj = null,

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
        object.free_objects(self.code.allocator, &self.objects);
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
            .Constant => {
                return constantInstruction("OP_CONSTANT", self, offset);
            },
            .Nil => {
                return simpleInstruction("OP_NIL", offset);
            },
            .True => {
                return simpleInstruction("OP_TRUE", offset);
            },
            .False => {
                return simpleInstruction("OP_FALSE", offset);
            },
            .Equal => {
                return simpleInstruction("OP_EQUAL", offset);
            },
            .Greater => {
                return simpleInstruction("OP_GREATER", offset);
            },
            .Less => {
                return simpleInstruction("OP_LESS", offset);
            },
            .Add => {
                return simpleInstruction("OP_ADD", offset);
            },
            .Subtract => {
                return simpleInstruction("OP_SUBTRACT", offset);
            },
            .Multiply => {
                return simpleInstruction("OP_MULTIPLY", offset);
            },
            .Divide => {
                return simpleInstruction("OP_DIVIDE", offset);
            },
            .Not => {
                return simpleInstruction("OP_NOT", offset);
            },
            .Negate => {
                return simpleInstruction("OP_NEGATE", offset);
            },
            .Print => {
                return simpleInstruction("OP_PRINT", offset);
            },
            .Return => {
                return simpleInstruction("OP_RETURN", offset);
            },
            .DefineGlobal => {
                return constantInstruction("OP_DEFINE_GLOBAL", self, offset);
            },
            .GetGlobal => {
                return constantInstruction("OP_GET_GLOBAL", self, offset);
            },
            .SetGlobal => {
                return constantInstruction("OP_SET_GLOBAL", self, offset);
            },
            .Pop => {
                return simpleInstruction("OP_POP", offset);
            },
        }
    }
};

fn constantInstruction(name: []const u8, chunk: *const Chunk, offset: usize) usize {
    const constant = chunk.code.items[offset + 1];
    std.debug.print("{s:<16} {d:>4} ", .{ name, constant });
    value.print(chunk.constants.values.items[constant]);
    std.debug.print("\n", .{});
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

    const return_opcode = @intFromEnum(OpCode.Return);
    try chunk.write(return_opcode, 123);
    try std.testing.expect(chunk.code.items.len == 1);
    try std.testing.expect(chunk.code.items[0] == return_opcode);
    try std.testing.expect(chunk.lines.items[0] == 123);
}
