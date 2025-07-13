const std = @import("std");
const zlox = @import("root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var vm = zlox.vm.VM.init(allocator);
    defer vm.deinit();

    var chk = zlox.chunk.Chunk.init(allocator);
    defer chk.deinit();

    const result = vm.interpret("\"hello\" + \", \" + \"world\"", &chk) catch |err| {
        std.debug.print("Interpret error: {any}\n", .{err});
        return;
    };

    zlox.value.print(result);
    std.debug.print("\n", .{});
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
