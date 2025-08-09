const std = @import("std");
const object = @import("object.zig");

pub const Value = union(enum) {
    const Self = @This();
    boolean: bool,
    number: f64,
    nil: f64,
    obj: *object.Obj,

    pub fn print(self: *const Self) void {
        switch (self.*) {
            .boolean => |b| std.debug.print("{}", .{b}),
            .number => |n| std.debug.print("{d}", .{n}),
            .nil => std.debug.print("nil", .{}),
            .obj => |o| o.print(),
        }
    }

    pub fn isBool(self: *const Self) bool {
        switch (self.*) {
            .boolean => true,
            else => false,
        }
    }

    pub fn isNumber(self: *const Self) bool {
        switch (self.*) {
            .number => true,
            else => false,
        }
    }

    pub fn isNil(self: *const Self) bool {
        return switch (self.*) {
            .nil => true,
            else => false,
        };
    }

    pub fn isObj(self: *const Self) bool {
        return switch (self.*) {
            .obj => true,
            else => false,
        };
    }

    pub fn isString(self: *const Self) bool {
        return switch (self.*) {
            .obj => |o| o.isString(),
            else => false,
        };
    }

    pub fn isFalsey(self: *const Self) bool {
        return switch (self.*) {
            .boolean => |b| b == false,
            .nil => true,
            else => false,
        };
    }

    pub fn equals(self: *const Self, other: *const Value) bool {
        return switch (self.*) {
            .number => |n| if (other.withNumber()) |o| o == n else false,
            .boolean => |b| if (other.withBoolean()) |o| o == b else false,
            .nil => other.isNil(),
            .obj => |o| if (other.withObject()) |p| o.equals(p) else false,
        };
    }

    pub fn withBoolean(self: *const Self) ?bool {
        return switch (self.*) {
            .boolean => |b| b,
            else => null,
        };
    }

    pub fn withNumber(self: *const Self) ?f64 {
        return switch (self.*) {
            .number => |n| n,
            else => null,
        };
    }

    pub fn withMutableNumber(self: *Self) ?*f64 {
        return switch (self.*) {
            .number => |*n| n,
            else => null,
        };
    }

    pub fn withObject(self: *const Self) ?*object.Obj {
        return switch (self.*) {
            .obj => |o| o,
            else => null,
        };
    }
};

pub const nil_val = Value{ .nil = 0 };
pub const true_val = Value{ .boolean = true };
pub const false_val = Value{ .boolean = false };

pub fn asBoolean(b: bool) Value {
    return Value{ .boolean = b };
}

pub fn asNumber(n: f64) Value {
    return Value{ .number = n };
}

pub fn asObject(o: *object.Obj) Value {
    return Value{ .obj = o };
}

pub const ValueError = error{ValueOverflow};

pub const ValueArray = struct {
    const Self = @This();

    values: std.ArrayList(Value),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .values = std.ArrayList(Value).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.values.deinit();
    }

    pub fn writeValue(self: *Self, value: Value) !u24 {
        try self.values.append(value);
        return @intCast(self.values.items.len - 1);
    }
};
