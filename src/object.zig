const std = @import("std");
const chunk = @import("chunk.zig");
const value = @import("value.zig");
const types = @import("types.zig");
const VM = @import("vm.zig");
const config = @import("config");

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
        return Heap{
            .allocator = allocator,
            .heap = null,
            .interned_strings = std.StringHashMap(*Obj).init(allocator),
            .names = std.ArrayList([]const u8).init(allocator),
            .name_map = std.StringHashMap(u24).init(allocator),
            .vm = null,
            .next_gc = 0,
            .obj_count = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        var obj = self.heap;
        while (obj) |o| {
            obj = o.next;
            o.deinit(self);
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
        const obj = try self.allocateObj("string", Obj.Data{
            .string = String{ .chars = chars },
        });
        try self.interned_strings.put(chars, obj);
        return obj;
    }

    pub fn makeFunction(self: *Self, function: Function) !*Obj {
        return self.allocateObj("function", Obj.Data{
            .function = function,
        });
    }

    pub fn makeClosure(self: *Self, closure: Closure) !*Obj {
        return self.allocateObj("closure", Obj.Data{
            .closure = closure,
        });
    }
    pub fn makeUpvalue(self: *Self, location: *value.Value) !*Obj {
        return self.allocateObj("upvalue", Obj.Data{
            .upvalue = ObjUpvalue.init(location),
        });
    }

    pub fn makeNativeFunction(self: *Self, native_function: NativeFunction) !*Obj {
        return self.allocateObj("native_function", Obj.Data{
            .native_function = native_function,
        });
    }

    pub fn makeClass(self: *Self, name: u24) !*Obj {
        return self.allocateObj("class", Obj.Data{
            .class = Class.init(name, self),
        });
    }

    pub fn makeInstance(self: *Self, class: *Class) !*Obj {
        return self.allocateObj("instance", Obj.Data{
            .instance = Instance.init(class, self),
        });
    }

    fn allocateObj(self: *Self, obj_type: []const u8, data: Obj.Data) !*Obj {
        if (config.gc_stress or self.obj_count == self.next_gc) {
            self.collectGarbage();
            self.next_gc = self.obj_count * config.gc_grow_factor;
        }
        const obj = try self.allocator.create(Obj);

        if (config.gc_log) {
            std.debug.print("{*} allocate {} for {s}\n", .{ obj, @sizeOf(Obj), obj_type });
        }

        obj.next = self.heap;
        obj.is_marked = false;
        self.heap = obj;
        obj.data = data;
        self.obj_count += 1;
        return obj;
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
                obj.deinit(self);
            }
        }
    }

    fn printObjectAddresses(self: *Self) void {
        var i: usize = 0;
        var maybe_obj = self.heap;
        while (maybe_obj) |obj| {
            std.debug.print("{d}:{*}\n", .{ i, obj });
            maybe_obj = obj.next;
            i += 1;
        }
    }
};

pub const ObjError = error{
    TypeMismatch,
};

pub const Obj = struct {
    const Self = @This();
    data: Data,
    next: ?*Obj,
    is_marked: bool,

    const Data = union(enum) {
        string: String,
        function: Function,
        native_function: NativeFunction,
        closure: Closure,
        upvalue: ObjUpvalue,
        class: Class,
        instance: Instance,
    };

    pub fn print(self: *Self, writer: anytype) !void {
        switch (self.data) {
            .class => |c| try writer.print("{s}", .{c.name()}),
            .closure => |c| try writer.print("<fn {s}>", .{c.fun().name()}),
            .function => |f| try writer.print("<fn {s}>", .{f.name()}),
            .instance => |i| try writer.print("{s} instance", .{i.class.name()}),
            .native_function => try writer.print("<native fn>", .{}),
            .string => |s| try writer.print("{s}", .{s.chars}),
            .upvalue => try writer.print("upvalue", .{}),
            // .function => |f| try writer.print("<fn {s}:{d}>", .{ f.name(), f.arity }),
            // .native_function => |f| try writer.print("<nfn {s}:{d}>", .{ f.name, f.arity }),
        }
    }

    pub fn isString(self: *const Self) bool {
        return switch (self.data) {
            .string => true,
            else => false,
        };
    }

    pub fn isFunction(self: *const Self) bool {
        return switch (self.data) {
            .function => true,
            else => false,
        };
    }

    pub fn isClosure(self: *const Self) bool {
        return switch (self.data) {
            .closure => true,
            else => false,
        };
    }

    pub fn withString(self: *const Self) ?*const String {
        return switch (self.data) {
            .string => |*s| s,
            else => null,
        };
    }

    pub fn withFunction(self: *const Self) ?*const Function {
        return switch (self.data) {
            .function => |*f| f,
            else => null,
        };
    }

    pub fn withClosure(self: *const Self) ?*const Closure {
        return switch (self.data) {
            .closure => |*c| c,
            else => null,
        };
    }

    fn objType(self: *Self) []const u8 {
        return switch (self.data) {
            .class => "class",
            .closure => "closure",
            .function => "function",
            .instance => "instance",
            .native_function => "native_function",
            .string => "string",
            .upvalue => "upvalue",
        };
    }

    pub fn deinit(self: *Self, heap: *Heap) void {
        if (config.gc_log) {
            std.debug.print("{*} free type {s} ", .{ self, self.objType() });
            self.print(std.io.getStdErr().writer()) catch {};
            std.debug.print("\n", .{});
        }

        switch (self.data) {
            .class => |*c| c.deinit(),
            .closure => |*c| c.deinit(),
            .function => |*f| f.deinit(),
            .instance => |*i| i.deinit(),
            .native_function => |*n| n.deinit(),
            .string => |*s| {
                _ = heap.interned_strings.remove(s.chars);
                s.deinit(heap.allocator);
            },
            .upvalue => {},
        }
        heap.allocator.destroy(self);
        heap.obj_count -= 1;
    }

    pub fn equals(self: *const Self, other: *const Self) bool {
        return self == other;
    }

    pub fn add(self: *const Self, heap: *Heap, other: *const Self) !*Self {
        return switch (self.data) {
            .string => |s| if (other.withString()) |o|
                heap.takeString(try std.mem.concat(heap.allocator, u8, &.{ s.chars, o.chars }))
            else
                ObjError.TypeMismatch,
            else => ObjError.TypeMismatch,
        };
    }

    pub fn mark(self: *Self) void {
        if (!self.is_marked) {
            if (config.gc_log) {
                std.debug.print("{x} mark {s} ", .{ @intFromPtr(self), self.objType() });
                self.print(std.io.getStdErr().writer()) catch {};
                std.debug.print("\n", .{});
            }
            self.is_marked = true;
            switch (self.data) {
                .class => |*c| c.mark(),
                .instance => |*i| i.mark(),
                .closure => |*c| c.mark(),
                .function => |*f| f.mark(),
                .upvalue => |*u| u.mark(),
                else => {},
            }
        }
    }
};

