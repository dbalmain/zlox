# zlox

A Zig implementation of the Lox programming language from Robert Nystrom's "Crafting Interpreters".

This project implements the bytecode virtual machine from Part II of the book, written in Zig for performance and learning purposes.

## Current Status

- **Chapter 20**: Hash Tables (String Interning) - ✅ Complete
  - Production-quality string interning using `std.StringHashMap(*Obj)`
  - Significant memory optimization: identical strings share single allocation
  - Lightning-fast O(1) string equality via pointer comparison
  - Smart string creation with `copyString()` and `takeString()` deduplication
  - Seamless integration with existing object system and compiler
  - Memory-efficient interning table cleanup with proper lifecycle management
  - Performance benefits: reduced memory fragmentation and faster operations

- **Chapter 19**: Strings - ✅ Complete
  - Complete string literal support with heap-allocated object system
  - String concatenation with `+` operator and proper memory management
  - String equality comparison and object-based value system
  - Heap management with linked-list object tracking for future garbage collection
  - Extensible object architecture supporting strings and functions via tagged unions
  - Memory ownership semantics with `copyString()` and `takeString()` functions

- **Chapter 18**: Types of Values - ✅ Complete
  - Complete type system with nil, boolean, and number values using tagged unions
  - Type-safe operations with comprehensive runtime type checking
  - Comparison operators (==, !=, <, >, <=, >=) with proper type semantics
  - Logical NOT operator (!) with Lox truthiness semantics
  - Literal compilation for booleans (true, false) and nil values
  - Memory-efficient 16-byte tagged union Value representation

- **Chapter 17**: Compiling Expressions - ✅ Complete
  - Complete Pratt parser implementation with precedence climbing
  - Full expression compilation for arithmetic operations (+, -, *, /)
  - Unary minus operator and parenthesized grouping support
  - Integrated compiler-VM pipeline with proper error handling
  - Expression parsing with correct operator precedence and associativity

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