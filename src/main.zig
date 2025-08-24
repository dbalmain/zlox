const std = @import("std");
const config = @import("config");
const zlox = @import("root.zig");
const compiler = @import("compiler.zig");
const object = @import("object.zig");
const debug = @import("debug.zig");
const VM = @import("vm.zig");

const ExitCode = enum(u8) {
    Success = 0,
    Usage = 64,
    DataErr = 65, // Compilation error
    NoInput = 66,
    NoUser = 67,
    NoHost = 68,
    Unavailable = 69,
    Software = 70, // Runtime error
    OsErr = 71,
    OsFile = 72,
    CantCreat = 73,
    IoErr = 74, // File I/O error
    TempFail = 75,
    Protocol = 76,
    NoPerm = 77,
    Config = 78,
};

fn exitWithError(comptime message: []const u8, code: ExitCode) noreturn {
    if (config.trace) {
        const stderr = std.io.getStdErr().writer();
        stderr.print("{s}\n", .{message}) catch {};
    }
    std.process.exit(@intFromEnum(code));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 10 }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 1) {
        try repl(allocator);
    } else if (args.len == 2) {
        try runFile(allocator, args[1]);
    } else {
        exitWithError("Usage: zlox [path]", .Usage);
    }
}

fn repl(allocator: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    while (true) {
        try stdout.print("> ", .{});

        const line = stdin.readUntilDelimiterAlloc(allocator, '\n', 64 * 1024) catch |err| {
            if (err == error.EndOfStream) {
                try stdout.print("Quitting...\n", .{});
                break;
            }
            continue;
        };
        defer allocator.free(line);
        interpret(allocator, line) catch {};
    }
}

fn runFile(allocator: std.mem.Allocator, file_path: []const u8) !void {
    const max_bytes = 10 * 1024 * 1024; // 10MB
    const file_contents = std.fs.cwd().readFileAlloc(allocator, file_path, max_bytes) catch {
        exitWithError("Error reading file", .IoErr);
    };
    defer allocator.free(file_contents);
    interpret(allocator, file_contents) catch |err| {
        switch (err) {
            error.RuntimeError => exitWithError("Runtime error", .Software),
            error.StackUnderflow => exitWithError("Stack underflow error", .Software),
            error.UnexpectedError => exitWithError("Unexpected failure during compilation", .DataErr),
            error.OutOfMemory => exitWithError("Out of memory", .Software),
            error.CompileError => exitWithError("Compile error", .DataErr),
            error.UnexpectedEof => exitWithError("Unexpected EOF", .DataErr),
            error.ParseError => exitWithError("Parser Error", .DataErr),
            error.InvalidArgument => exitWithError("Invalid argument passed to native function", .Software),
        }
    };
}

fn interpret(allocator: std.mem.Allocator, source: []u8) !void {
    var heap = object.Heap.init(allocator);
    defer heap.deinit();
    const function = try compiler.compile(&heap, source);

    var vm = try VM.VM.init(&heap, function);
    defer vm.deinit();

    return vm.run();
}
