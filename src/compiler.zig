const std = @import("std");
const scanner = @import("scanner.zig");

const Compiler = struct {
    const Self = @This();
    scanner: scanner.Scanner,

    fn init(source: []const u8) Self {
        return Compiler{
            .scanner = scanner.Scanner.init(source),
        };
    }
};

pub fn compile(source: []const u8) void {
    var compiler = Compiler.init(source);
    var line: u24 = undefined;
    while (true) {
        const token = compiler.scanner.next();
        if (token.line != line) {
            line = token.line;
            std.debug.print("{d:>4} ", .{line});
        } else {
            std.debug.print("   | ", .{});
        }
        std.debug.print("{s:<10} '{s}'\n", .{
            @tagName(token.type),
            token.start[0..token.len],
        });
        if (token.type == .Eof) break;
    }
}
