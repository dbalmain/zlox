# zlox

A Zig implementation of the Lox programming language from Robert Nystrom's "Crafting Interpreters".

This project implements the bytecode virtual machine from Part II of the book, written in Zig for performance and learning purposes.

## 🎯 Major Milestone: Full Test Suite Compatibility

**All 132 applicable tests from the official Crafting Interpreters test suite now pass!** This represents the first chapter where our Zig implementation achieves 100% compatibility with Robert Nystrom's reference implementation.

- ✅ Complete test compatibility with https://github.com/munificent/craftinginterpreters
- ✅ Fixed 27 test failures across error formatting, operators, and runtime behavior
- ✅ Enhanced implementation with 2 tests intentionally ignored due to our optimizations

## Current Status

- **Chapter 27**: Classes and Instances - ✅ Complete (with Performance Optimization)
  - Complete object-oriented programming system with classes and instances
  - **Class declarations**: First-class class objects with name resolution and proper scoping
  - **Instance creation**: Runtime instance creation with class constructor calls 
  - **Property access**: Dynamic property get/set operations with `instance.property` syntax
  - **Property cache optimization**: Single-property cache per instance for improved repeated access performance
    - Cache uses `maxInt(u24)` as invalid marker for both hits and misses
    - Significant performance improvement for property-heavy code without memory overhead
    - Cache invalidated and updated on property set operations
  - **Runtime type safety**: Proper error handling for property access on non-instance values
  - New OpCodes: `Class`, `ClassLong`, `GetProperty`, `GetPropertyLong`, `SetProperty`, `SetPropertyLong`
  - Enhanced object system with `Class` and `Instance` types for OOP support
  - VM integration with class creation and instance property operations
  - Comprehensive property management with dynamic field storage using AutoHashMap
  - Memory management integration with GC marking for classes, instances, and their properties

- **Chapter 26**: Garbage Collection - ✅ Complete 
  - Complete mark-and-sweep garbage collection system with automatic memory management
  - **Object-count based GC triggering**: Collection activates when object count reaches threshold or under gc-stress mode
  - **VM pointer approach**: Direct heap-to-VM communication avoiding circular dependencies between heap and VM modules  
  - **Comprehensive root marking**: Stack values, global variables, call frame slots, and open upvalues all properly marked
  - **Object marking with cycle detection**: All object types support marking through `mark()` method with `is_marked` flag
  - **Sweep phase with cleanup**: Unmarked objects automatically freed with proper string interning cleanup
  - **Configurable GC options**:
    - `gc-stress`: Forces GC on every allocation for testing memory management
    - `gc-log`: Enables detailed garbage collection debug logging with allocation/deallocation tracking
    - `gc-grow-factor`: Configurable growth multiplier for GC threshold (default: 2x)
  - **Performance optimizations**: Object-count based triggering more predictable than byte-based approaches
  - **String interning integration**: Proper cleanup of interned strings during sweep phase 
  - **Comprehensive statistics**: GC logging shows objects collected, before/after counts, and next collection threshold
  - **Memory safety**: All object types properly handle marking of referenced objects to prevent premature collection

- **Chapter 25**: Closures - ✅ Complete (with Native Functions)
  - Complete closure system with upvalue capture for lexical scoping
  - **Upvalue management**: Automatic capture of local variables from enclosing scopes
  - **Closure objects**: First-class function values with captured environment
  - **Memory management**: Proper upvalue lifecycle with automatic cleanup
  - **Stack-to-heap conversion**: Upvalues automatically moved to heap when locals go out of scope
  - **Nested closures**: Support for arbitrarily deep closure nesting with proper variable resolution
  - **Performance optimization**: Direct stack access for captured locals until scope exit
  - **Native Functions**: Built-in functions for common operations
    - `clock()` - Returns current timestamp in milliseconds
    - `sqrt(n)` - Square root of number (errors for negative values)
    - `sin(n)`, `cos(n)` - Trigonometric functions
    - `string(value)` - Converts any value to its string representation
  - New OpCodes: `GetUpvalue`, `SetUpvalue`, `CloseUpvalue`, `Closure`, `ClosureLong` for closure operations
  - Enhanced object system with `Closure` and `ObjUpvalue` types for closure representation
  - Advanced compiler with upvalue resolution supporting local and inherited upvalue chains
  - VM integration with open upvalue tracking and automatic closure at scope boundaries
  - Comprehensive closure creation supporting both simple functions and closures with captured variables

- **Chapter 23**: Jumping Back and Forth - ✅ Complete (with Exercises)
  - Complete control flow system with if/else statements, while loops, and for loops
  - **Chapter 23 Exercises**: Advanced control flow with continue, break, and switch statements
  - **Continue statement**: Loop continuation with proper context tracking and nested loop support
  - **Break statement**: Innovative two-jump VM architecture for efficient loop exit
  - **Switch statement**: Sequential case matching with dynamic expressions and type safety
  - Advanced jump management with 16-bit encoding supporting reasonable function sizes
  - Logical operators (`and`, `or`) with short-circuit evaluation for optimal performance
  - Control flow statements: `if (condition) statement else statement` with proper scoping
  - Loop constructs: `while (condition) statement` and `for (init; condition; increment) statement`
  - Jump instruction processing with efficient IP manipulation and compact bytecode
  - Critical limitation: 16-bit jump distances limit functions to ~65KB bytecode size
  - New OpCodes: `Jump`, `JumpIfFalse`, `Loop`, `And`, `Or`, `Break`, `Matches` for comprehensive control flow
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