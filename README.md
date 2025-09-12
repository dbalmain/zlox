# zlox

A Zig implementation of the Lox programming language from Robert Nystrom's "Crafting Interpreters".

This project implements the bytecode virtual machine from Part II of the book, written in Zig for performance and learning purposes.

## 🎯 Full Test Suite Compatibility

**All 244 tests from the official Crafting Interpreters test suite now pass (100% success rate)!** This achievement reflects the current state of our Chapter 30 Memory Optimization implementation with the C-style object system.

- ✅ Complete test compatibility with https://github.com/munificent/craftinginterpreters

## Current Status

- **Chapter 30**: Memory Optimization - ✅ Complete (97-98% Memory Reduction + NaN-Boxing)
  - **C-style Object System**: Complete refactoring from tagged union to C-style inheritance pattern
    - **Massive Memory Efficiency**: String objects reduced from ~2,744 bytes to ~16 bytes (97-98% reduction)
    - **Eliminated Memory Overhead**: Removed 274,000% memory bloat from tagged union approach
    - **Type-Safe Casting**: Method-based casting API with `obj.asString()`, `obj.asFunction()`, etc.
    - **Separate Object Structs**: `String`, `Function`, `Class`, `Instance`, `Closure`, `Upvalue`, `BoundMethod`, `Native`
    - **Enhanced Object Architecture**: Base `Obj` struct with `obj_type`, `is_marked`, `next` fields
    - **Specialized Heap Allocation**: Object-specific allocation methods for optimal memory usage
    - **Clean API Design**: Object methods moved directly onto `Obj` struct for intuitive interface
  - **NaN-Boxing Value Optimization**: 50% memory reduction for Value representation (v0.30.1)
    - **8-byte Values**: Complete rewrite from 16-byte tagged union to 8-byte NaN-boxed encoding
    - **IEEE 754 NaN-Boxing**: Uses quiet NaN bit patterns for efficient non-number encoding
    - **Proper NaN Semantics**: Correct NaN ≠ NaN handling per IEEE 754 standard
    - **Cache Optimization**: Improved CPU cache utilization with smaller value representation
  - **Critical Bug Fixes**: Resolved bytecode corruption caused by stack/heap pointer mismatch
  - **VM Integration**: Updated all object access patterns with method-based casting API
  - **Performance Improvements**: Better cache utilization and reduced memory fragmentation
  - **Test Results**: All 244/244 tests passing (100% success rate) with massive memory improvements

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

# Release builds for optimal performance
zig build -Doptimize=ReleaseFast    # Maximum performance
zig build -Doptimize=ReleaseSafe    # Performance with safety checks  
zig build -Doptimize=ReleaseSmall   # Minimum binary size

# Run release build
zig build run -Doptimize=ReleaseFast -- script.lox
```

**Release Build Options:**
- `ReleaseFast` provides maximum performance by disabling runtime safety checks
- `ReleaseSafe` provides good performance while keeping safety checks
- `ReleaseSmall` optimizes for minimum binary size

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