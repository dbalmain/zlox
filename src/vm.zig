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
        self.reset_stack();
        return self.run();
    }

    fn reset_stack(self: *VM) void {
        self.stackTop = &self.stack;
    }

    fn runtime_error(self: *VM, comptime format: []const u8, args: anytype) InterpretResult {
        std.debug.print(format, args);
        std.debug.print("\n", .{});

        const instruction = self.ip - self.chk.code.items.ptr - 1;
        const line = self.chk.lines.items[instruction];
        std.debug.print("[line {d}] in script\n", .{line});

        self.reset_stack();
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
                .OpEqual => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(value.bool_val(value.values_equal(a, b)));
                },
                .OpGreater => if (self.binary_op(.Gt)) |err| return err,
                .OpLess => if (self.binary_op(.Lt)) |err| return err,
                .OpAdd => if (self.binary_op(.Add)) |err| return err,
                .OpSubtract => if (self.binary_op(.Sub)) |err| return err,
                .OpMultiply => if (self.binary_op(.Mul)) |err| return err,
                .OpDivide => if (self.binary_op(.Div)) |err| return err,
                .OpNil => self.push(value.NIL_VAL),
                .OpTrue => self.push(value.TRUE_VAL),
                .OpFalse => self.push(value.FALSE_VAL),
                .OpNot => self.push(value.bool_val(is_falsey(self.pop()))),
                .OpNegate => {
                    if (!value.is_number(self.peek(0))) {
                        return self.runtime_error("Operand must be a number.", .{});
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

    inline fn binary_op(self: *VM, comptime op: enum { Add, Sub, Mul, Div, Gt, Lt }) ?InterpretResult {
        if (!value.is_number(self.peek(0)) or !value.is_number(self.peek(1))) {
            return self.runtime_error("Operands must be numbers.", .{});
        }
        const b = value.as_number(self.pop());
        const a = value.as_number(self.pop());

        switch (op) {
            .Add => self.push(value.number_val(a + b)),
            .Sub => self.push(value.number_val(a - b)),
            .Mul => self.push(value.number_val(a * b)),
            .Div => self.push(value.number_val(a / b)),
            .Gt => self.push(value.bool_val(a > b)),
            .Lt => self.push(value.bool_val(a < b)),
        }
        return null;
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

fn is_falsey(val: value.Value) bool {
    return value.is_nil(val) or (value.is_bool(val) and !value.as_bool(val));
}
