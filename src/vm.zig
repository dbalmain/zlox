const std = @import("std");
const config = @import("config");
const chunk = @import("chunk.zig");
const value = @import("value.zig");
const debug = @import("debug.zig");

pub const InterpreterError = error{
    ParserError,
    CompilerError,
    RuntimeError,
    StackUnderflow,
};

const BinaryOperator = enum {
    Add,
    Subtract,
    Multiply,
    Divide,
};

const STACK_START_CAPACITY = 256;

pub const VM = struct {
    const Self = @This();

    chunk: *chunk.Chunk,
    ip: [*]u8,
    stack: std.ArrayList(value.Value),

    pub fn init(chk: *chunk.Chunk, allocator: std.mem.Allocator) Self {
        const vm = Self{
            .chunk = chk,
            .ip = undefined,
            .stack = std.ArrayList(value.Value).init(allocator),
        };
        return vm;
    }

    pub fn deinit(self: *Self) void {
        self.stack.deinit();
    }

    pub fn run(self: *Self) !void {
        self.ip = self.chunk.code.items.ptr;
        self.resetStack();
        var previous_line: u24 = 0;
        while (true) {
            if (config.trace) {
                const offset: u24 = @intCast(self.ip - self.chunk.code.items.ptr);
                const current_line = self.chunk.getLine(offset);
                _ = try debug.disassembleInstruction(
                    self.chunk,
                    offset,
                    if (current_line == previous_line) null else current_line,
                );
                previous_line = current_line;
            }
            const instruction = try self.readCode();
            switch (instruction) {
                .Constant => {
                    const constant = self.readConstant();
                    try self.push(constant);
                },
                .ConstantLong => {
                    const constant = self.readLongConstant();
                    try self.push(constant);
                },
                .Add => try self.binaryOperation(.Add),
                .Subtract => try self.binaryOperation(.Subtract),
                .Multiply => try self.binaryOperation(.Multiply),
                .Divide => try self.binaryOperation(.Divide),
                .Negate => self.stack.items[self.stack.items.len - 1] *= -1,
                .Print => {
                    value.print(try self.pop());
                    std.debug.print("\n", .{});
                },
                .Return => {
                    value.print(try self.pop());
                    std.debug.print("\n", .{});
                    return;
                },
            }
            // print the stack AFTER the instruction is complete
            if (config.trace) {
                std.debug.print("        | ", .{});
                for (self.stack.items) |val| {
                    std.debug.print("[ ", .{});
                    value.print(val);
                    std.debug.print(" ]", .{});
                }
                std.debug.print("\n", .{});
            }
        }
    }

    fn binaryOperation(self: *Self, comptime operator: BinaryOperator) !void {
        const right = try self.pop();
        const left = try self.pop();
        switch (operator) {
            .Add => try self.push(left + right),
            .Subtract => try self.push(left - right),
            .Multiply => try self.push(left * right),
            .Divide => {
                if (right == 0.0) {
                    return InterpreterError.RuntimeError;
                }
                try self.push(left / right);
            },
        }
    }

    fn resetStack(self: *Self) void {
        self.stack.clearRetainingCapacity();
    }

    fn push(self: *Self, val: value.Value) !void {
        try self.stack.append(val);
    }

    fn pop(self: *Self) !value.Value {
        return self.stack.pop() orelse InterpreterError.StackUnderflow;
    }

    fn readCode(self: *Self) !chunk.OpCode {
        const byte = self.readByte();
        return std.meta.intToEnum(chunk.OpCode, byte) catch {
            return InterpreterError.RuntimeError;
        };
    }

    fn readByte(self: *Self) u8 {
        const byte = self.ip[0];
        self.ip += 1;
        return byte;
    }

    fn readConstant(self: *Self) value.Value {
        return self.chunk.constants.values.items[self.readByte()];
    }

    fn readLongConstant(self: *Self) value.Value {
        const index = @as(u24, self.readByte()) |
            @as(u24, self.readByte()) << 8 |
            @as(u24, self.readByte()) << 16;
        return self.chunk.constants.values.items[index];
    }
};
