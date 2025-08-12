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
        .Constant, .DefineGlobal, .SetGlobal, .GetGlobal => return constantInstruction(self, offset, instruction),
        .ConstantLong, .DefineGlobalLong, .SetGlobalLong, .GetGlobalLong => return constantLongInstruction(self, offset, instruction),
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
    self.constants.values.items[constant].print();
    std.debug.print("'\n", .{});
    return offset + 2;
}

fn constantLongInstruction(self: *const chunk.Chunk, offset: usize, code: chunk.OpCode) !usize {
    const constant = @as(u24, self.code.items[offset + 1]) |
        (@as(u24, self.code.items[offset + 2]) << 8) |
        (@as(u24, self.code.items[offset + 3]) << 16);
    std.debug.print("{s:<18} {d:>4} '", .{ @tagName(code), constant });
    self.constants.values.items[constant].print();
    std.debug.print("'\n", .{});
    return offset + 4;
}
