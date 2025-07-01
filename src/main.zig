const std = @import("std");
const zlox = @import("zlox");

pub fn main() !void {
    var vm = zlox.vm.VM.init();
    defer vm.deinit();

    var chunk = zlox.chunk.Chunk.init(std.heap.page_allocator);
    defer chunk.deinit();

    if (!try zlox.compiler.compile("var x = 1;\n// this is a comment\nprint x;", &chunk)) {
        std.debug.print("Compilation failed.\n", .{});
        return;
    }
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