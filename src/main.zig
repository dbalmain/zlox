const std = @import("std");
const zlox = @import("root.zig");
const debug = @import("debug.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    var chk = zlox.chunk.Chunk.init(allocator);
    for (0..257) |i| {
        try chk.writeConstant(i, i);
        try chk.writeCode(.Return, i);
    }

    try chk.writeCode(.Return, 1);
    try chk.writeCode(.Return, 1);
    try chk.writeCode(.Return, 2);
    try chk.writeCode(.Return, 2);
    try debug.disassembleChunk(&chk, "test chunk");
    chk.deinit();
}
