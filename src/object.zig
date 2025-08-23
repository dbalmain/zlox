const std = @import("std");
const chunk = @import("chunk.zig");
const value = @import("value.zig");
const types = @import("types.zig");

pub const Local = struct {
    name_index: u24,
    depth: i8,

    pub fn init(name_index: u24) Local {
        return Local{
            .name_index = name_index,
            .depth = -1,
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
    };

    pub fn print(self: *Self, writer: anytype) !void {
        switch (self.*.data) {
            .string => |s| try writer.print("{s}", .{s.chars}),
            .function => |f| try writer.print("<fn {s}>", .{f.name()}),
            .native_function => try writer.print("<native fn>", .{}),
            // .function => |f| try writer.print("<fn {s}:{d}>", .{ f.name(), f.arity }),
            // .native_function => |f| try writer.print("<nfn {s}:{d}>", .{ f.name, f.arity }),
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

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        switch (self.*.data) {
            .string => |*s| s.deinit(allocator),
            .function => |*f| f.deinit(),
            .native_function => |*n| n.deinit(),
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

pub const Function = struct {
    const Self = @This();
    chunk: chunk.Chunk,
    arity: u8,
    local_top: u9,
    function_type: FunctionType,
    locals: [LOCAL_MAX]Local,
    name_index: u24,
    heap: *Heap,

    pub fn init(heap: *Heap, function_type: FunctionType, name_index: u24, arity: u8) Self {
        return Self{
            .arity = arity,
            .chunk = chunk.Chunk.init(heap),
            .local_top = 1,
            .function_type = function_type,
            .locals = undefined,
            .name_index = name_index,
            .heap = heap,
        };
    }

    pub fn name(self: *const Self) []const u8 {
        return self.heap.names.items[self.name_index];
    }

    pub fn deinit(self: *Self) void {
        self.chunk.deinit();
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
