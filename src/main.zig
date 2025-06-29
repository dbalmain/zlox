const std = @import("std");
const zlox = @import("zlox");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var chk = zlox.chunk.Chunk.init(allocator);
    defer chk.deinit();

    try chk.addConstant(1.2);
    const constant_opcode = @intFromEnum(zlox.chunk.OpCode.OpConstant);
    try chk.write(constant_opcode, 123);
    try chk.write(0, 123);

    const return_opcode = @intFromEnum(zlox.chunk.OpCode.OpReturn);
    try chk.write(return_opcode, 123);

    chk.disassemble("test chunk");
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
