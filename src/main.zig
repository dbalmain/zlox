const std = @import("std");
const zlox = @import("root.zig");
const debug = @import("debug.zig");

const debug_flag = true;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var vm = zlox.vm.VM.init(allocator);
    defer vm.deinit();

    var chk = zlox.chunk.Chunk.init(allocator);
    defer chk.deinit();

    const program =
        \\if (true) {
        \\    print "if works!";
        \\} else {
        \\    print "else works!";
        \\}
        \\
        \\var i = 0;
        \\while (i < 3) {
        \\    print i;
        \\    i = i + 1;
        \\}
        \\
        \\if (true and false) {
        \\    print "should not print";
        \\} else {
        \\    print "logical and works!";
        \\}
        \\
        \\if (false or true) {
        \\    print "logical or works!";
        \\}
        \\for (var i = 0; i < 10; i = i + 1) {
        \\  print i;
        \\}
    ;

    vm.interpret(program, &chk) catch |err| {
        std.debug.print("Interpret error: {any}\n", .{err});
        return;
    };

    if (debug_flag) {
        debug.disassembleChunk(&chk, "test chunk");
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