const String = struct {
    const Self = @This();
    chars: []const u8,

    fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.chars);
    }
};

pub const LOCAL_MAX = std.math.maxInt(u8) + 1;

pub const FunctionType = enum {
    Function,
    Script,
};

pub const FunctionError = error{
    TooManyClosureVariables,
    VariableDeclarationSelfReference,
};

pub const Function = struct {
    const Self = @This();
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

    pub fn init(
        heap: *Heap,
        function_type: FunctionType,
        name_index: u24,
        arity: u8,
        enclosing: ?*Function,
    ) Self {
        return Self{
            .arity = arity,
            .chunk = chunk.Chunk.init(heap),
            .local_top = 1,
            .upvalue_top = 0,
            .function_type = function_type,
            .locals = undefined,
            .upvalues = undefined,
            .name_index = name_index,
            .heap = heap,
            .enclosing = enclosing,
        };
    }

    pub fn mark(self: *Self) void {
        for (self.chunk.constants.values.items) |*v| v.mark();
    }

    pub fn name(self: *const Self) []const u8 {
        return self.heap.names.items[self.name_index];
    }

    pub fn deinit(self: *Self) void {
        self.chunk.deinit();
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

pub const NativeFn = *const fn (heap: *Heap, arg_count: u8, args: []value.Value) types.InterpreterError!value.Value;

pub const NativeFunction = struct {
    const Self = @This();
    call: NativeFn,
    name: []const u8,
    arity: u8,

    pub fn init(name: []const u8, arity: u8, native_function: NativeFn) Self {
        return Self{
            .call = native_function,
            .name = name,
            .arity = arity,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

pub const Closure = struct {
    const Self = @This();
    function: *Obj,
    slots: []*Obj,
    heap: *Heap,

    pub fn init(function: *Obj, heap: *Heap) !Self {
        return Self{
            .function = function,
            .slots = try heap.allocator.alloc(*Obj, function.data.function.upvalue_top),
            .heap = heap,
        };
    }

    fn deinit(self: *Self) void {
        self.heap.allocator.free(self.slots);
    }

    pub fn fun(self: *const Self) *Function {
        return &self.function.data.function;
    }

    fn mark(self: *Self) void {
        self.function.mark();
        for (self.slots) |slot| slot.mark();
    }
};

const ObjUpvalue = struct {
    const Self = @This();
    location: *value.Value,
    closed: value.Value,
    next: ?*Obj,

    fn init(location: *value.Value) Self {
        return Self{
            .location = location,
            .next = null,
            .closed = value.nil_val,
        };
    }

    fn mark(self: *Self) void {
        self.location.mark();
    }
};

const Class = struct {
    const Self = @This();
    name_index: u24,
    heap: *Heap,

    fn init(name_index: u24, heap: *Heap) Self {
        return Self{
            .name_index = name_index,
            .heap = heap,
        };
    }

    pub fn name(self: *const Self) []const u8 {
        return self.heap.names.items[self.name_index];
    }

    fn mark(self: *Self) void {
        _ = self;
    }

    fn deinit(self: *Self) void {
        _ = self;
    }
};

pub const Instance = struct {
    const Self = @This();
    class: *Class,
    fields: std.AutoHashMap(u24, value.Value),
    cached_property: u24,

    fn init(class: *Class, heap: *Heap) Self {
        return Self{
            .class = class,
            .fields = std.AutoHashMap(u24, value.Value).init(heap.allocator),
            .cached_property = std.math.maxInt(u24), // Invalid initial value
        };
    }

    fn mark(self: *Self) void {
        var field_iterator = self.fields.iterator();
        while (field_iterator.next()) |entry| entry.value_ptr.mark();
        self.class.mark();
    }

    fn deinit(self: *Self) void {
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
};
