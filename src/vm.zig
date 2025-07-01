const std = @import("std");
const chunk = @import("chunk.zig");
const value = @import("value.zig");

pub const InterpretResult = enum {
    Ok,
    CompileError,
    RuntimeError,
};

const STACK_MAX = 256;

pub const VM = struct {
    chk: *chunk.Chunk,
    ip: [*]u8,
    stack: [STACK_MAX]value.Value,
    stackTop: [*]value.Value,

    pub fn init() VM {
        return VM{
            .chk = undefined,
            .ip = undefined,
            .stack = undefined,
            .stackTop = undefined,
        };
    }

    pub fn deinit(_: *VM) void {}

    pub fn interpret(self: *VM, chk: *chunk.Chunk) !InterpretResult {
        self.chk = chk;
        self.ip = self.chk.code.items.ptr;
        self.resetStack();
        return self.run();
    }

    fn resetStack(self: *VM) void {
        self.stackTop = &self.stack;
    }

    fn run(self: *VM) !InterpretResult {
        while (true) {
            const instruction = self.read_byte();
            switch (@as(chunk.OpCode, @enumFromInt(instruction))) {
                .OpReturn => {
                    const val = self.pop();
                    std.debug.print("{any}\n", .{val});
                    return .Ok;
                },
                .OpAdd => try self.binaryOp(.Add),
                .OpSubtract => try self.binaryOp(.Subtract),
                .OpMultiply => try self.binaryOp(.Multiply),
                .OpDivide => try self.binaryOp(.Divide),
                .OpNegate => {
                    const val = self.pop();
                    try self.push(-val);
                },
                .OpConstant => {
                    const constant = self.read_byte();
                    const val = self.chk.constants.values.items[constant];
                    try self.push(val);
                },
            }
        }
    }

    fn binaryOp(self: *VM, comptime op: enum { Add, Subtract, Multiply, Divide }) !void {
        const b = self.pop();
        const a = self.pop();
        switch (op) {
            .Add => try self.push(a + b),
            .Subtract => try self.push(a - b),
            .Multiply => try self.push(a * b),
            .Divide => try self.push(a / b),
        }
    }


    fn push(self: *VM, val: value.Value) !void {
        self.stackTop[0] = val;
        self.stackTop += 1;
    }

    fn pop(self: *VM) value.Value {
        self.stackTop -= 1;
        return self.stackTop[0];
    }

    fn read_byte(self: *VM) u8 {
        const byte = self.ip[0];
        self.ip += 1;
        return byte;
    }
};
