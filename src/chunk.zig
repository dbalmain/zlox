const std = @import("std");
const value = @import("value.zig");

pub const OpCode = enum(u8) {
    Constant,
    Return,
};

pub const Chunk = struct {
    const Self = @This();

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

    pub fn deinit(self: *Self) void {
        self.code.deinit();
        self.constants.deinit();
        self.lines.deinit();
    }

    pub fn writeByte(self: *Self, byte: u8, line: usize) !void {
        try self.lines.append(line);
        try self.code.append(byte);
    }

    pub fn writeCode(self: *Self, code: OpCode, line: usize) !void {
        try self.lines.append(line);
        try self.code.append(@intFromEnum(code));
    }

    pub fn writeConstant(self: *Self, val: value.Value) !u8 {
        return try self.constants.writeValue(val);
    }
};
