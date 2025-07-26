const std = @import("std");
const chunk = @import("chunk.zig");
const value = @import("value.zig");

pub fn disassembleChunk(self: *const chunk.Chunk, name: []const u8) !void {
    std.debug.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < self.code.items.len) {
        offset = try disassembleInstruction(self, offset);
    }
}

pub fn disassembleInstruction(self: *const chunk.Chunk, offset: usize) !usize {
    std.debug.print("{d:0>4} ", .{offset});
    if (offset > 0 and self.lines.items[offset] == self.lines.items[offset - 1]) {
        std.debug.print("   | ", .{});
    } else {
        std.debug.print("{d:>4} ", .{self.lines.items[offset]});
    }
    const instruction: chunk.OpCode = @enumFromInt(self.code.items[offset]);
    switch (instruction) {
        .Constant => return constantInstruction(self, offset),
        else => return simpleInstruction(instruction, offset),
    }
}

fn simpleInstruction(code: chunk.OpCode, offset: usize) !usize {
    std.debug.print("{s}\n", .{@tagName(code)});
    return offset + 1;
}

fn constantInstruction(self: *const chunk.Chunk, offset: usize) !usize {
    const constant = self.code.items[offset + 1];
    std.debug.print("{s:<14} {d:>4} '", .{ "Constant", constant });
    value.print(self.constants.values.items[constant]);
    std.debug.print("'\n", .{});
    return offset + 2;
}
