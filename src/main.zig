const std = @import("std");
const config = @import("config");
const zlox = @import("root.zig");
const debug = @import("debug.zig");
const VM = @import("vm.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    std.debug.print("# Challenge 1 - More arithmetic expressions\n", .{});

    {
        // Example 1a: 1 * 2 + 3
        std.debug.print("1 * 2 + 3 = ", .{});
        var chk1a = zlox.chunk.Chunk.init(allocator);
        defer chk1a.deinit();
        try chk1a.writeConstant(1, 1);
        try chk1a.writeConstant(2, 1);
        try chk1a.writeCode(.Multiply, 1);
        try chk1a.writeConstant(3, 1);
        try chk1a.writeCode(.Add, 1);
        try chk1a.writeCode(.Return, 1);
        var vm = VM.VM.init(&chk1a, allocator);
        defer vm.deinit();
        try vm.run();
    }

    {
        // Example 1b: 1 + 2 * 3
        std.debug.print("1 + 2 * 3 = ", .{});
        var chk1b = zlox.chunk.Chunk.init(allocator);
        defer chk1b.deinit();
        try chk1b.writeConstant(1, 1);
        try chk1b.writeConstant(2, 1);
        try chk1b.writeConstant(3, 1);
        try chk1b.writeCode(.Multiply, 1);
        try chk1b.writeCode(.Add, 1);
        try chk1b.writeCode(.Return, 1);
        var vm = VM.VM.init(&chk1b, allocator);
        defer vm.deinit();
        try vm.run();
    }

    {
        // Example 1c: 3 - 2 - 1
        std.debug.print("3 - 2 - 1 = ", .{});
        var chk1c = zlox.chunk.Chunk.init(allocator);
        defer chk1c.deinit();
        try chk1c.writeConstant(3, 1);
        try chk1c.writeConstant(2, 1);
        try chk1c.writeCode(.Subtract, 1);
        try chk1c.writeConstant(1, 1);
        try chk1c.writeCode(.Subtract, 1);
        try chk1c.writeCode(.Return, 1);
        var vm = VM.VM.init(&chk1c, allocator);
        defer vm.deinit();
        try vm.run();
    }

    {
        // Example 1d: 1 + 2 * 3 - 4 / -5
        std.debug.print("1 + 2 * 3 - 4 / -5 = ", .{});
        var chk1d = zlox.chunk.Chunk.init(allocator);
        defer chk1d.deinit();
        try chk1d.writeConstant(1, 1);
        try chk1d.writeConstant(2, 1);
        try chk1d.writeConstant(3, 1);
        try chk1d.writeCode(.Multiply, 1);
        try chk1d.writeCode(.Add, 1);
        try chk1d.writeConstant(4, 1);
        try chk1d.writeCode(.Subtract, 1);
        try chk1d.writeConstant(5, 1);
        try chk1d.writeCode(.Negate, 1);
        try chk1d.writeCode(.Divide, 1);
        try chk1d.writeCode(.Return, 1);
        var vm = VM.VM.init(&chk1d, allocator);
        defer vm.deinit();
        try vm.run();
    }

    {
        std.debug.print("\n# Challenge 2 - Expression without Negate\n", .{});

        // Challenge 2: 4 - 3 * (0 - 2) compiled without using negate
        std.debug.print("4 - 3 * (0 - 2) = ", .{});
        var chk2 = zlox.chunk.Chunk.init(allocator);
        defer chk2.deinit();
        try chk2.writeConstant(4, 1);
        try chk2.writeConstant(3, 1);
        try chk2.writeConstant(0, 1);
        try chk2.writeConstant(2, 1);
        try chk2.writeCode(.Subtract, 1); // (0 - 2) as subtraction, not negate
        try chk2.writeCode(.Multiply, 1); // 3 * result
        try chk2.writeCode(.Subtract, 1); // 4 - result
        try chk2.writeCode(.Return, 1);
        var vm = VM.VM.init(&chk2, allocator);
        defer vm.deinit();
        try vm.run();
    }
}
