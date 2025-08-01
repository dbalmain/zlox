const std = @import("std");
const config = @import("config");
const zlox = @import("root.zig");
const debug = @import("debug.zig");
const VM = @import("vm.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    var chk = zlox.chunk.Chunk.init(allocator);
    // for (0..257) |i| {
    //     try chk.writeConstant(i, i);
    //     try chk.writeCode(.Return, i);
    // }

    try chk.writeConstant(1.2, 1);
    try chk.writeConstant(3.4, 1);
    try chk.writeCode(.Add, 1);
    try chk.writeConstant(2.3, 1);
    try chk.writeConstant(4.8, 1);
    try chk.writeCode(.Subtract, 1);
    try chk.writeCode(.Multiply, 1);
    try chk.writeConstant(5.6, 1);
    try chk.writeCode(.Divide, 1);
    try chk.writeCode(.Negate, 1);
    try chk.writeCode(.Return, 2);
    var vm = VM.VM.init(&chk);
    try vm.run();
    //try debug.disassembleChunk(&chk, "test chunk");
    chk.deinit();
}
