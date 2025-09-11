const std = @import("std");
const chunk = @import("chunk.zig");
const value = @import("value.zig");
const types = @import("types.zig");
const VM = @import("vm.zig");
const config = @import("config");

pub var THIS: u24 = undefined;
pub var INIT: u24 = undefined;
pub var SUPER: u24 = undefined;

pub const Local = struct {
    name_index: u24,
    depth: i8,
    is_captured: bool,

    pub fn init(name_index: u24) Local {
        return Local{
            .name_index = name_index,
            .depth = -1,
            .is_captured = false,
        };
    }
};

const Upvalue = struct {
    const Self = @This();
    index: u8,
    is_local: bool,

    fn init(index: u8, is_local: bool) Self {
        return Self{
            .index = index,
            .is_local = is_local,
        };
    }
};

pub const Type = enum(u8) {
    string,
    function,
    native_function,
    closure,
    upvalue,
    class,
    instance,
    bound_method,
};

// Base object header - like C struct inheritance
pub const Obj = struct {
    const Self = @This();
    obj_type: Type,
    is_marked: bool,
    next: ?*Obj,
    pub fn print(self: *Obj, writer: anytype) !void {
        switch (self.obj_type) {
            .class => try asClass(self).print(writer),
            .closure => try asClosure(self).print(writer),
            .function => try asFunction(self).print(writer),
            .instance => try asInstance(self).print(writer),
            .native_function => try writer.print("<native fn>", .{}),
            .string => try writer.print("{s}", .{asString(self).chars}),
            .upvalue => try writer.print("upvalue", .{}),
            .bound_method => try asBoundMethod(self).method.print(writer),
        }
    }

    pub fn isString(self: *const Obj) bool {
        return self.obj_type == .string;
    }

    pub fn isFunction(self: *const Obj) bool {
        return self.obj_type == .function;
    }

    pub fn isClosure(self: *const Obj) bool {
        return self.obj_type == .closure;
    }

    pub fn equals(self: *const Obj, other: *const Obj) bool {
        return self == other;
    }

    pub fn add(self: *const Obj, heap: *Heap, other: *const Obj) !*Obj {
        if (self.obj_type == .string and other.obj_type == .string) {
            const s1 = asString(@constCast(self));
            const s2 = asString(@constCast(other));
            return heap.takeString(try std.mem.concat(heap.allocator, u8, &.{ s1.chars, s2.chars }));
        }
        return Error.TypeMismatch;
    }

    pub fn mark(self: *Obj) void {
        if (!self.is_marked) {
            if (config.gc_log) {
                std.debug.print("{x} mark {s} ", .{ @intFromPtr(self), @tagName(self.obj_type) });
                self.print(std.io.getStdErr().writer()) catch {};
                std.debug.print("\n", .{});
            }
            self.is_marked = true;
            switch (self.obj_type) {
                .class => asClass(self).mark(),
                .instance => asInstance(self).mark(),
                .closure => asClosure(self).mark(),
                .function => asFunction(self).mark(),
                .upvalue => asUpvalue(self).mark(),
                .bound_method => asBoundMethod(self).mark(),
                .string => {},
                .native_function => {},
            }
        }
    }
};

// String object
pub const String = struct {
    const Self = @This();
    obj: Obj,
    chars: []const u8,

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.chars);
    }
};

