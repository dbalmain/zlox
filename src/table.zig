const std = @import("std");

pub fn Table(comptime V: type) type {
    return struct {
        map: std.StringHashMap(V),

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .map = std.StringHashMap(V).init(allocator),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.map.deinit();
        }
    };
}