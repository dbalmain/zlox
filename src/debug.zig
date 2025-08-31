const std = @import("std");
const chunk = @import("chunk.zig");
const value = @import("value.zig");

pub fn disassembleChunk(self: *const chunk.Chunk, name: []const u8) !void {
    std.debug.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    var line: ?usize = self.lines.items[0].line;
    var line_index: usize = 1;
    while (offset < self.code.items.len) {
        if (line_index < self.lines.items.len and
            offset >= self.lines.items[line_index].chunk_offset)
        {
            line = self.lines.items[line_index].line;
            line_index += 1;
        }
        offset = try disassembleInstruction(self, offset, line);
        line = null;
    }
}

pub fn disassembleInstruction(self: *const chunk.Chunk, offset: usize, line: ?usize) !usize {
    std.debug.print("{d:0>4} ", .{offset});
    if (line) |l| {
        std.debug.print("{d:>4} ", .{l});
    } else {
        std.debug.print("   | ", .{});
    }
    const instruction: chunk.OpCode = @enumFromInt(self.code.items[offset]);
    switch (instruction) {
        .Constant => return constantInstruction(self, offset, instruction),
        .ConstantLong => return constantLongInstruction(self, offset, instruction),
        .DefineGlobal,
        .SetGlobal,
        .GetGlobal,
        => return globalVariableInstruction(self, offset, instruction),
        .SetLocal,
        .GetLocal,
        .SetUpvalue,
        .GetUpvalue,
        .Call,
        => return variableInstruction(self, offset, instruction),
        .DefineGlobalLong,
        .SetGlobalLong,
        .GetGlobalLong,
        => return globalVariableLongInstruction(self, offset, instruction),
        .Break,
        .Loop,
        .Jump,
        .JumpIfFalse,
        => return shortVariableInstruction(self, offset, instruction),
        .Closure,
        => return closureInstruction(self, offset, false),
        .ClosureLong,
        => return closureInstruction(self, offset, true),
        else => return simpleInstruction(instruction, offset),
    }
}

fn simpleInstruction(code: chunk.OpCode, offset: usize) !usize {
    std.debug.print("{s}\n", .{@tagName(code)});
    return offset + 1;
}

fn constantInstruction(self: *const chunk.Chunk, offset: usize, code: chunk.OpCode) !usize {
    const constant = self.code.items[offset + 1];
    std.debug.print("{s:<18} {d:>4} '", .{ @tagName(code), constant });
    try self.constants.values.items[constant].print(std.io.getStdErr().writer());
    std.debug.print("'\n", .{});
    return offset + 2;
}

fn constantLongInstruction(self: *const chunk.Chunk, offset: usize, code: chunk.OpCode) !usize {
    const constant = @as(u24, self.code.items[offset + 1]) |
        (@as(u24, self.code.items[offset + 2]) << 8) |
        (@as(u24, self.code.items[offset + 3]) << 16);
    std.debug.print("{s:<18} {d:>4} '", .{ @tagName(code), constant });
    try self.constants.values.items[constant].print(std.io.getStdErr().writer());
    std.debug.print("'\n", .{});
    return offset + 4;
}

fn variableInstruction(self: *const chunk.Chunk, offset: usize, code: chunk.OpCode) !usize {
    const index = self.code.items[offset + 1];
    std.debug.print("{s:<18} {d:>4}\n", .{ @tagName(code), index });
    return offset + 2;
}

fn shortVariableInstruction(self: *const chunk.Chunk, offset: usize, code: chunk.OpCode) !usize {
    const jump: u16 = @as(u16, self.code.items[offset + 1]) << 8 | self.code.items[offset + 2];
    std.debug.print("{s:<18} {d:>4}\n", .{ @tagName(code), jump });
    return offset + 3;
}

fn globalVariableInstruction(self: *const chunk.Chunk, offset: usize, code: chunk.OpCode) !usize {
    const index = self.code.items[offset + 1];
    std.debug.print("{s:<18} {d:>4} '{s}'\n", .{ @tagName(code), index, self.heap.names.items[index] });
    return offset + 2;
}

fn globalVariableLongInstruction(self: *const chunk.Chunk, offset: usize, code: chunk.OpCode) !usize {
    const index = @as(u24, self.code.items[offset + 1]) |
        (@as(u24, self.code.items[offset + 2]) << 8) |
        (@as(u24, self.code.items[offset + 3]) << 16);
    std.debug.print("{s:<18} {d:>4} '{s}'\n", .{ @tagName(code), index, self.heap.names.items[index] });
    return offset + 4;
}

fn closureInstruction(self: *const chunk.Chunk, start_offset: usize, is_long: bool) !usize {
    var offset = start_offset;
    var constant: u24 = undefined;
    if (is_long) {
        constant = @as(u24, self.code.items[offset + 1]) |
            (@as(u24, self.code.items[offset + 2]) << 8) |
            (@as(u24, self.code.items[offset + 3]) << 16);
        offset += 4;
    } else {
        constant = @intCast(self.code.items[offset + 1]);
        offset += 2;
    }
    std.debug.print("{s:<18} {d:>4} \n", .{ @tagName(chunk.OpCode.Closure), constant });
    const function_value = self.constants.values.items[constant];
    try function_value.print(std.io.getStdErr().writer());
    std.debug.print("\n", .{});
    const function = function_value.obj.data.function;
    for (0..function.upvalue_top) |_| {
        const is_local = self.code.items[offset];
        const index = self.code.items[offset + 1];
        std.debug.print("{d:>4}      |                       {s} {d}\n", .{
            offset,
            if (is_local == 1) "local" else "upvalue",
            index,
        });

        offset += 2;
    }

    return offset;
}
