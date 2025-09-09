# zlox

A Zig implementation of the Lox programming language from Robert Nystrom's "Crafting Interpreters".

This project implements the bytecode virtual machine from Part II of the book, written in Zig for performance and learning purposes.

## 🎯 Major Milestone: Full Test Suite Compatibility

**All 132 applicable tests from the official Crafting Interpreters test suite now pass!** This represents the first chapter where our Zig implementation achieves 100% compatibility with Robert Nystrom's reference implementation.

- ✅ Complete test compatibility with https://github.com/munificent/craftinginterpreters
- ✅ Fixed 27 test failures across error formatting, operators, and runtime behavior
- ✅ Enhanced implementation with 2 tests intentionally ignored due to our optimizations

## Current Status

- **Chapter 29**: Superclasses - ✅ Complete (with SuperInvoke Optimization)
  - Complete inheritance system with `class Derived < Base` syntax and method resolution
  - **Class inheritance**: Classes inherit methods from superclasses with runtime method copying
  - **Super method calls**: `super.method()` syntax for accessing overridden superclass methods
  - **Super keyword support**: Proper scoping of `super` in method closures and nested contexts
  - **SuperInvoke optimization**: Direct super method calls bypassing intermediate bound method creation
    - OpCodes: `SuperInvoke`, `SuperInvokeLong` for optimized super method invocation
    - Performance improvement for super method calls with argument count encoding
    - Fallback to traditional super property access when optimization not applicable
  - **Method inheritance**: Superclass methods copied to subclass for efficient method resolution
  - **Inheritance validation**: Prevents circular inheritance and ensures proper class hierarchy
  - **Enhanced ClassCompiler**: Tracks superclass relationships with `has_super` field for proper compilation
  - **Proper `this` binding**: Inherited methods correctly bind to subclass instances
  - New OpCodes: `Super`, `SuperLong`, `SuperInvoke`, `SuperInvokeLong`, `Inherit` for inheritance support
  - Enhanced object system with superclass method resolution and proper scoping
  - VM integration with inheritance operations and super method binding during class creation
  - Memory management integration with GC marking for inherited method structures

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

# Run with garbage collection stress testing
zig build run -Dgc-stress=true -- script.lox

# Run with detailed GC logging
zig build run -Dgc-log=true -- script.lox

# Run with custom GC growth factor (default: 2)
zig build run -Dgc-grow-factor=3 -- script.lox

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