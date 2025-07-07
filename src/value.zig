const std = @import("std");

pub const Value = f64;

const QNAN = 0x7ffc000000000000;
const SIGN_BIT = 0x8000000000000000;

const TAG_NIL = 1;
const TAG_FALSE = 2;
const TAG_TRUE = 3;

pub const NIL_VAL: Value = @bitCast(@as(u64, QNAN | TAG_NIL));
pub const FALSE_VAL: Value = @bitCast(@as(u64, QNAN | TAG_FALSE));
pub const TRUE_VAL: Value = @bitCast(@as(u64, QNAN | TAG_TRUE));

pub fn is_number(value: Value) bool {
    return (@as(u64, @bitCast(value)) & QNAN) != QNAN;
}

pub fn valuesEqual(a: Value, b: Value) bool {
    return @as(u64, @bitCast(a)) == @as(u64, @bitCast(b));
}

pub fn is_nil(value: Value) bool {
    return valuesEqual(value, NIL_VAL);
}

pub fn is_bool(value: Value) bool {
    return (@as(u64, @bitCast(value)) | 1) == @as(u64, @bitCast(TRUE_VAL));
}

pub fn as_number(value: Value) f64 {
    return value;
}

pub fn as_bool(value: Value) bool {
    return valuesEqual(value, TRUE_VAL);
}

pub fn number_val(value: f64) Value {
    return value;
}

pub fn bool_val(value: bool) Value {
    return if (value) TRUE_VAL else FALSE_VAL;
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

test "value types" {
    const num = number_val(1.2);
    try std.testing.expect(is_number(num));
    try std.testing.expect(!is_bool(num));
    try std.testing.expect(!is_nil(num));
    try std.testing.expect(as_number(num) == 1.2); // This should fail

    const tr = bool_val(true);
    try std.testing.expect(is_bool(tr));
    try std.testing.expect(!is_number(tr));
    try std.testing.expect(as_bool(tr));

    const fls = bool_val(false);
    try std.testing.expect(is_bool(fls));
    try std.testing.expect(!is_number(fls));
    try std.testing.expect(!as_bool(fls));

    const n = NIL_VAL;
    try std.testing.expect(is_nil(n));
    try std.testing.expect(!is_number(n));
    try std.testing.expect(!is_bool(n));
}