// Function object
pub const Function = struct {
    const Self = @This();
    obj: Obj,
    chunk: chunk.Chunk,
    arity: u8,
    local_top: u9,
    upvalue_top: u9,
    function_type: FunctionType,
    locals: [LOCAL_MAX]Local,
    upvalues: [LOCAL_MAX]Upvalue,
    name_index: u24,
    heap: *Heap,
    enclosing: ?*Function,

    pub fn mark(self: *Self) void {
        for (self.chunk.constants.values.items) |*v| v.mark();
    }

    pub fn name(self: *const Self) []const u8 {
        return self.heap.names.items[self.name_index];
    }

    pub fn deinit(self: *Self) void {
        self.chunk.deinit();
    }

    pub fn print(self: *Self, writer: anytype) !void {
        try writer.print("<fn {s}>", .{self.name()});
    }

    pub fn resolveLocal(self: *const Self, name_index: u24) FunctionError!?u8 {
        var i = self.local_top;
        while (i > 0) {
            i -= 1;
            const local = self.locals[i];
            if (local.name_index == name_index) {
                if (local.depth == -1) {
                    return FunctionError.VariableDeclarationSelfReference;
                }
                return @intCast(i);
            }
        }
        return null;
    }

    pub fn addLocal(self: *Self, name_index: u24) FunctionError!void {
        if (self.local_top == LOCAL_MAX) {
            return FunctionError.TooManyLocalVariables;
        }
        self.locals[self.local_top] = Local.init(name_index);
        self.local_top += 1;
    }

    pub fn resolveUpvalue(self: *Self, name_index: u24) FunctionError!?u8 {
        const maybe_fun = self.enclosing;
        if (maybe_fun) |fun| {
            if (try fun.resolveLocal(name_index)) |i| {
                fun.locals[i].is_captured = true;
                return self.addUpvalue(i, true);
            }

            if (try fun.resolveUpvalue(name_index)) |i| {
                return self.addUpvalue(i, false);
            }
        }
        return null;
    }

    fn addUpvalue(self: *Self, index: u8, is_local: bool) FunctionError!?u8 {
        for (0..self.upvalue_top) |i| {
            const upvalue = self.upvalues[i];
            if (upvalue.index == index and upvalue.is_local == is_local) {
                return @intCast(i);
            }
        }
        if (self.upvalue_top > std.math.maxInt(u8)) {
            return FunctionError.TooManyClosureVariables;
        }
        self.upvalues[self.upvalue_top] = Upvalue{
            .is_local = is_local,
            .index = index,
        };
        self.upvalue_top += 1;
        return @intCast(self.upvalue_top - 1);
    }
};

