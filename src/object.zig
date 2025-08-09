const std = @import("std");

pub const Heap = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    heap: ?*Obj,

    pub fn init(allocator: std.mem.Allocator) Heap {
        return Heap{
            .allocator = allocator,
            .heap = null,
        };
    }

    pub fn deinit(self: *Self) void {
        var obj = self.heap;
        while (obj) |o| {
            obj = o.next;
            o.deinit(self.allocator);
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

    const Data = union(enum) {
        string: String,
        function: Function,
    };

    pub fn print(self: *Self) void {
        switch (self.*.data) {
            .string => |s| std.debug.print("{s}", .{s.chars}),
            .function => std.debug.print("function", .{}),
        }
    }

    pub fn isString(self: *const Self) bool {
        return switch (self.*.data) {
            .string => true,
            else => false,
        };
    }

    pub fn withString(self: *const Self) ?String {
        return switch (self.*.data) {
            .string => |s| s,
            else => null,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        switch (self.*.data) {
            .string => |*s| s.deinit(allocator),
            else => {},
        }
        allocator.destroy(self);
    }

    pub fn equals(self: *const Self, other: *const Self) bool {
        return switch (self.*.data) {
            .string => |s| if (other.withString()) |o| std.mem.eql(u8, s.chars, o.chars) else false,
            .function => false,
        };
    }

    pub fn add(self: *const Self, heap: *Heap, other: *const Self) !*Self {
        return switch (self.*.data) {
            .string => |s| if (other.withString()) |o|
                takeString(heap, try std.mem.concat(heap.allocator, u8, &.{ s.chars, o.chars }))
            else
                ObjError.TypeMismatch,
            else => ObjError.TypeMismatch,
        };
    }
};

pub fn copyString(heap: *Heap, str: []const u8) !*Obj {
    return takeString(heap, try heap.allocator.dupe(u8, str));
}

pub fn takeString(heap: *Heap, chars: []const u8) !*Obj {
    const obj = try heap.allocator.create(Obj);
    obj.next = heap.heap;
    heap.heap = obj;
    obj.data = Obj.Data{
        .string = String{ .chars = chars },
    };

    return obj;
}

const String = struct {
    const Self = @This();
    chars: []const u8,

    fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.chars);
    }
};

const Function = struct {
    const Self = @This();

    fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};
