# zlox

A Zig implementation of the Lox programming language from Robert Nystrom's "Crafting Interpreters".

This project implements the bytecode virtual machine from Part II of the book, written in Zig for performance and learning purposes.

## Current Status

- **Chapter 23**: Jumping Back and Forth - ✅ Complete
  - Complete control flow system with if/else statements, while loops, and for loops
  - Advanced jump management with 16-bit encoding supporting reasonable function sizes
  - Logical operators (`and`, `or`) with short-circuit evaluation for optimal performance
  - Control flow statements: `if (condition) statement else statement` with proper scoping
  - Loop constructs: `while (condition) statement` and `for (init; condition; increment) statement`
  - Jump instruction processing with efficient IP manipulation and compact bytecode
  - Critical limitation: 16-bit jump distances limit functions to ~65KB bytecode size
  - New OpCodes: `Jump`, `JumpIfFalse`, `Loop`, `And`, `Or` for comprehensive control flow
  - Perfect integration with local variable system maintaining proper scoping throughout
  - Robust error handling with "Too much code to jump over" detection for large functions

- **Chapter 22**: Local Variables - ✅ Complete
  - Complete block scoping system with `{` and `}` syntax for nested scope management
  - Stack-based local variable storage with O(1) direct indexing for maximum performance
  - Two-tier variable resolution: locals first, then globals with seamless fallback
  - Local variable lifecycle management with proper initialization and cleanup
  - Scope depth tracking supporting 127 nested levels with variable shadowing
  - Advanced error handling: redeclaration detection, self-reference prevention, capacity limits
  - New OpCodes: `GetLocal` and `SetLocal` for direct stack access operations
  - Sophisticated compiler infrastructure with fixed array storage and efficient resolution
  - Performance improvements: local variables significantly faster than global HashMap operations
  - Clean integration maintaining backward compatibility with existing global variable system

- **Chapter 21**: Global Variables - ✅ Complete (with Exercises 1-2)
  - Complete statement system with declaration, assignment, and print statements
  - Optimized variable storage with dedicated indexing system and name deduplication
  - Variable declarations with `var name = value;` and `var name;` (defaults to nil)
  - Variable assignment with `variable = value` and proper validation
  - Variable access with identifier resolution and undefined variable detection
  - Expression statements with automatic result disposal using Pop instruction
  - Print statements with `print expression;` syntax
  - Advanced assignment validation preventing invalid targets like `1 + 2 = 3`
  - Runtime redeclaration checking with clear error messages
  - Sophisticated error handling with panic mode and synchronization recovery
  - Clean compiler architecture using state management instead of parameter threading
  - Performance optimizations: O(1) variable name lookups and reduced memory usage

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