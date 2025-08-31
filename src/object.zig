const std = @import("std");
const chunk = @import("chunk.zig");
const value = @import("value.zig");
const types = @import("types.zig");

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

    pub fn init(allocator: std.mem.Allocator) Heap {
        return Heap{
            .allocator = allocator,
            .heap = null,
            .interned_strings = std.StringHashMap(*Obj).init(allocator),
            .names = std.ArrayList([]const u8).init(allocator),
            .name_map = std.StringHashMap(u24).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var obj = self.heap;
        while (obj) |o| {
            obj = o.next;
            o.deinit(self.allocator);
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
        const obj = try self.allocator.create(Obj);
        obj.next = self.heap;
        self.heap = obj;
        obj.data = Obj.Data{
            .string = String{ .chars = chars },
        };
        try self.interned_strings.put(chars, obj);

        return obj;
    }

    pub fn makeFunction(self: *Self, function: Function) !*Obj {
        const obj = try self.allocator.create(Obj);
        obj.next = self.heap;
        self.heap = obj;
        obj.data = Obj.Data{
            .function = function,
        };

        return obj;
    }

    pub fn makeClosure(self: *Self, closure: Closure) !*Obj {
        const obj = try self.allocator.create(Obj);
        obj.next = self.heap;
        self.heap = obj;
        obj.data = Obj.Data{
            .closure = closure,
        };

        return obj;
    }
    pub fn makeUpvalue(self: *Self, location: *value.Value) !*Obj {
        const obj = try self.allocator.create(Obj);
        obj.next = self.heap;
        self.heap = obj;
        obj.data = Obj.Data{
            .upvalue = ObjUpvalue.init(location),
        };

        return obj;
    }

    pub fn makeNativeFunction(self: *Self, native_function: NativeFunction) !*Obj {
        const obj = try self.allocator.create(Obj);
        obj.next = self.heap;
        self.heap = obj;
        obj.data = Obj.Data{
            .native_function = native_function,
        };

        return obj;
    }
};

pub const ObjError = error{
    TypeMismatch,
};

pub const Obj = struct {
    const Self = @This();
    data: Data,
    next: ?*Obj,

    const Data = union(enum) {
        string: String,
        function: Function,
        native_function: NativeFunction,
        closure: Closure,
        upvalue: ObjUpvalue,
    };

    pub fn print(self: *Self, writer: anytype) !void {
        switch (self.*.data) {
            .string => |s| try writer.print("{s}", .{s.chars}),
            .function => |f| try writer.print("<fn {s}>", .{f.name()}),
            .native_function => try writer.print("<native fn>", .{}),
            // .function => |f| try writer.print("<fn {s}:{d}>", .{ f.name(), f.arity }),
            // .native_function => |f| try writer.print("<nfn {s}:{d}>", .{ f.name, f.arity }),
            .closure => |c| try writer.print("<fn {s}>", .{c.function.name()}),
            .upvalue => try writer.print("upvalue", .{}),
        }
    }

    pub fn isString(self: *const Self) bool {
        return switch (self.*.data) {
            .string => true,
            else => false,
        };
    }

    pub fn isFunction(self: *const Self) bool {
        return switch (self.*.data) {
            .function => true,
            else => false,
        };
    }

    pub fn isClosure(self: *const Self) bool {
        return switch (self.*.data) {
            .closure => true,
            else => false,
        };
    }

    pub fn withString(self: *const Self) ?*const String {
        return switch (self.*.data) {
            .string => |*s| s,
            else => null,
        };
    }

    pub fn withFunction(self: *const Self) ?*const Function {
        return switch (self.*.data) {
            .function => |*f| f,
            else => null,
        };
    }

    pub fn withClosure(self: *const Self) ?*const Closure {
        return switch (self.*.data) {
            .closure => |*c| c,
            else => null,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        switch (self.*.data) {
            .string => |*s| s.deinit(allocator),
            .function => |*f| f.deinit(),
            .native_function => |*n| n.deinit(),
            .closure => |*c| c.deinit(),
            .upvalue => {},
        }
        allocator.destroy(self);
    }

    pub fn equals(self: *const Self, other: *const Self) bool {
        return self == other;
    }

    pub fn add(self: *const Self, heap: *Heap, other: *const Self) !*Self {
        return switch (self.*.data) {
            .string => |s| if (other.withString()) |o|
                heap.takeString(try std.mem.concat(heap.allocator, u8, &.{ s.chars, o.chars }))
            else
                ObjError.TypeMismatch,
            else => ObjError.TypeMismatch,
        };
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

pub const NativeFn = *const fn (arg_count: u8, args: []value.Value) types.InterpreterError!value.Value;

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
    function: Function,
    slots: []*Obj,
    heap: *Heap,

    pub fn init(function: Function, heap: *Heap) !Self {
        return Self{
            .function = function,
            .slots = try heap.allocator.alloc(*Obj, function.upvalue_top),
            .heap = heap,
        };
    }

    pub fn deinit(self: *Self) void {
        self.heap.allocator.free(self.slots);
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
};
