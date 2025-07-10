const std = @import("std");

pub const Value = f64;

// The book uses a clever trick to store non-numeric values inside a double.
// A double-precision float is "Not a Number" (NaN) if all of its exponent bits are set.
// The remaining 52 bits (the fraction) can be used to store other data.
// We can create a quiet NaN (QNAN) by setting the most significant bit of the fraction.
const QNAN = 0x7ffc000000000000;
const SIGN_BIT = 0x8000000000000000;

// We'll use the lowest 3 bits of the fraction to tag our non-numeric types.
const TAG_NIL = 1;
const TAG_FALSE = 2;
const TAG_TRUE = 3;

pub const NIL_VAL: Value = @bitCast(@as(u64, QNAN | TAG_NIL));
pub const FALSE_VAL: Value = @bitCast(@as(u64, QNAN | TAG_FALSE));
pub const TRUE_VAL: Value = @bitCast(@as(u64, QNAN | TAG_TRUE));

pub fn bool_val(b: bool) Value {
    return if (b) TRUE_VAL else FALSE_VAL;
}

pub fn number_val(n: f64) Value {
    return n;
}

pub fn as_bool(v: Value) bool {
    return values_equal(v, TRUE_VAL);
}

pub fn as_number(v: Value) f64 {
    return v;
}

pub fn is_bool(v: Value) bool {
    return (@as(u64, @bitCast(v)) & @as(u64, @bitCast(FALSE_VAL))) == @as(u64, @bitCast(FALSE_VAL));
}

pub fn is_nil(v: Value) bool {
    return values_equal(v, NIL_VAL);
}

pub fn is_number(v: Value) bool {
    // If it's not a NaN, it's a number.
    return (@as(u64, @bitCast(v)) & QNAN) != QNAN;
}

pub fn values_equal(a: Value, b: Value) bool {
    if (is_number(a) and is_number(b)) {
        return as_number(a) == as_number(b);
    }
    return @as(u64, @bitCast(a)) == @as(u64, @bitCast(b));
}

pub fn print(value: Value) void {
    if (is_bool(value)) {
        std.debug.print("{any}", .{as_bool(value)});
    } else if (is_nil(value)) {
        std.debug.print("nil", .{});
    } else if (is_number(value)) {
        std.debug.print("{d}", .{as_number(value)});
    }
}

pub const ValueArray = struct {
    values: std.ArrayList(Value),

    pub fn init(allocator: std.mem.Allocator) ValueArray {
        return .{
            .values = std.ArrayList(Value).init(allocator),
        };
    }

    pub fn deinit(self: *ValueArray) void {
        self.values.deinit();
    }

    pub fn write(self: *ValueArray, value: Value) !void {
        try self.values.append(value);
    }
};