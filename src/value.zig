const std = @import("std");
const object = @import("object.zig");
const types = @import("types.zig");

// NaN-Boxing constants
const SIGN_BIT: u64 = 0x8000000000000000;
const QNAN: u64 = 0x7ffc000000000000;
const TAG_NIL: u64 = 1;
const TAG_FALSE: u64 = 2;
const TAG_TRUE: u64 = 3;

// NaN-Boxed Value representation
pub const Value = extern struct {
    const Self = @This();
    bits: u64,

    // Type checking methods using NaN-Boxing
    pub fn isNumber(self: Self) bool {
        return (self.bits & QNAN) != QNAN;
    }

    pub fn isNil(self: Self) bool {
        return self.bits == (QNAN | TAG_NIL);
    }

    pub fn isBool(self: Self) bool {
        return (self.bits | 1) == (QNAN | TAG_TRUE);
    }

    pub fn isObj(self: Self) bool {
        return (self.bits & (QNAN | SIGN_BIT)) == (QNAN | SIGN_BIT);
    }

    pub fn isString(self: Self) bool {
        if (!self.isObj()) return false;
        const obj = self.asObject();
        return obj.isString();
    }

    pub fn isFalsey(self: Self) bool {
        return self.isNil() or (self.isBool() and !self.asBoolean());
    }

    // Value extraction methods
    pub fn asNumber(self: Self) f64 {
        std.debug.assert(self.isNumber());
        return @bitCast(self.bits);
    }

    pub fn asBoolean(self: Self) bool {
        std.debug.assert(self.isBool());
        return self.bits == (QNAN | TAG_TRUE);
    }

    pub fn asObject(self: Self) *object.Obj {
        std.debug.assert(self.isObj());
        return @ptrFromInt(self.bits & ~(SIGN_BIT | QNAN));
    }

    // Optional extraction methods for compatibility
    pub fn withNumber(self: Self) ?f64 {
        return if (self.isNumber()) self.asNumber() else null;
    }

    pub fn withBoolean(self: Self) ?bool {
        return if (self.isBool()) self.asBoolean() else null;
    }

    pub fn withMutableNumber(self: *Self) ?*f64 {
        // NaN-boxing doesn't support mutable number references
        _ = self;
        return null;
    }

    pub fn withObject(self: Self) ?*object.Obj {
        return if (self.isObj()) self.asObject() else null;
    }

    pub fn withClass(self: Self) ?*object.Class {
        if (!self.isObj()) return null;
        const obj = self.asObject();
        return if (obj.obj_type == .class) object.asClass(obj) else null;
    }

    pub fn withInstance(self: Self) ?*object.Instance {
        if (!self.isObj()) return null;
        const obj = self.asObject();
        return if (obj.obj_type == .instance) object.asInstance(obj) else null;
    }

    pub fn asStringChars(self: Self) []const u8 {
        std.debug.assert(self.isObj());
        const obj = self.asObject();
        std.debug.assert(obj.obj_type == .string);
        return object.asString(obj).chars;
    }

    // Equality comparison
    pub fn equals(self: Self, other: Self) bool {        
        if (self.isObj() and other.isObj()) {
            return self.asObject().equals(other.asObject());
        }
        
        // For numbers, we need special NaN handling
        if (self.isNumber() or other.isNumber()) {
            if (!self.isNumber() or !other.isNumber()) return false;
            const a = self.asNumber();
            const b = other.asNumber();
            // NaN is not equal to anything, including itself
            if (std.math.isNan(a) or std.math.isNan(b)) return false;
            return a == b;
        }
        
        // For non-numbers, non-objects (booleans, nil), compare bits
        return self.bits == other.bits;
    }

    // Printing support
    pub fn print(self: Self, writer: anytype) !void {
        if (self.isNumber()) {
            try writer.print("{d}", .{self.asNumber()});
        } else if (self.isBool()) {
            try writer.print("{}", .{self.asBoolean()});
        } else if (self.isNil()) {
            try writer.print("nil", .{});
        } else if (self.isObj()) {
            try self.asObject().print(writer);
        }
    }

    // Garbage collection support
    pub fn mark(self: Self) void {
        if (self.isObj()) {
            self.asObject().mark();
        }
    }
};

// NaN-Boxed value constructors
pub const nil_val = Value{ .bits = QNAN | TAG_NIL };
pub const true_val = Value{ .bits = QNAN | TAG_TRUE };
pub const false_val = Value{ .bits = QNAN | TAG_FALSE };

pub fn fromBoolean(b: bool) Value {
    return Value{ .bits = QNAN | (if (b) TAG_TRUE else TAG_FALSE) };
}

pub fn fromNumber(n: f64) Value {
    return Value{ .bits = @bitCast(n) };
}

pub fn fromObject(o: *object.Obj) Value {
    return Value{ .bits = SIGN_BIT | QNAN | @intFromPtr(o) };
}

pub const ValueError = types.ValueError;

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
