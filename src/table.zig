const std = @import("std");
const value = @import("value.zig");
const object = @import("object.zig");

pub const Table = struct {
    map: std.StringHashMap(*object.ObjString),

    pub fn init(allocator: std.mem.Allocator) Table {
        return .{
            .map = std.StringHashMap(*object.ObjString).init(allocator),
        };
    }

    pub fn deinit(self: *Table) void {
        self.map.deinit();
    }
};
