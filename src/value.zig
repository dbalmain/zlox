const std = @import("std");

pub const Value = f64;

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

test "init and deinit value array" {
    const allocator = std.testing.allocator;
    var array = ValueArray.init(allocator);
    defer array.deinit();

    try std.testing.expect(array.values.items.len == 0);
}

test "write to value array" {
    const allocator = std.testing.allocator;
    var array = ValueArray.init(allocator);
    defer array.deinit();

    try array.write(1.2);
    try std.testing.expect(array.values.items.len == 1);
    try std.testing.expect(array.values.items[0] == 1.2);
}
