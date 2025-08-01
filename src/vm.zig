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

const STACK_MAX = 256;
pub const VM = struct {
    const Self = @This();

    chunk: *chunk.Chunk,
    ip: [*]u8,
    stack: [STACK_MAX]value.Value,
    sp: [*]value.Value,

    pub fn init(chk: *chunk.Chunk) Self {
        const vm = Self{
            .chunk = chk,
            .ip = undefined,
            .stack = .{0} ** STACK_MAX,
            .sp = undefined,
        };
        return vm;
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
                    self.push(constant);
                },
                .ConstantLong => {
                    const constant = self.readLongConstant();
                    self.push(constant);
                },
                .Add => try self.binaryOperation(.Add),
                .Subtract => try self.binaryOperation(.Subtract),
                .Multiply => try self.binaryOperation(.Multiply),
                .Divide => try self.binaryOperation(.Divide),
                .Negate => self.push(-(try self.pop())),
                .Return => {
                    value.print(try self.pop());
                    std.debug.print("\n", .{});
                    return;
                },
            }
            // print the stack AFTER the instruction is complete
            if (config.trace) {
                std.debug.print("        | ", .{});
                for (0..(&self.sp[0] - &self.stack[0])) |i| {
                    std.debug.print("[ ", .{});
                    value.print(self.stack[i]);
                    std.debug.print(" ]", .{});
                }
                std.debug.print("\n", .{});
            }
        }
    }

    fn binaryOperation(self: *Self, operator: BinaryOperator) !void {
        const right = try self.pop();
        const left = try self.pop();
        switch (operator) {
            .Add => self.push(left + right),
            .Subtract => self.push(left - right),
            .Multiply => self.push(left * right),
            .Divide => {
                if (right == 0.0) {
                    return InterpreterError.RuntimeError;
                }
                self.push(left / right);
            },
        }
    }

    fn resetStack(self: *Self) void {
        self.sp = &self.stack;
    }

    fn push(self: *Self, val: value.Value) void {
        self.sp[0] = val;
        self.sp += 1;
    }

    fn pop(self: *Self) !value.Value {
        if (self.sp == &self.stack) {
            return InterpreterError.StackUnderflow;
        }
        self.sp -= 1;
        return self.sp[0];
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
