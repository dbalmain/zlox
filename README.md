# zlox

A Zig implementation of the Lox programming language from Robert Nystrom's "Crafting Interpreters".

This project implements the bytecode virtual machine from Part II of the book, written in Zig for performance and learning purposes.

## Current Status

- **Chapter 15**: A Virtual Machine - ✅ Complete
  - Stack-based bytecode virtual machine with arithmetic operations
  - Runtime execution of bytecode with proper error handling
  - Configurable trace mode for debugging VM execution
  - Support for floating-point arithmetic and stack management

## Building and Running

```bash
# Build the project
zig build

# Run the interpreter
zig build run

# Run with trace output (debug VM execution)
zig build run -Dtrace=true

# Run tests
zig build test
```

## Project Structure

- `src/main.zig` - Main executable entry point
- `src/vm.zig` - Virtual machine implementation
- `src/chunk.zig` - Bytecode chunk representation
- `src/value.zig` - Value types and operations
- `src/debug.zig` - Disassembler and debugging utilities
- `src/root.zig` - Library module exports
- `build.zig` - Zig build configuration

## Learning Goals

This implementation focuses on:
- Understanding bytecode virtual machines
- Zig language features and idioms
- Memory management in language implementations
- Performance-oriented interpreter design

## Reference

Based on "Crafting Interpreters" by Robert Nystrom - https://craftinginterpreters.com/