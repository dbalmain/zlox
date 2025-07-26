const std = @import("std");
const zlox = @import("root.zig");
const debug = @import("debug.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    var chk = zlox.chunk.Chunk.init(allocator);
    const byte = try chk.writeConstant(5);
    try chk.writeCode(.Constant, 0);
    try chk.writeByte(byte, 0);
    try chk.writeCode(.Return, 0);
    try debug.disassembleChunk(&chk, "test chunk");
    chk.deinit();
}
