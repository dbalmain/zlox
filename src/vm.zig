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
    callable: object.Callable,
    ip: [*]u8,
    slots: []value.Value,

    fn init(callable: object.Callable, slots: []value.Value) Self {
        return Self{
            .callable = callable,
            .ip = callable.chk().code.items.ptr,
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
        return self.callable.chk().constants.values.items[self.readByte()];
    }

    fn readU24(self: *Self) u24 {
        return @as(u24, self.readByte()) |
            @as(u24, self.readByte()) << 8 |
            @as(u24, self.readByte()) << 16;
    }

    fn readLongConstant(self: *Self) value.Value {
        const index = self.readU24();
        return self.callable.chk().constants.values.items[index];
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
    open_upvalues: ?*object.Obj,

    pub fn init(heap: *object.Heap, function: *object.Obj) !Self {
        var self = Self{
            .heap = heap,
            .frames = undefined,
            .stack = undefined,
            .frames_top = 0,
            .stack_top = 0,
            .globals = std.AutoHashMap(u24, value.Value).init(heap.allocator),
            .open_upvalues = null,
        };

        try self.defineNative("clock", 0, clockNative);
        try self.defineNative("sqrt", 1, sqrtNative);
        try self.defineNative("sin", 1, sinNative);
        try self.defineNative("cos", 1, cosNative);
        try self.defineNative("string", 1, stringNative);

        // The function is already a heap-allocated object
        self.push(value.fromObject(function));

        return self;
    }

    pub fn markRoots(self: *Self) void {
        for (self.stack[0..self.stack_top]) |*v| v.mark();
        var global_iterator = self.globals.iterator();
        while (global_iterator.next()) |entry| entry.value_ptr.mark();
        for (self.frames[0..self.frames_top]) |*frame| {
            for (frame.slots) |*slot| slot.mark();
        }
        var maybe_upvalue = self.open_upvalues;
        while (maybe_upvalue) |upvalue| {
            upvalue.mark();
            maybe_upvalue = object.asUpvalue(upvalue).next;
        }
    }

    pub fn deinit(self: *Self) void {
        self.globals.deinit();
    }

    pub fn run(self: *Self) !void {
        // Set the markRoots function for garbage collection
        self.heap.setVm(self);

        // Now call the function from the heap object
        try self.call(object.Callable{ .function = object.asFunction(self.stack[0].obj) }, 0);
        const stdout = std.io.getStdOut().writer();
        var frame = &self.frames[self.frames_top - 1];
        var previous_line: u24 = 0;
        while (true) {
            if (config.trace) {
                const offset: u24 = @intCast(frame.ip - frame.callable.chk().code.items.ptr);
                const current_line = frame.callable.chk().getLine(offset);
                _ = debug.disassembleInstruction(
                    frame.callable.chk(),
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
                .SetProperty => try self.setPropertyVar(frame.readByte()),
                .SetPropertyLong => try self.setPropertyVar(frame.readU24()),
                .GetProperty => try self.getPropertyVar(frame.readByte()),
                .GetPropertyLong => try self.getPropertyVar(frame.readU24()),
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
                            self.push(value.fromObject(left.add(self.heap, right) catch
                                return self.runtimeError("Operands must be two numbers or two strings.", .{})));
                        } else return self.runtimeError("Operands must be two numbers or two strings.", .{});
                    } else {
                        // Check if both operands are numbers
                        if ((try self.pop()).withNumber()) |right| {
                            if ((try self.pop()).withNumber()) |left| {
                                self.push(value.fromNumber(left + right));
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
                .Not => self.push(value.fromBoolean((try self.pop()).isFalsey())),
                .Equal => self.push(value.fromBoolean((try self.pop()).equals(&try self.pop()))),
                .Matches => self.push(value.fromBoolean((try self.pop()).equals(self.peek(0)))),
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
                    self.closeUpvalues(&frame.slots[0]);
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
                .Closure => try self.makeClosure(frame, frame.readConstant()),
                .ClosureLong => try self.makeClosure(frame, frame.readLongConstant()),
                .GetUpvalue => {
                    const slot = frame.readByte();
                    self.push(object.asUpvalue(frame.callable.closure.slots[slot]).location.*);
                },
                .SetUpvalue => {
                    const slot = frame.readByte();
                    object.asUpvalue(frame.callable.closure.slots[slot]).location.* = self.peek(0).*;
                },
                .CloseUpvalue => {
                    self.closeUpvalues(&self.stack[self.stack_top - 1]);
                    _ = try self.pop();
                },
                .Class => try self.makeClass(@intCast(frame.readByte())),
                .ClassLong => try self.makeClass(frame.readU24()),
                .Method => try self.addMethod(@intCast(frame.readByte())),
                .MethodLong => try self.addMethod(frame.readU24()),
                .Invoke => {
                    try self.invoke(@intCast(frame.readByte()), frame.readByte());
                    frame = &self.frames[self.frames_top - 1];
                },
                .InvokeLong => {
                    try self.invoke(frame.readU24(), frame.readByte());
                    frame = &self.frames[self.frames_top - 1];
                },
                .SuperInvoke => {
                    try self.superInvoke(@intCast(frame.readByte()), frame.readByte());
                    frame = &self.frames[self.frames_top - 1];
                },
                .SuperInvokeLong => {
                    try self.superInvoke(frame.readU24(), frame.readByte());
                    frame = &self.frames[self.frames_top - 1];
                },
                .Super => try self.super(@intCast(frame.readByte())),
                .SuperLong => try self.super(frame.readU24()),
                .Inherit => {
                    if (self.peek(1).withClass()) |super_class| {
                        if (self.peek(0).withClass()) |sub_class| {
                            var method_iterator = super_class.methods.iterator();
                            while (method_iterator.next()) |entry| {
                                try sub_class.methods.put(entry.key_ptr.*, entry.value_ptr.*);
                            }
                            _ = try self.pop();
                        } else {
                            return self.runtimeError("Subclass must be a class.", .{});
                        }
                    } else {
                        return self.runtimeError("Superclass must be a class.", .{});
                    }
                },
                .Fun => {},
                .Var => {},
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

    fn callValue(self: *Self, callee: *const value.Value, arg_count: u8) !void {
        if (callee.withObject()) |obj| {
            switch (obj.obj_type) {
                .class => {
                    const class = object.asClass(obj);
                    self.stack[self.stack_top - arg_count - 1] =
                        value.fromObject(try self.heap.makeInstance(obj));
                    if (class.methods.get(object.INIT)) |*initialiser| {
                        try self.callValue(initialiser, arg_count);
                    } else if (arg_count > 0) {
                        return self.runtimeError("Expected 0 arguments but got {d}.", .{arg_count});
                    }
                    return;
                },
                .closure => {
                    const closure = object.asClosure(obj);
                    return self.call(object.Callable{ .closure = closure }, arg_count);
                },
                .function => {
                    const fun = object.asFunction(obj);
                    return self.call(object.Callable{ .function = fun }, arg_count);
                },
                .native_function => {
                    const fun = object.asNativeFunction(obj);
                    return self.nativeCall(fun, arg_count);
                },
                .bound_method => {
                    const method = object.asBoundMethod(obj);
                    self.stack[self.stack_top - arg_count - 1] = method.receiver;
                    return try self.callValue(&value.fromObject(method.method), arg_count);
                },
                else => {},
            }
        }
        return self.runtimeError("Can only call functions and classes.", .{});
    }

    fn call(self: *Self, callable: object.Callable, arg_count: u8) !void {
        if (arg_count != callable.arity()) {
            return self.runtimeError("Expected {d} arguments but got {d}.", .{ callable.arity(), arg_count });
        }

        if (self.frames_top >= FRAMES_MAX) {
            return self.runtimeError("Stack overflow.", .{});
        }

        const slot_start = self.stack_top - arg_count - 1;
        self.frames[self.frames_top] = CallFrame.init(callable, self.stack[slot_start..]);
        self.frames_top += 1;
    }

    fn nativeCall(self: *Self, fun: *const object.NativeFunction, arg_count: u8) !void {
        if (arg_count != fun.arity) {
            return self.runtimeError("Expected {d} arguments but got {d}.", .{ fun.arity, arg_count });
        }
        const result = fun.call(self.heap, arg_count, self.stack[(self.stack_top - arg_count)..self.stack_top]) catch |err| {
            return switch (err) {
                error.InvalidArgument => self.runtimeError("Invalid argument provided to native function '{s}'.", .{fun.name}),
                else => err,
            };
        };
        self.stack_top = self.stack_top - arg_count - 1;
        self.push(result);
    }

    fn invoke(self: *Self, name: u24, arg_count: u8) !void {
        const receiver = self.peek(arg_count);
        if (receiver.withInstance()) |instance| {
            if (instance.fields.get(name)) |fun| {
                self.stack[self.stack_top - arg_count - 1] = fun;
                return self.callValue(&fun, arg_count);
            }
            return self.invokeFromClass(object.asClass(instance.class), name, arg_count);
        } else {
            return self.runtimeError("Only instances have methods.", .{});
        }
    }

    fn invokeFromClass(self: *Self, class: *object.Class, name: u24, arg_count: u8) !void {
        if (class.methods.get(name)) |method| {
            try self.callValue(&method, arg_count);
        } else {
            return self.runtimeError("Undefined property '{s}'.", .{self.heap.names.items[name]});
        }
    }

    fn makeClass(self: *Self, name: u24) !void {
        self.push(value.fromObject(try self.heap.makeClass(name)));
    }

    fn super(self: *Self, name: u24) !void {
        const superclass = try self.pop();
        if (!try self.bindMethod(superclass.obj, name)) {
            return self.runtimeError("Undefined property '{s}'.", .{self.heap.names.items[name]});
        }
    }

    fn superInvoke(self: *Self, name: u24, arg_count: u8) !void {
        if ((try self.pop()).withClass()) |superclass| {
            try self.invokeFromClass(superclass, name, arg_count);
        } else {
            return self.runtimeError("'super' is not a class.", .{});
        }
    }

    fn addMethod(self: *Self, name: u24) !void {
        const method = self.peek(0);
        var class = object.asClass(self.peek(1).obj);
        try class.methods.put(name, method.*);
        _ = try self.pop();
    }

    fn makeClosure(self: *Self, frame: *CallFrame, fun: value.Value) !void {
        const closure_obj = try self.heap.makeClosure(fun.obj);
        self.push(value.fromObject(closure_obj));
        const closure = object.asClosure(closure_obj);
        const slot_count = closure.slots.len;
        closure.slots.len = 0;
        for (0..slot_count) |i| {
            const is_local = frame.readByte();
            const index = frame.readByte();
            // creating the slot can trigger GC so we keep initialised slot count
            // to only those we've initialised so far.
            const slot = if (is_local == 1)
                try self.captureUpvalue(&frame.slots[index])
            else
                frame.callable.closure.slots[index];
            closure.slots.len += 1;
            closure.slots[i] = slot;
        }
    }

    fn captureUpvalue(self: *Self, location: *value.Value) !*object.Obj {
        var prev_upvalue: ?*object.Obj = null;
        var curr_upvalue = self.open_upvalues;
        while (curr_upvalue) |upvalue| {
            const upvalue_obj = object.asUpvalue(upvalue);
            if (@intFromPtr(upvalue_obj.location) <= @intFromPtr(location)) break;
            prev_upvalue = curr_upvalue;
            curr_upvalue = upvalue_obj.next;
        }
        if (curr_upvalue) |upvalue| {
            if (object.asUpvalue(upvalue).location == location) return upvalue;
        }
        const upvalue = try self.heap.makeUpvalue(location);
        object.asUpvalue(upvalue).next = curr_upvalue;
        if (prev_upvalue) |p_upvalue| {
            object.asUpvalue(p_upvalue).next = upvalue;
        } else {
            self.open_upvalues = upvalue;
        }
        return upvalue;
    }

    fn closeUpvalues(self: *Self, last: *value.Value) void {
        while (self.open_upvalues) |upvalue| {
            const upvalue_obj = object.asUpvalue(upvalue);
            if (@intFromPtr(upvalue_obj.location) < @intFromPtr(last)) break;
            upvalue_obj.closed = upvalue_obj.location.*;
            upvalue_obj.location = &upvalue_obj.closed;
            self.open_upvalues = upvalue_obj.next;
        }
    }

    fn binaryOperation(self: *Self, comptime operator: BinaryOperator) !void {
        if ((try self.pop()).withNumber()) |right| {
            if ((try self.pop()).withNumber()) |left| {
                return switch (operator) {
                    .Add => self.push(value.fromNumber(left + right)),
                    .Subtract => self.push(value.fromNumber(left - right)),
                    .Multiply => self.push(value.fromNumber(left * right)),
                    .Divide => self.push(value.fromNumber(left / right)),
                    .Less => self.push(value.fromBoolean(left < right)),
                    .Greater => self.push(value.fromBoolean(left > right)),
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

    fn defineGlobalVar(self: *Self, name: u24) !void {
        // Check for redeclaration - not done by clox
        // if (self.globals.contains(index)) {
        //     return self.runtimeError("Variable '{s}' already declared.", .{self.heap.names.items[index]});
        // }
        // don't pop before adding the value to the table to prevent garbage collection
        try self.globals.put(name, self.peek(0).*);
        _ = try self.pop();
    }

    fn setGlobalVar(self: *Self, name: u24) !void {
        const previous = try self.globals.fetchPut(name, self.peek(0).*);
        if (previous == null) {
            _ = self.globals.remove(name);
            return self.runtimeError("Undefined variable '{s}'.", .{self.heap.names.items[name]});
        }
    }

    fn getGlobalVar(self: *Self, name: u24) !void {
        self.push(self.globals.get(name) orelse
            return self.runtimeError("Undefined variable '{s}'.", .{self.heap.names.items[name]}));
    }

    fn setPropertyVar(self: *Self, name: u24) !void {
        if (self.peek(1).withInstance()) |instance| {
            try instance.setProperty(name, self.peek(0).*);
            const val = try self.pop();
            _ = try self.pop();
            self.push(val);
        } else {
            return self.runtimeError("Only instances have fields.", .{});
        }
    }

    fn getPropertyVar(self: *Self, name: u24) !void {
        if (self.peek(0).withInstance()) |instance| {
            if (instance.getProperty(name)) |val| {
                _ = try self.pop();
                self.push(val);
            } else if (!try self.bindMethod(instance.class, name)) {
                return self.runtimeError("Undefined property '{s}'.", .{self.heap.names.items[name]});
            }
        } else {
            return self.runtimeError("Only instances have properties.", .{});
        }
    }

    fn bindMethod(self: *Self, class: *object.Obj, name: u24) !bool {
        if (object.asClass(class).methods.get(name)) |method| {
            const bound = try self.heap.makeMethod(self.peek(0).*, method.obj);
            _ = try self.pop();
            self.push(value.fromObject(bound));
            return true;
        } else {
            return false;
        }
    }

    fn runtimeError(self: *Self, comptime fmt: []const u8, args: anytype) InterpreterError {
        std.debug.print(fmt, args);
        std.debug.print("\n", .{});
        var i = self.frames_top;
        while (i > 0) {
            i -= 1;
            const frame = &self.frames[i];
            const callable = frame.callable;
            const offset = frame.ip - callable.chk().code.items.ptr - 1;
            std.debug.print("[line {d}] in {s}\n", .{ callable.chk().getLine(@intCast(offset)), callable.name() });
        }
        return InterpreterError.RuntimeError;
    }

    fn defineNative(self: *Self, comptime name: []const u8, arity: u8, function: object.NativeFn) !void {
        // If we don't get the name, then the native function is never referenced so no need to set.
        if (self.heap.name_map.get(name)) |name_index| {
            self.push(value.fromObject(try self.heap.makeNativeFunction(name, arity, function)));
            try self.globals.put(name_index, self.stack[self.stack_top - 1]);
            _ = try self.pop();
        }
    }
};

fn sinNative(heap: *object.Heap, arg_count: u8, args: []value.Value) InterpreterError!value.Value {
    _ = heap;
    _ = arg_count;
    if (args[0].withNumber()) |n| {
        return value.fromNumber(std.math.sin(n));
    }
    return InterpreterError.InvalidArgument;
}

fn cosNative(heap: *object.Heap, arg_count: u8, args: []value.Value) InterpreterError!value.Value {
    _ = heap;
    _ = arg_count;
    if (args[0].withNumber()) |n| {
        return value.fromNumber(std.math.cos(n));
    }
    return InterpreterError.InvalidArgument;
}

fn sqrtNative(heap: *object.Heap, arg_count: u8, args: []value.Value) InterpreterError!value.Value {
    _ = heap;
    _ = arg_count;
    if (args[0].withNumber()) |n| {
        if (n >= 0) {
            return value.fromNumber(std.math.sqrt(n));
        }
    }
    return InterpreterError.InvalidArgument;
}

fn clockNative(heap: *object.Heap, arg_count: u8, args: []value.Value) InterpreterError!value.Value {
    _ = heap;
    _ = arg_count;
    _ = args;
    return value.fromNumber(@floatFromInt(std.time.milliTimestamp()));
}

fn stringNative(heap: *object.Heap, arg_count: u8, args: []value.Value) InterpreterError!value.Value {
    _ = arg_count;

    // Create a buffer to write the string representation to
    var buffer: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    // Use the existing print method to format the value
    args[0].print(stream.writer()) catch return InterpreterError.RuntimeError;

    // Create a string object from the buffer
    const formatted_str = buffer[0..stream.pos];

    // Create and return the string object
    const string_obj = heap.copyString(formatted_str) catch return InterpreterError.RuntimeError;
    return value.fromObject(string_obj);
}
