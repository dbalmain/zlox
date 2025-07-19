const std = @import("std");
const chunk = @import("chunk.zig");
const value = @import("value.zig");

pub fn disassembleChunk(ch: *const chunk.Chunk, name: []const u8) void {
    std.debug.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < ch.code.items.len) {
        offset = disassembleInstruction(ch, offset);
    }
}

pub fn disassembleInstruction(ch: *const chunk.Chunk, offset: usize) usize {
    std.debug.print("{d:0>4} ", .{offset});
    if (offset > 0 and ch.lines.items[offset] == ch.lines.items[offset - 1]) {
        std.debug.print("   | ", .{});
    } else {
        std.debug.print("{d:>4} ", .{ch.lines.items[offset]});
    }

    const instruction: chunk.OpCode = @enumFromInt(ch.code.items[offset]);
    switch (instruction) {
        .Constant => {
            return constantInstruction("OP_CONSTANT", ch, offset);
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
            return constantInstruction("OP_DEFINE_GLOBAL", ch, offset);
        },
        .GetGlobal => {
            return constantInstruction("OP_GET_GLOBAL", ch, offset);
        },
        .SetGlobal => {
            return constantInstruction("OP_SET_GLOBAL", ch, offset);
        },
        .GetLocal => {
            return byteInstruction("OP_GET_LOCAL", ch, offset);
        },
        .SetLocal => {
            return byteInstruction("OP_SET_LOCAL", ch, offset);
        },
        .Pop => {
            return simpleInstruction("OP_POP", offset);
        },
    }
}

fn constantInstruction(name: []const u8, ch: *const chunk.Chunk, offset: usize) usize {
    const constant = ch.code.items[offset + 1];
    std.debug.print("{s:<16} {d:>4} ", .{ name, constant });
    value.print(ch.constants.values.items[constant]);
    std.debug.print("\n", .{});
    return offset + 2;
}

fn simpleInstruction(name: []const u8, offset: usize) usize {
    std.debug.print("{s}\n", .{name});
    return offset + 1;
}

fn byteInstruction(name: []const u8, ch: *const chunk.Chunk, offset: usize) usize {
    const slot = ch.code.items[offset + 1];
    std.debug.print("{s:<16} {d:>4}\n", .{ name, slot });
    return offset + 2;
}
