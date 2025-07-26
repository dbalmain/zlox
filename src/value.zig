const std = @import("std");
pub const Value = u64;

pub fn print(value: Value) void {
    std.debug.print("{d}", .{value});
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

    pub fn writeValue(self: *Self, value: Value) !u8 {
        if (self.values.items.len == 256) {
            return ValueError.ValueOverflow;
        }
        try self.values.append(value);
        return @intCast(self.values.items.len - 1);
    }
};
