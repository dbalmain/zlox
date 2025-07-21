const std = @import("std");
const chunk = @import("chunk.zig");
const value = @import("value.zig");
const compiler = @import("compiler.zig");
const object = @import("object.zig");
const table = @import("table.zig");

pub const InterpretError = error{
    CompileError,
    RuntimeError,
};

const STACK_MAX = 256;

pub const VM = struct {
    allocator: std.mem.Allocator,
    chk: *chunk.Chunk,
    ip: [*]u8,
    stack: [STACK_MAX]value.Value,
    stackTop: [*]value.Value,
    objects: ?*object.Obj = null,
    strings: table.Table(*object.ObjString),
    globals: table.Table(value.Value),

    pub fn init(allocator: std.mem.Allocator) VM {
        return VM{
            .allocator = allocator,
            .chk = undefined,
            .ip = undefined,
            .stack = undefined,
            .stackTop = undefined,
            .strings = table.Table(*object.ObjString).init(allocator),
            .globals = table.Table(value.Value).init(allocator),
        };
    }

    pub fn deinit(self: *VM) void {
        object.free_objects(self.allocator, &self.objects);
        self.strings.deinit();
        self.globals.deinit();
    }

    pub fn interpret(self: *VM, source: []const u8, chk: *chunk.Chunk) InterpretError!void {
        if (!compiler.compile(self.allocator, source, chk, &self.strings)) {
            return InterpretError.CompileError;
        }

        self.chk = chk;
        self.ip = self.chk.code.items.ptr;
        self.reset_stack();

        try self.run();
    }

    fn reset_stack(self: *VM) void {
        self.stackTop = &self.stack;
    }

    fn runtime_error(self: *VM, comptime format: []const u8, args: anytype) InterpretError!void {
        std.debug.print(format, args);
        std.debug.print("\n", .{});

        const instruction = self.ip - self.chk.code.items.ptr - 1;
        const line = self.chk.lines.items[instruction];
        std.debug.print("[line {d}] in script\n", .{line});

        self.reset_stack();
        return InterpretError.RuntimeError;
    }

    fn run(self: *VM) InterpretError!void {
        while (true) {
            const instruction = self.read_byte();
            switch (@as(chunk.OpCode, @enumFromInt(instruction))) {
                .Return => {
                    return;
                },
                .Print => {
                    value.print(self.pop());
                    std.debug.print("\n", .{});
                },
                .Equal => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(value.bool_val(value.values_equal(a, b)));
                },
                .Greater => try self.binary_op(.Gt),
                .Less => try self.binary_op(.Lt),
                .Add => {
                    if (value.is_string(self.peek(0)) and value.is_string(self.peek(1))) {
                        const b = value.as_object(self.pop());
                        const a = value.as_object(self.pop());
                        const result = value.concatenate(self.allocator, object.as_string(a), object.as_string(b), &self.objects, &self.strings) catch {
                            return self.runtime_error("Could not allocate memory for string concatenation.", .{});
                        };
                        self.push(value.object_val(&result.obj));
                    } else {
                        try self.binary_op(.Add);
                    }
                },
                .Subtract => try self.binary_op(.Sub),
                .Multiply => try self.binary_op(.Mul),
                .Divide => try self.binary_op(.Div),
                .Nil => self.push(value.NIL_VAL),
                .True => self.push(value.TRUE_VAL),
                .False => self.push(value.FALSE_VAL),
                .Not => self.push(value.bool_val(is_falsey(self.pop()))),
                .Negate => {
                    if (!value.is_number(self.peek(0))) {
                        return self.runtime_error("Operand must be a number.", .{});
                    }
                    self.push(value.number_val(-value.as_number(self.pop())));
                },
                .Constant => {
                    const constant = self.read_byte();
                    const val = self.chk.constants.values.items[constant];
                    self.push(val);
                },
                .DefineGlobal => {
                    const name = self.read_name();
                    self.globals.map.put(name.chars, self.peek(0)) catch return self.runtime_error("Out of memory.", .{});
                    _ = self.pop();
                },
                .GetGlobal => {
                    const name = self.read_name();
                    const val = self.globals.map.get(name.chars) orelse {
                        return self.runtime_error("Undefined variable '{s}'.", .{name.chars});
                    };
                    self.push(val);
                },
                .SetGlobal => {
                    const name = self.read_name();
                    const previous = self.globals.map.fetchPut(name.chars, self.peek(0)) catch return self.runtime_error("Out of memory", .{});

                    if (previous == null) {
                        _ = self.globals.map.remove(name.chars);
                        return self.runtime_error("Undefined variable '{s}'.", .{name.chars});
                    }
                },
                .GetLocal => {
                    const slot = self.read_byte();
                    self.push(self.stack[slot]);
                },
                .SetLocal => {
                    const slot = self.read_byte();
                    self.stack[slot] = self.peek(0);
                },
                .Pop => {
                    _ = self.pop();
                },
                .Jump => {
                    const offset = self.read_short();
                    self.ip += offset;
                },
                .JumpIfFalse => {
                    const offset = self.read_short();
                    if (is_falsey(self.peek(0))) self.ip += offset;
                },
                .Loop => {
                    const offset = self.read_short();
                    self.ip -= offset;
                },
            }
        }
    }

    inline fn binary_op(self: *VM, comptime op: enum { Add, Sub, Mul, Div, Gt, Lt }) InterpretError!void {
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
        return self.stack[self.stackTop - &self.stack - 1 - distance];
    }

    fn read_byte(self: *VM) u8 {
        const byte = self.ip[0];
        self.ip += 1;
        return byte;
    }

    fn read_short(self: *VM) u16 {
        const high = self.read_byte();
        const low = self.read_byte();
        return (@as(u16, high) << 8) | low;
    }

    fn read_name(self: *VM) *object.ObjString {
        const constant = self.read_byte();
        return object.as_string(value.as_object(self.chk.constants.values.items[constant]));
    }
};

fn is_falsey(val: value.Value) bool {
    return value.is_nil(val) or (value.is_bool(val) and !value.as_bool(val));
}

test "string concatenation" {
    const allocator = std.testing.allocator;
    var vm = VM.init(allocator);
    defer vm.deinit();

    const source = "var result = \"hello\" + \" world\";";
    var chk = chunk.Chunk.init(allocator);
    defer chk.deinit();

    vm.interpret(source, &chk) catch |err| {
        std.debug.print("Unexpected interpret error: {any}", .{err});
        return err;
    };
    const result_value = vm.globals.map.get("result") orelse {
        std.debug.print("FAIL: The global variable 'result' was not found.\n", .{});
        return error.TestUnexpectedResult;
    };

    try std.testing.expect(value.is_string(result_value));
    const string_obj = value.as_object(result_value);
    try std.testing.expectEqualSlices(u8, "hello world", object.as_string_bytes(string_obj));
}

test "global variables" {
    const allocator = std.testing.allocator;
    var vm = VM.init(allocator);
    defer vm.deinit();

    const source = "var a = 1; var b = 2; var result = a + b;";
    var chk = chunk.Chunk.init(allocator);
    defer chk.deinit();

    vm.interpret(source, &chk) catch |err| {
        std.debug.print("Unexpected interpret error: {any}", .{err});
        return err;
    };
    const result_value = vm.globals.map.get("result") orelse {
        std.debug.print("FAIL: The global variable 'result' was not found.\n", .{});
        return error.TestUnexpectedResult;
    };

    try std.testing.expect(value.is_number(result_value));
    try std.testing.expectEqual(3.0, value.as_number(result_value));
}
