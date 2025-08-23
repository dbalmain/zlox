const std = @import("std");
const config = @import("config");
const chunk = @import("chunk.zig");
const value = @import("value.zig");
const object = @import("object.zig");
const debug = @import("debug.zig");
const types = @import("types.zig");

pub const InterpreterError = types.InterpreterError;

const BinaryOperator = enum {
    Add,
    Subtract,
    Multiply,
    Divide,
    Less,
    Greater,
};

const CallFrame = struct {
    const Self = @This();
    function: *const object.Function,
    ip: [*]u8,
    slots: []value.Value,

    fn init(function: *const object.Function, slots: []value.Value) Self {
        return Self{
            .function = function,
            .ip = function.chunk.code.items.ptr,
            .slots = slots,
        };
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

    fn readShort(self: *Self) u16 {
        const short = @as(u16, self.ip[0]) << 8 | self.ip[1];
        self.ip += 2;
        return short;
    }

    fn readConstant(self: *Self) value.Value {
        return self.function.chunk.constants.values.items[self.readByte()];
    }

    fn readU24(self: *Self) u24 {
        return @as(u24, self.readByte()) |
            @as(u24, self.readByte()) << 8 |
            @as(u24, self.readByte()) << 16;
    }

    fn readLongConstant(self: *Self) value.Value {
        const index = self.readU24();
        return self.function.chunk.constants.values.items[index];
    }
};

const FRAMES_MAX = 64;
const STACK_MAX = FRAMES_MAX * std.math.maxInt(u8);

pub const VM = struct {
    const Self = @This();

    frames: [FRAMES_MAX]CallFrame,
    stack: [STACK_MAX]value.Value,
    frames_top: u8,
    stack_top: u16,
    globals: std.AutoHashMap(u24, value.Value),
    heap: *object.Heap,

    pub fn init(heap: *object.Heap, function: object.Function) !Self {
        var self = Self{
            .heap = heap,
            .frames = undefined,
            .stack = undefined,
            .frames_top = 0,
            .stack_top = 0,
            .globals = std.AutoHashMap(u24, value.Value).init(heap.allocator),
        };

        try self.defineNative("clock", 0, clockNative);

        // Create a heap-allocated function object first
        const function_obj = try heap.makeFunction(function);
        self.push(value.asObject(function_obj));

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.globals.deinit();
    }

    pub fn run(self: *Self) !void {
        // Now call the function from the heap object
        try self.call(&self.stack[0].obj.data.function, 0);
        const stdout = std.io.getStdOut().writer();
        var frame = &self.frames[self.frames_top - 1];
        var previous_line: u24 = 0;
        while (true) {
            if (config.trace) {
                const offset: u24 = @intCast(frame.ip - frame.function.chunk.code.items.ptr);
                const current_line = frame.function.chunk.getLine(offset);
                _ = debug.disassembleInstruction(
                    &frame.function.chunk,
                    offset,
                    if (current_line == previous_line) null else current_line,
                ) catch {};
                previous_line = current_line;
            }
            const instruction = try frame.readCode();
            switch (instruction) {
                .Constant => self.push(frame.readConstant()),
                .ConstantLong => self.push(frame.readLongConstant()),
                .DefineGlobal => try self.defineGlobalVar(frame.readByte()),
                .DefineGlobalLong => try self.defineGlobalVar(frame.readU24()),
                .SetGlobal => try self.setGlobalVar(frame.readByte()),
                .SetGlobalLong => try self.setGlobalVar(frame.readU24()),
                .GetGlobal => try self.getGlobalVar(frame.readByte()),
                .GetGlobalLong => try self.getGlobalVar(frame.readU24()),
                .GetLocal => self.push(frame.slots[frame.readByte()]),
                .SetLocal => frame.slots[frame.readByte()] = self.peek(0).*,
                .Nil => self.push(value.nil_val),
                .True => self.push(value.true_val),
                .False => self.push(value.false_val),
                .Add => {
                    // Check if both operands are objects (strings)
                    if (self.peek(0).withObject()) |right| {
                        if (self.peek(1).withObject()) |left| {
                            _ = try self.pop();
                            _ = try self.pop();
                            self.push(value.asObject(left.add(self.heap, right) catch
                                return self.runtimeError("Operands must be two numbers or two strings.", .{})));
                        } else return self.runtimeError("Operands must be two numbers or two strings.", .{});
                    } else {
                        // Check if both operands are numbers
                        if ((try self.pop()).withNumber()) |right| {
                            if ((try self.pop()).withNumber()) |left| {
                                self.push(value.asNumber(left + right));
                            } else return self.runtimeError("Operands must be two numbers or two strings.", .{});
                        } else return self.runtimeError("Operands must be two numbers or two strings.", .{});
                    }
                },
                .Subtract => try self.binaryOperation(.Subtract),
                .Multiply => try self.binaryOperation(.Multiply),
                .Divide => try self.binaryOperation(.Divide),
                .Less => try self.binaryOperation(.Less),
                .Greater => try self.binaryOperation(.Greater),
                .Negate => if (self.peek(0).withMutableNumber()) |n| {
                    n.* *= -1;
                } else return self.runtimeError("Operand must be a number.", .{}),
                .Not => self.push(value.asBoolean((try self.pop()).isFalsey())),
                .Equal => self.push(value.asBoolean((try self.pop()).equals(&try self.pop()))),
                .Matches => self.push(value.asBoolean((try self.pop()).equals(self.peek(0)))),
                .Print => {
                    (try self.pop()).print(stdout) catch {};
                    stdout.print("\n", .{}) catch {};
                },
                .Pop => {
                    _ = try self.pop();
                },
                .JumpIfFalse => {
                    const offset = frame.readShort();
                    if ((try self.pop()).isFalsey()) frame.ip += offset;
                },
                .And => {
                    const offset = frame.readShort();
                    if (self.peek(0).isFalsey()) frame.ip += offset;
                },
                .Or => {
                    const offset = frame.readShort();
                    if (!self.peek(0).isFalsey()) frame.ip += offset;
                },
                .Jump => {
                    const offset = frame.readShort();
                    frame.ip += offset;
                },
                .Loop => {
                    const offset = frame.readShort();
                    frame.ip -= offset;
                },
                .Break => {
                    const break_offset = frame.readShort();
                    frame.ip -= break_offset;
                    const offset = frame.readShort();
                    frame.ip += offset;
                },
                .Call => {
                    const arg_count = frame.readByte();
                    try self.callValue(self.peek(arg_count), arg_count);
                    frame = &self.frames[self.frames_top - 1];
                },
                .Return => {
                    const result = try self.pop();
                    self.frames_top -= 1;
                    if (self.frames_top == 0) {
                        _ = try self.pop();
                        return;
                    }

                    self.stack_top = @intCast(frame.slots.ptr - &self.stack[0]);
                    self.push(result);
                    // Refresh frame pointer after frames.pop()
                    frame = &self.frames[self.frames_top - 1];
                },
                .Class => {},
                .Fun => {},
                .Var => {},
                .For => {},
                .If => {},
                .While => {},
            }
            // print the stack AFTER the instruction is complete
            if (config.trace and self.stack_top > 0) {
                // Add this right before the stack printing loop
                std.debug.print("        | ", .{});
                for (self.stack[0..self.stack_top]) |val| {
                    //for (self.stack[(frame.slots.ptr - &self.stack[0])..self.stack_top]) |val| {
                    std.debug.print("[ ", .{});
                    val.print(std.io.getStdErr().writer()) catch {};
                    std.debug.print(" ]", .{});
                }
                std.debug.print("\n", .{});
            }
        }
    }

    fn callValue(self: *Self, callee: *value.Value, arg_count: u8) !void {
        if (callee.withObject()) |obj| {
            switch (obj.*.data) {
                .function => |*fun| return self.call(fun, arg_count),
                .native_function => |*fun| {
                    const result = try fun.call(arg_count, self.stack[(self.stack_top - arg_count)..self.stack_top]);
                    self.stack_top = self.stack_top - arg_count - 1;
                    self.push(result);
                    return;
                },
                else => {},
            }
        }
        return self.runtimeError("Can only call functions and classes.", .{});
    }

    fn call(self: *Self, fun: *const object.Function, arg_count: u8) !void {
        if (arg_count != fun.arity) {
            return self.runtimeError("Expected {d} arguments but got {d}.", .{ fun.arity, arg_count });
        }

        if (self.frames_top >= FRAMES_MAX) {
            return self.runtimeError("Stack overflow.", .{});
        }

        const slot_start = self.stack_top - arg_count - 1;
        self.frames[self.frames_top] = CallFrame.init(fun, self.stack[slot_start..]);
        self.frames_top += 1;
    }

    fn binaryOperation(self: *Self, comptime operator: BinaryOperator) !void {
        if ((try self.pop()).withNumber()) |right| {
            if ((try self.pop()).withNumber()) |left| {
                return switch (operator) {
                    .Add => self.push(value.asNumber(left + right)),
                    .Subtract => self.push(value.asNumber(left - right)),
                    .Multiply => self.push(value.asNumber(left * right)),
                    .Divide => self.push(value.asNumber(left / right)),
                    .Less => self.push(value.asBoolean(left < right)),
                    .Greater => self.push(value.asBoolean(left > right)),
                };
            }
        }
        return self.runtimeError("Operands must be numbers.", .{});
    }

    fn push(self: *Self, val: value.Value) void {
        if (self.stack_top >= STACK_MAX) {
            std.debug.print("Stack overflow: cannot push more values\n", .{});
            std.process.exit(1);
        }
        self.stack[self.stack_top] = val;
        self.stack_top += 1;
    }

    fn pop(self: *Self) !value.Value {
        if (self.stack_top == 0) return InterpreterError.StackUnderflow;
        self.stack_top -= 1;
        return self.stack[self.stack_top];
    }

    fn peek(self: *Self, distance: usize) *value.Value {
        return &self.stack[self.stack_top - 1 - distance];
    }

    fn defineGlobalVar(self: *Self, index: u24) !void {
        // Check for redeclaration - not done by clox
        // if (self.globals.contains(index)) {
        //     return self.runtimeError("Variable '{s}' already declared.", .{self.heap.names.items[index]});
        // }
        // don't pop before adding the value to the table to prevent garbage collection
        try self.globals.put(index, self.peek(0).*);
        _ = try self.pop();
    }

    fn setGlobalVar(self: *Self, index: u24) !void {
        const previous = try self.globals.fetchPut(index, self.peek(0).*);
        if (previous == null) {
            _ = self.globals.remove(index);
            return self.runtimeError("Undefined variable '{s}'.", .{self.heap.names.items[index]});
        }
    }

    fn getGlobalVar(self: *Self, index: u24) !void {
        self.push(self.globals.get(index) orelse
            return self.runtimeError("Undefined variable '{s}'.", .{self.heap.names.items[index]}));
    }

    fn runtimeError(self: *Self, comptime fmt: []const u8, args: anytype) InterpreterError {
        std.debug.print(fmt, args);
        std.debug.print("\n", .{});
        var i = self.frames_top;
        while (i > 0) {
            i -= 1;
            const frame = &self.frames[i];
            const fun = frame.function;
            const offset = frame.ip - fun.chunk.code.items.ptr - 1;
            std.debug.print("[line {d}] in {s}\n", .{ fun.chunk.getLine(@intCast(offset)), fun.name() });
        }
        return InterpreterError.RuntimeError;
    }

    fn defineNative(self: *Self, comptime name: []const u8, arity: u8, function: object.NativeFn) !void {
        // If we don't get the name, then the native function is never referenced so no need to set.
        if (self.heap.name_map.get(name)) |name_index| {
            self.push(value.asObject(try self.heap.makeNativeFunction(object.NativeFunction.init(name, arity, function))));
            try self.globals.put(name_index, self.stack[self.stack_top - 1]);
            _ = try self.pop();
        }
    }
};

fn clockNative(arg_count: u8, args: []value.Value) InterpreterError!value.Value {
    _ = arg_count;
    _ = args;
    return value.asNumber(@floatFromInt(std.time.milliTimestamp()));
}
