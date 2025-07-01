const std = @import("std");
const scanner = @import("scanner.zig");
const chunk = @import("chunk.zig");

pub fn compile(source: []const u8, compilingChunk: *const chunk.Chunk) !bool {
    _ = compilingChunk;
    var sc = scanner.Scanner.init(source);
    var line: usize = 0;
    while (true) {
        const token = sc.scanToken();
        if (token.line != line) {
            std.debug.print("{d:4} ", .{token.line});
            line = token.line;
        } else {
            std.debug.print("   | ", .{});
        }
        const slice = token.start[0..token.length];
        std.debug.print("{s} '{s}'\n", .{@tagName(token.type), slice});

        if (token.type == .Eof) {
            break;
        }
    }
    return true;
}