# zlox

A Zig implementation of the Lox programming language from Robert Nystrom's "Crafting Interpreters".

This project implements the bytecode virtual machine from Part II of the book, written in Zig for performance and learning purposes.

## 🎯 Major Milestone: Full Test Suite Compatibility

**All 132 applicable tests from the official Crafting Interpreters test suite now pass!** This represents the first chapter where our Zig implementation achieves 100% compatibility with Robert Nystrom's reference implementation.

- ✅ Complete test compatibility with https://github.com/munificent/craftinginterpreters
- ✅ Fixed 27 test failures across error formatting, operators, and runtime behavior
- ✅ Enhanced implementation with 2 tests intentionally ignored due to our optimizations

## Current Status

- **Chapter 28**: Methods and Initializers - ✅ Complete (with Invoke Optimization)
  - Complete method system with method definitions, binding, and invocation in classes
  - **Method declarations**: Methods defined within class bodies with proper name resolution and storage
  - **Method binding**: Runtime method binding creating BoundMethod objects for `this` context preservation
  - **Method invocation**: Direct method calls on instances with `instance.method()` syntax
  - **Constructor support**: Special `init` methods for object initialization with automatic return handling
  - **`this` keyword**: Implicit `this` parameter in methods providing access to instance state
  - **Invoke optimization**: Direct method invocation bypassing intermediate bound method creation
    - OpCodes: `Invoke`, `InvokeLong` for optimized method calls with argument count encoding
    - Performance improvement by checking methods before fields in property access
    - Fallback to traditional property access for non-method calls
  - **Method storage**: Class methods stored in AutoHashMap for efficient lookup and inheritance preparation
  - **Constructor semantics**: `init` methods automatically return instance, other methods return `nil` by default
  - **Runtime type safety**: Proper error handling for method calls on non-instance values
  - New OpCodes: `Method`, `MethodLong`, `Invoke`, `InvokeLong` for comprehensive method support
  - Enhanced object system with `BoundMethod` type for method binding and `INIT` constant recognition
  - VM integration with method binding, invocation, and constructor calling during class instantiation
  - Memory management integration with GC marking for bound methods and method storage

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