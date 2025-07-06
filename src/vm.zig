const std = @import("std");
const chunk = @import("chunk.zig");
const value = @import("value.zig");
const compiler = @import("compiler.zig");

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

    pub fn interpret(self: *VM, source: []const u8) InterpretResult {
        var chk = chunk.Chunk.init(std.heap.page_allocator);
        defer chk.deinit();

        if (!compiler.compile(source, &chk)) {
            return .CompileError;
        }

        self.chk = &chk;
        self.ip = self.chk.code.items.ptr;
        self.resetStack();
        return self.run();
    }

    fn resetStack(self: *VM) void {
        self.stackTop = &self.stack;
    }

    fn runtimeError(self: *VM, comptime format: []const u8, args: anytype) InterpretResult {
        std.debug.print(format, args);
        std.debug.print("\n", .{});

        const instruction = self.ip - self.chk.code.items.ptr - 1;
        const line = self.chk.lines.items[instruction];
        std.debug.print("[line {d}] in script\n", .{line});

        self.resetStack();
        return .RuntimeError;
    }

    fn run(self: *VM) InterpretResult {
        while (true) {
            const instruction = self.read_byte();
            switch (@as(chunk.OpCode, @enumFromInt(instruction))) {
                .OpReturn => {
                    value.print(self.pop());
                    std.debug.print("\n", .{});
                    return .Ok;
                },
                .OpAdd => {
                    if (!value.is_number(self.peek(0)) or !value.is_number(self.peek(1))) {
                        return self.runtimeError("Operands must be numbers.", .{});
                    }
                    const b = value.as_number(self.pop());
                    const a = value.as_number(self.pop());
                    self.push(value.number_val(a + b));
                },
                .OpSubtract => {
                    if (!value.is_number(self.peek(0)) or !value.is_number(self.peek(1))) {
                        return self.runtimeError("Operands must be numbers.", .{});
                    }
                    const b = value.as_number(self.pop());
                    const a = value.as_number(self.pop());
                    self.push(value.number_val(a - b));
                },
                .OpMultiply => {
                    if (!value.is_number(self.peek(0)) or !value.is_number(self.peek(1))) {
                        return self.runtimeError("Operands must be numbers.", .{});
                    }
                    const b = value.as_number(self.pop());
                    const a = value.as_number(self.pop());
                    self.push(value.number_val(a * b));
                },
                .OpDivide => {
                    if (!value.is_number(self.peek(0)) or !value.is_number(self.peek(1))) {
                        return self.runtimeError("Operands must be numbers.", .{});
                    }
                    const b = value.as_number(self.pop());
                    const a = value.as_number(self.pop());
                    self.push(value.number_val(a / b));
                },
                .OpNil => self.push(value.NIL_VAL),
                .OpTrue => self.push(value.TRUE_VAL),
                .OpFalse => self.push(value.FALSE_VAL),
                .OpNegate => {
                    if (!value.is_number(self.peek(0))) {
                        return self.runtimeError("Operand must be a number.", .{});
                    }
                    self.push(value.number_val(-value.as_number(self.pop())));
                },
                .OpConstant => {
                    const constant = self.read_byte();
                    const val = self.chk.constants.values.items[constant];
                    self.push(val);
                },
            }
        }
    }

    fn push(self: *VM, val: value.Value) void {
        self.stackTop[0] = val;
        self.stackTop += 1;
    }

    fn pop(self: *VM) value.Value {
        self.stackTop -= 1;
        return self.stackTop[0];
    }

    fn peek(self: *VM, distance: usize) value.Value {
        return self.stackTop[distance];
    }

    fn read_byte(self: *VM) u8 {
        const byte = self.ip[0];
        self.ip += 1;
        return byte;
    }
};
