const std = @import("std");
const object = @import("object.zig");
const table = @import("table.zig");

pub const Value = u64;

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

pub const NIL_VAL: Value = QNAN | TAG_NIL;
pub const FALSE_VAL: Value = QNAN | TAG_FALSE;
pub const TRUE_VAL: Value = QNAN | TAG_TRUE;

pub fn bool_val(b: bool) Value {
    return if (b) TRUE_VAL else FALSE_VAL;
}

pub fn number_val(n: f64) Value {
    return @bitCast(n);
}

pub fn object_val(obj: *object.Obj) Value {
    return SIGN_BIT | QNAN | @intFromPtr(obj);
}

pub fn as_bool(v: Value) bool {
    return v == TRUE_VAL;
}

pub fn as_number(v: Value) f64 {
    return @bitCast(v);
}

pub fn as_object(v: Value) *object.Obj {
    return @ptrFromInt(v & ~(@as(u64, SIGN_BIT | QNAN)));
}

pub fn is_bool(v: Value) bool {
    return (v | 1) == TRUE_VAL;
}

pub fn is_nil(v: Value) bool {
    return v == NIL_VAL;
}

pub fn is_number(v: Value) bool {
    // If it's not a NaN, it's a number.
    return (v & QNAN) != QNAN;
}

pub fn is_object(v: Value) bool {
    return (v & (QNAN | SIGN_BIT)) == (QNAN | SIGN_BIT);
}

pub fn is_string(v: Value) bool {
    return is_object(v) and as_object(v).type == .String;
}

pub fn values_equal(a: Value, b: Value) bool {
    if (is_number(a) and is_number(b)) {
        return as_number(a) == as_number(b);
    }
    if (is_object(a) and is_object(b)) {
        const obj_a = as_object(a);
        const obj_b = as_object(b);
        if (obj_a.type == obj_b.type) {
            switch (obj_a.type) {
                .String => return std.mem.eql(u8, object.as_string_bytes(obj_a), object.as_string_bytes(obj_b)),
            }
        } else {
            return false;
        }
    }
    return a == b;
}

pub fn print(value: Value) void {
    if (is_bool(value)) {
        std.debug.print("{any}", .{as_bool(value)});
    } else if (is_nil(value)) {
        std.debug.print("nil", .{});
    } else if (is_number(value)) {
        std.debug.print("{d}", .{as_number(value)});
    } else if (is_object(value)) {
        print_object(value);
    }
}

pub fn print_object(v: Value) void {
    switch (as_object(v).type) {
        .String => std.debug.print("{s}", .{object.as_string_bytes(as_object(v))}),
    }
}

pub fn concatenate(allocator: std.mem.Allocator, a: *object.ObjString, b: *object.ObjString, head: *?*object.Obj, strings: *table.Table(*object.ObjString)) !*object.ObjString {
    const length = a.length + b.length;
    const chars = try allocator.alloc(u8, length);
    @memcpy(chars[0..a.length], a.chars);
    @memcpy(chars[a.length..length], b.chars);
    return object.take_string(allocator, chars, length, head, strings);
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

test "bool_val, is_bool, as_bool" {
    const true_val = bool_val(true);
    try std.testing.expect(is_bool(true_val));
    try std.testing.expect(as_bool(true_val));

    const false_val = bool_val(false);
    try std.testing.expect(is_bool(false_val));
    try std.testing.expect(!as_bool(false_val));
}

test "number_val, is_number, as_number" {
    const num_val = number_val(123.45);
    try std.testing.expect(is_number(num_val));
    try std.testing.expectEqual(123.45, as_number(num_val));
}

test "is_nil" {
    try std.testing.expect(is_nil(NIL_VAL));
    try std.testing.expect(!is_nil(number_val(0)));
}

test "object_val, is_object, as_object, is_string" {
    const allocator = std.testing.allocator;
    var objects: ?*object.Obj = null;
    defer object.free_objects(allocator, &objects);
    var strings = table.Table(*object.ObjString).init(allocator);
    defer strings.deinit();

    const test_string = try object.copy_string(allocator, "test", &objects, &strings);
    const obj_val = object_val(&test_string.obj);

    try std.testing.expect(is_object(obj_val));
    try std.testing.expect(is_string(obj_val));
    try std.testing.expectEqual(test_string, object.as_string(as_object(obj_val)));
}

test "is_number with object" {
    const allocator = std.testing.allocator;
    var objects: ?*object.Obj = null;
    defer object.free_objects(allocator, &objects);
    var strings = table.Table(*object.ObjString).init(allocator);
    defer strings.deinit();

    const test_string = try object.copy_string(allocator, "test", &objects, &strings);
    const obj_val = object_val(&test_string.obj);

    try std.testing.expect(!is_number(obj_val));
}

test "values_equal" {
    // Numbers
    try std.testing.expect(values_equal(number_val(1.0), number_val(1.0)));
    try std.testing.expect(!values_equal(number_val(1.0), number_val(2.0)));

    // Booleans
    try std.testing.expect(values_equal(bool_val(true), bool_val(true)));
    try std.testing.expect(!values_equal(bool_val(true), bool_val(false)));

    // Nil
    try std.testing.expect(values_equal(NIL_VAL, NIL_VAL));
    try std.testing.expect(!values_equal(NIL_VAL, bool_val(false)));

    // Objects (strings)
    const allocator = std.testing.allocator;
    var objects: ?*object.Obj = null;
    defer object.free_objects(allocator, &objects);
    var strings = table.Table(*object.ObjString).init(allocator);
    defer strings.deinit();

    const str1 = try object.copy_string(allocator, "hello", &objects, &strings);
    const str2 = try object.copy_string(allocator, "hello", &objects, &strings);
    const str3 = try object.copy_string(allocator, "world", &objects, &strings);

    try std.testing.expect(values_equal(object_val(&str1.obj), object_val(&str2.obj)));
    try std.testing.expect(!values_equal(object_val(&str1.obj), object_val(&str3.obj)));
}

test "concatenate" {
    const allocator = std.testing.allocator;
    var objects: ?*object.Obj = null;
    defer object.free_objects(allocator, &objects);
    var strings = table.Table(*object.ObjString).init(allocator);
    defer strings.deinit();

    const str1 = try object.copy_string(allocator, "hello", &objects, &strings);
    const str2 = try object.copy_string(allocator, " world", &objects, &strings);

    const concatenated_str = try concatenate(allocator, str1, str2, &objects, &strings);
    try std.testing.expectEqualSlices(u8, "hello world", concatenated_str.chars[0..concatenated_str.length]);
}