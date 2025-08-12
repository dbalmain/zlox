# zlox

A Zig implementation of the Lox programming language from Robert Nystrom's "Crafting Interpreters".

This project implements the bytecode virtual machine from Part II of the book, written in Zig for performance and learning purposes.

## Current Status

- **Chapter 21**: Global Variables - ✅ Complete
  - Complete statement system with declaration, assignment, and print statements
  - Global variable storage using efficient `StringArrayHashMap` in VM
  - Variable declarations with `var name = value;` and `var name;` (defaults to nil)
  - Variable assignment with `variable = value` and proper validation
  - Variable access with identifier resolution and undefined variable detection
  - Expression statements with automatic result disposal using Pop instruction
  - Print statements with `print expression;` syntax
  - Advanced assignment validation preventing invalid targets like `1 + 2 = 3`
  - Sophisticated error handling with panic mode and synchronization recovery
  - Clean compiler architecture using state management instead of parameter threading

## Building and Running

```bash
# Build the project
zig build

# Run the REPL (interactive mode)
zig build run

# Run a Lox file
zig build run -- script.lox

# Run with trace output (debug VM execution)
zig build run -Dtrace=true

# Run tests
zig build test
```

## Project Structure

- `src/main.zig` - Main executable entry point with CLI interface and heap management
- `src/scanner.zig` - Lexical analyzer for tokenizing Lox source code
- `src/compiler.zig` - Pratt parser compiler for expressions with precedence handling
- `src/vm.zig` - Virtual machine implementation with object heap integration
- `src/chunk.zig` - Bytecode chunk representation
- `src/value.zig` - Value types and operations with object system support
- `src/object.zig` - Object system with heap management and string operations
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