// Native function object
pub const NativeFunction = struct {
    const Self = @This();
    obj: Obj,
    call: NativeFn,
    name: []const u8,
    arity: u8,

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

// Closure object
pub const Closure = struct {
    const Self = @This();
    obj: Obj,
    function: *Obj,
    slots: []*Obj,
    heap: *Heap,

    pub fn deinit(self: *Self) void {
        self.heap.allocator.free(self.slots);
    }

    pub fn fun(self: *const Self) *Function {
        return asFunction(self.function);
    }

    pub fn mark(self: *Self) void {
        self.function.mark();
        for (self.slots) |slot| slot.mark();
    }

    pub fn print(self: *Self, writer: anytype) !void {
        try writer.print("<fn {s}>", .{self.fun().name()});
    }
};

// Upvalue object
pub const ObjUpvalue = struct {
    const Self = @This();
    obj: Obj,
    location: *value.Value,
    closed: value.Value,
    next: ?*Obj,

    pub fn mark(self: *Self) void {
        self.location.mark();
    }
};

// Class object
pub const Class = struct {
    const Self = @This();
    obj: Obj,
    name_index: u24,
    methods: std.AutoHashMap(u24, value.Value),
    heap: *Heap,

    pub fn name(self: *const Self) []const u8 {
        return self.heap.names.items[self.name_index];
    }

    pub fn mark(self: *Self) void {
        var method_iterator = self.methods.iterator();
        while (method_iterator.next()) |entry| entry.value_ptr.mark();
    }

    pub fn deinit(self: *Self) void {
        self.methods.deinit();
    }

    pub fn print(self: *Self, writer: anytype) !void {
        try writer.print("{s}", .{self.name()});
    }
};

// Instance object
pub const Instance = struct {
    const Self = @This();
    obj: Obj,
    class: *Obj,
    fields: std.AutoHashMap(u24, value.Value),
    cached_property: u24,

    pub fn mark(self: *Self) void {
        var field_iterator = self.fields.iterator();
        while (field_iterator.next()) |entry| entry.value_ptr.mark();
        self.class.mark();
    }

    pub fn deinit(self: *Self) void {
        self.fields.deinit();
    }

    pub fn getProperty(self: *Self, name: u24) ?value.Value {
        // Check cache first
        if (self.cached_property == name) {
            return self.fields.get(name);
        }

        // Slow path - do lookup and update cache
        if (self.fields.get(name)) |val| {
            self.cached_property = name;
            return val;
        } else {
            // Cache the miss too
            self.cached_property = name;
            return null;
        }
    }

    pub fn setProperty(self: *Self, name: u24, val: value.Value) !void {
        try self.fields.put(name, val);
        // Update cache on set
        self.cached_property = name;
    }

    pub fn print(self: *Self, writer: anytype) !void {
        try writer.print("{s} instance", .{asClass(self.class).name()});
    }
};

// BoundMethod object
pub const BoundMethod = struct {
    const Self = @This();
    obj: Obj,
    receiver: value.Value,
    method: *Obj,

    pub fn mark(self: *Self) void {
        self.receiver.mark();
        self.method.mark();
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

// Type-safe casting functions - like C casts but with runtime checks
pub fn asString(obj: *Obj) *String {
    std.debug.assert(obj.obj_type == .string);
    return @fieldParentPtr("obj", obj);
}

pub fn asFunction(obj: *Obj) *Function {
    std.debug.assert(obj.obj_type == .function);
    return @fieldParentPtr("obj", obj);
}

pub fn asNativeFunction(obj: *Obj) *NativeFunction {
    std.debug.assert(obj.obj_type == .native_function);
    return @fieldParentPtr("obj", obj);
}

pub fn asClosure(obj: *Obj) *Closure {
    std.debug.assert(obj.obj_type == .closure);
    return @fieldParentPtr("obj", obj);
}

pub fn asUpvalue(obj: *Obj) *ObjUpvalue {
    std.debug.assert(obj.obj_type == .upvalue);
    return @fieldParentPtr("obj", obj);
}

pub fn asClass(obj: *Obj) *Class {
    std.debug.assert(obj.obj_type == .class);
    return @fieldParentPtr("obj", obj);
}

pub fn asInstance(obj: *Obj) *Instance {
    std.debug.assert(obj.obj_type == .instance);
    return @fieldParentPtr("obj", obj);
}

pub fn asBoundMethod(obj: *Obj) *BoundMethod {
    std.debug.assert(obj.obj_type == .bound_method);
    return @fieldParentPtr("obj", obj);
}

// Error types
pub const Error = error{
    TypeMismatch,
};

pub const FunctionError = error{
    TooManyLocalVariables,
    TooManyClosureVariables,
    VariableDeclarationSelfReference,
};

pub const LOCAL_MAX = std.math.maxInt(u8) + 1;

pub const FunctionType = enum {
    Function,
    Initialiser,
    Method,
    Script,
};

pub const NativeFn = *const fn (heap: *Heap, arg_count: u8, args: []value.Value) types.InterpreterError!value.Value;

// Heap with updated allocation methods
pub const Heap = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    heap: ?*Obj,
    interned_strings: std.StringHashMap(*Obj),
    names: std.ArrayList([]const u8),
    name_map: std.StringHashMap(u24),
    vm: ?*VM.VM,
    next_gc: usize,
    obj_count: usize,

    pub fn init(allocator: std.mem.Allocator) Heap {
        var self = Heap{
            .allocator = allocator,
            .heap = null,
            .interned_strings = std.StringHashMap(*Obj).init(allocator),
            .names = std.ArrayList([]const u8).init(allocator),
            .name_map = std.StringHashMap(u24).init(allocator),
            .vm = null,
            .next_gc = 0,
            .obj_count = 0,
        };

        self.initKeywords();
        return self;
    }

    fn initKeywords(self: *Heap) void {
        const keywords = [_][]const u8{ "this", "init", "super" };
        const indices = [_]*u24{ &THIS, &INIT, &SUPER };

        inline for (keywords, indices) |keyword, index_ptr| {
            index_ptr.* = self.makeIdentifier(keyword) catch unreachable;
        }
    }

    pub fn deinit(self: *Self) void {
        var obj = self.heap;
        while (obj) |o| {
            obj = o.next;
            self.freeObject(o);
        }
        self.interned_strings.deinit();
        self.names.deinit();
        self.name_map.deinit();
    }

    pub fn makeIdentifier(self: *Self, name: []const u8) !u24 {
        if (self.name_map.get(name)) |index| {
            return index;
        } else {
            const index: u24 = @intCast(self.names.items.len);
            try self.names.append(name);
            try self.name_map.put(name, index);
            return index;
        }
    }

    pub fn copyString(self: *Self, chars: []const u8) !*Obj {
        if (self.interned_strings.get(chars)) |obj| {
            return obj;
        }
        return self.makeString(try self.allocator.dupe(u8, chars));
    }

    pub fn takeString(self: *Self, chars: []const u8) !*Obj {
        if (self.interned_strings.get(chars)) |obj| {
            self.allocator.free(chars);
            return obj;
        }
        return self.makeString(chars);
    }

    fn makeString(self: *Self, chars: []const u8) !*Obj {
        const obj_string = try self.allocateObject(String, .string);
        obj_string.chars = chars;
        try self.interned_strings.put(chars, &obj_string.obj);
        return &obj_string.obj;
    }

    pub fn makeFunction(self: *Self, function_type: FunctionType, name_index: u24, arity: u8, enclosing: ?*Function) !*Obj {
        const obj_function = try self.allocateObject(Function, .function);
        obj_function.* = Function{
            .obj = obj_function.obj,
            .arity = arity,
            .chunk = chunk.Chunk.init(self),
            .local_top = 1,
            .upvalue_top = 0,
            .function_type = function_type,
            .locals = undefined,
            .upvalues = undefined,
            .name_index = name_index,
            .heap = self,
            .enclosing = enclosing,
        };

        // Initialize first local as 'this'
        obj_function.locals[0] = Local{
            .name_index = if (function_type == FunctionType.Function)
                std.math.maxInt(u24)
            else
                THIS,
            .depth = 0,
            .is_captured = false,
        };

        return &obj_function.obj;
    }

    pub fn makeClosure(self: *Self, function: *Obj) !*Obj {
        const obj_function = asFunction(function);
        const obj_closure = try self.allocateObject(Closure, .closure);
        obj_closure.function = function;
        obj_closure.slots = try self.allocator.alloc(*Obj, obj_function.upvalue_top);
        obj_closure.heap = self;
        return &obj_closure.obj;
    }

    pub fn makeMethod(self: *Self, receiver: value.Value, fun: *Obj) !*Obj {
        const obj_bound_method = try self.allocateObject(BoundMethod, .bound_method);
        obj_bound_method.receiver = receiver;
        obj_bound_method.method = fun;
        return &obj_bound_method.obj;
    }

    pub fn makeUpvalue(self: *Self, location: *value.Value) !*Obj {
        const obj_upvalue = try self.allocateObject(ObjUpvalue, .upvalue);
        obj_upvalue.location = location;
        obj_upvalue.next = null;
        obj_upvalue.closed = value.nil_val;
        return &obj_upvalue.obj;
    }

    pub fn makeNativeFunction(self: *Self, name: []const u8, arity: u8, native_function: NativeFn) !*Obj {
        const obj_native = try self.allocateObject(NativeFunction, .native_function);
        obj_native.call = native_function;
        obj_native.name = name;
        obj_native.arity = arity;
        return &obj_native.obj;
    }

    pub fn makeClass(self: *Self, name: u24) !*Obj {
        const obj_class = try self.allocateObject(Class, .class);
        obj_class.name_index = name;
        obj_class.heap = self;
        obj_class.methods = std.AutoHashMap(u24, value.Value).init(self.allocator);
        return &obj_class.obj;
    }

    pub fn makeInstance(self: *Self, class: *Obj) !*Obj {
        const obj_instance = try self.allocateObject(Instance, .instance);
        obj_instance.class = class;
        obj_instance.fields = std.AutoHashMap(u24, value.Value).init(self.allocator);
        obj_instance.cached_property = std.math.maxInt(u24);
        return &obj_instance.obj;
    }

    fn allocateObject(self: *Self, comptime T: type, obj_type: Type) !*T {
        if (config.gc_stress or self.obj_count == self.next_gc) {
            self.collectGarbage();
            self.next_gc = self.obj_count * config.gc_grow_factor;
        }

        const obj = try self.allocator.create(T);

        if (config.gc_log) {
            std.debug.print("{*} allocate {} for {s}\n", .{ obj, @sizeOf(T), @tagName(obj_type) });
        }

        obj.obj = Obj{
            .obj_type = obj_type,
            .is_marked = false,
            .next = self.heap,
        };
        self.heap = &obj.obj;
        self.obj_count += 1;
        return obj;
    }

    fn freeObject(self: *Self, obj: *Obj) void {
        if (config.gc_log) {
            std.debug.print("{*} free type {s} ", .{ obj, @tagName(obj.obj_type) });
            obj.print(std.io.getStdErr().writer()) catch {};
            std.debug.print("\n", .{});
        }

        switch (obj.obj_type) {
            .bound_method => {
                const bound_method = asBoundMethod(obj);
                bound_method.deinit();
                self.allocator.destroy(bound_method);
            },
            .class => {
                const class = asClass(obj);
                class.deinit();
                self.allocator.destroy(class);
            },
            .closure => {
                const closure = asClosure(obj);
                closure.deinit();
                self.allocator.destroy(closure);
            },
            .function => {
                const function = asFunction(obj);
                function.deinit();
                self.allocator.destroy(function);
            },
            .instance => {
                const instance = asInstance(obj);
                instance.deinit();
                self.allocator.destroy(instance);
            },
            .native_function => {
                const native = asNativeFunction(obj);
                native.deinit();
                self.allocator.destroy(native);
            },
            .string => {
                const str = asString(obj);
                _ = self.interned_strings.remove(str.chars);
                str.deinit(self.allocator);
                self.allocator.destroy(str);
            },
            .upvalue => {
                const upvalue = asUpvalue(obj);
                self.allocator.destroy(upvalue);
            },
        }
        self.obj_count -= 1;
    }

    pub fn setVm(self: *Self, vm: *VM.VM) void {
        self.vm = vm;
        self.next_gc = self.obj_count * config.gc_grow_factor;
    }

    fn collectGarbage(self: *Self) void {
        // we don't start collecting garbage until the VM provides a `markRoots` function
        if (self.vm) |vm| {
            if (config.gc_log) {
                std.debug.print("-- gc begin\n", .{});
            }

            vm.markRoots();
            const before = self.obj_count;
            self.sweep();

            if (config.gc_log) {
                std.debug.print("-- gc end\n", .{});
                std.debug.print("   collected {d} objects (from {d} to {d}). Next at {d}\n", .{
                    before - self.obj_count,
                    before,
                    self.obj_count,
                    self.next_gc,
                });
            }
        }
    }

    fn sweep(self: *Self) void {
        var obj_ptr = &self.heap;
        while (obj_ptr.*) |obj| {
            if (obj.is_marked) {
                obj.is_marked = false;
                obj_ptr = &obj.next;
            } else {
                obj_ptr.* = obj.next;
                self.freeObject(obj);
            }
        }
    }
};

pub const Callable = union(enum) {
    const Self = @This();
    function: *Function,
    closure: *Closure,

    pub fn name(self: *const Self) []const u8 {
        return switch (self.*) {
            .function => |fun| fun.name(),
            .closure => |closure| closure.fun().name(),
        };
    }

    pub fn chk(self: *const Self) *const chunk.Chunk {
        return switch (self.*) {
            .function => |fun| &fun.chunk,
            .closure => |closure| &closure.fun().chunk,
        };
    }

    pub fn arity(self: *const Self) u8 {
        return switch (self.*) {
            .function => |fun| fun.arity,
            .closure => |closure| closure.fun().arity,
        };
    }
};
