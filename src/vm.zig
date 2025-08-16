const std = @import("std");
const config = @import("config");
const chunk = @import("chunk.zig");
const value = @import("value.zig");
const object = @import("object.zig");
const debug = @import("debug.zig");

pub const InterpreterError = error{
    RuntimeError,
    StackUnderflow,
};

const BinaryOperator = enum {
    Add,
    Subtract,
    Multiply,
    Divide,
    Less,
    Greater,
};

const STACK_START_CAPACITY = 256;

pub const VM = struct {
    const Self = @This();

    chunk: *const chunk.Chunk,
    ip: [*]u8,
    stack: std.ArrayList(value.Value),
    globals: std.AutoHashMap(u24, value.Value),
    heap: *object.Heap,

    pub fn init(heap: *object.Heap, chk: *const chunk.Chunk) Self {
        const vm = Self{
            .heap = heap,
            .chunk = chk,
            .ip = undefined,
            .stack = std.ArrayList(value.Value).init(heap.allocator),
            .globals = std.AutoHashMap(u24, value.Value).init(heap.allocator),
        };
        return vm;
    }

    pub fn deinit(self: *Self) void {
        self.stack.deinit();
        self.globals.deinit();
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
                .Constant => try self.push(self.readConstant()),
                .ConstantLong => try self.push(self.readLongConstant()),
                .DefineGlobal => try self.defineGlobalVar(self.readByte()),
                .DefineGlobalLong => try self.defineGlobalVar(self.readU24()),
                .SetGlobal => try self.setGlobalVar(self.readByte()),
                .SetGlobalLong => try self.setGlobalVar(self.readU24()),
                .GetGlobal => try self.getGlobalVar(self.readByte()),
                .GetGlobalLong => try self.getGlobalVar(self.readU24()),
                .GetLocal => try self.push(self.stack.items[self.readByte()]),
                .SetLocal => self.stack.items[self.readByte()] = self.peek(0).*,
                .Nil => try self.push(value.nil_val),
                .True => try self.push(value.true_val),
                .False => try self.push(value.false_val),
                .Add => if (self.peek(0).withObject()) |right| {
                    if (self.peek(1).withObject()) |left| {
                        // need to push. Maybe better not to use binaryOperation here? Or make it work with strings.
                        _ = try self.pop();
                        _ = try self.pop();
                        try self.push(value.asObject(left.add(self.heap, right) catch
                            return runtimeError("failed to add objects", .{})));
                    } else return runtimeError("Operands must both be objects", .{});
                } else try self.binaryOperation(.Add),
                .Subtract => try self.binaryOperation(.Subtract),
                .Multiply => try self.binaryOperation(.Multiply),
                .Divide => try self.binaryOperation(.Divide),
                .Less => try self.binaryOperation(.Less),
                .Greater => try self.binaryOperation(.Greater),
                .Negate => if (self.peek(0).withMutableNumber()) |n| {
                    n.* *= -1;
                } else return runtimeError("Operand must be a number", .{}),
                .Not => try self.push(value.asBoolean((try self.pop()).isFalsey())),
                .Equal => try self.push(value.asBoolean((try self.pop()).equals(&try self.pop()))),
                .Print => {
                    (try self.pop()).print();
                    std.debug.print("\n", .{});
                },
                .Pop => {
                    _ = try self.pop();
                },
                .Return => return,
                .Class => {},
                .Fun => {},
                .Var => {},
                .For => {},
                .If => {},
                .While => {},
            }
            // print the stack AFTER the instruction is complete
            if (config.trace) {
                std.debug.print("        | ", .{});
                for (self.stack.items) |val| {
                    std.debug.print("[ ", .{});
                    val.print();
                    std.debug.print(" ]", .{});
                }
                std.debug.print("\n", .{});
            }
        }
    }

    fn binaryOperation(self: *Self, comptime operator: BinaryOperator) !void {
        if ((try self.pop()).withNumber()) |right| {
            if ((try self.pop()).withNumber()) |left| {
                return switch (operator) {
                    .Add => try self.push(value.asNumber(left + right)),
                    .Subtract => try self.push(value.asNumber(left - right)),
                    .Multiply => try self.push(value.asNumber(left * right)),
                    .Divide => {
                        if (right == 0.0) {
                            return runtimeError("Division by 0", .{});
                        }
                        try self.push(value.asNumber(left / right));
                    },
                    .Less => try self.push(value.asBoolean(left < right)),
                    .Greater => try self.push(value.asBoolean(left > right)),
                };
            }
        }
        return runtimeError("Operands must be numbers", .{});
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

    fn peek(self: *Self, comptime distance: usize) *value.Value {
        return &self.stack.items[self.stack.items.len - 1 - distance];
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

    fn readU24(self: *Self) u24 {
        return @as(u24, self.readByte()) |
            @as(u24, self.readByte()) << 8 |
            @as(u24, self.readByte()) << 16;
    }

    fn readLongConstant(self: *Self) value.Value {
        const index = self.readU24();
        return self.chunk.constants.values.items[index];
    }

    fn defineGlobalVar(self: *Self, index: u24) !void {
        // Check for redeclaration
        if (self.globals.contains(index)) {
            return runtimeError("Variable '{s}' already declared.", .{self.chunk.names.items[index]});
        }
        // don't pop before adding the value to the table to prevent garbage collection
        try self.globals.put(index, self.peek(0).*);
        _ = try self.pop();
    }

    fn setGlobalVar(self: *Self, index: u24) !void {
        const previous = try self.globals.fetchPut(index, self.peek(0).*);
        if (previous == null) {
            _ = self.globals.remove(index);
            return runtimeError("Undefined variable '{s}'.", .{self.chunk.names.items[index]});
        }
    }

    fn getGlobalVar(self: *Self, index: u24) !void {
        try self.push(self.globals.get(index) orelse
            return runtimeError("Undefined variable '{s}'.", .{self.chunk.names.items[index]}));
    }
};

fn runtimeError(comptime fmt: []const u8, args: anytype) InterpreterError {
    std.debug.print(fmt, args);
    return InterpreterError.RuntimeError;
}
