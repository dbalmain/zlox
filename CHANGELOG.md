# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.16.0] - 2025-08-03

### Added
- Chapter 16 - Scanning on Demand implementation
- Complete lexical analyzer (`Scanner` struct) with proper bounds checking using end pointer
- Token types for all Lox language constructs (keywords, operators, literals, punctuation)
- String literal tokenization with escape sequence handling and line tracking
- Number literal tokenization supporting both integers and floating-point values
- Identifier tokenization with keyword recognition using trie-based approach
- Comment handling (single-line `//` comments) 
- Error token generation for invalid characters and unterminated strings
- Command-line interface with REPL and file execution modes
- Standard Unix exit codes via `ExitCode` enum with PascalCase naming
- `exitWithError` helper function for consistent error reporting and process termination

### Changed
- Main function completely rewritten for Chapter 16 CLI interface
- Replaced Chapter 15 challenge demonstrations with proper interpreter entry points
- VM constructor signature changed from `init(chunk, allocator)` to `init(allocator, chunk)`
- Scanner uses pointer-based bounds checking (`start`, `current`, `end` pointers)
- Token structure uses `[*]const u8` for start pointer and `u24` for length and line numbers
- Compiler module added as foundation for future parsing phases

### Technical Details
- Scanner implements on-demand tokenization without pre-processing entire source
- Bounds safety achieved through end pointer comparison instead of source length tracking
- Keyword recognition uses efficient character-by-character matching
- Line number tracking handles newlines in string literals and comments
- Error handling follows book's approach with Error tokens containing message text
- CLI supports both interactive REPL mode and batch file processing

## [0.15.1] - 2025-08-02

### Added
- Chapter 15 Challenge 1: Multiple arithmetic expression demonstrations
  - `1 * 2 + 3` - operator precedence with multiplication first
  - `1 + 2 * 3` - operator precedence with addition deferred
  - `3 - 2 - 1` - left-associative subtraction
  - `1 + 2 * 3 - 4 / -5` - complex expression with multiple operators
- Chapter 15 Challenge 2: Expression compilation without negate operation
  - `4 - 3 * (0 - 2)` implemented using subtraction instead of negate
- `Print` opcode for explicit value output during execution
- Comprehensive main.zig demonstrations with proper scoping and cleanup

### Changed
- VM stack changed from fixed-size array to dynamic `ArrayList(Value)`
- Stack management now uses `clearRetainingCapacity()` for efficient resets
- Improved memory management with proper `init`/`deinit` patterns
- Binary operations now use `comptime` parameter for operator selection
- Negate operation optimized to modify stack top in-place
- Enhanced error handling for stack operations with `StackUnderflow`
- VM initialization now requires allocator parameter

### Technical Details
- Dynamic stack growth eliminates fixed 256-element limitation
- Each challenge demonstration properly scoped with defer cleanup
- Stack operations use ArrayList methods for bounds checking
- Memory-efficient stack reuse between VM executions

## [0.15.0] - 2025-08-01

### Added
- Chapter 15 - Virtual Machine implementation
- Complete stack-based bytecode virtual machine (`VM` struct)
- Arithmetic operations: `Add`, `Subtract`, `Multiply`, `Divide`, `Negate` opcodes
- Stack management with 256-element capacity and overflow protection
- Runtime error handling with `InterpreterError` types
- Binary operations with proper operand ordering (left/right)
- Division by zero error checking
- Configurable execution tracing via build option (`-Dtrace=true`)
- Stack visualization during trace execution
- Line number tracking integration with VM execution

### Changed
- Value type changed from `u64` to `f64` for floating-point arithmetic
- Main function now executes bytecode via VM instead of just disassembling
- Line number types standardized to `u24` throughout codebase
- Build system enhanced with trace configuration option

### Technical Details
- VM uses instruction pointer (`ip`) for bytecode navigation
- Stack pointer (`sp`) manages operand stack with bounds checking
- Binary operations pop two operands, compute result, and push back to stack
- Long constants (24-bit indices) fully supported in VM execution
- Trace mode shows instruction disassembly with line numbers and stack state

## [0.14.1] - 2025-07-27

### Added
- Optimized line number encoding using offset-based skiplist instead of run-length encoding
- Long Constant challenge implementation supporting constants beyond 256 limit
- `ConstantLong` opcode for handling 24-bit constant indices
- Efficient line number tracking with `CodeLine` structure storing chunk offset and line number

### Changed
- Modified `Chunk.writeByte()` to no longer require line parameter
- Updated `Chunk.writeConstant()` to automatically choose between `Constant` and `ConstantLong` opcodes
- Refactored line number storage from `ArrayList(usize)` to `ArrayList(CodeLine)`
- Enhanced disassembler to properly handle both constant instruction types
- Removed 256 constant limit in `ValueArray.writeValue()`

### Technical Details
- Line number encoding now uses skiplist approach: only stores line changes with their chunk offsets
- Constants beyond index 255 use 3-byte encoding (24-bit) via `ConstantLong` instruction
- Disassembler tracks line numbers efficiently during instruction iteration

## [0.14.0] - 2025-07-27

### Added
- Chapter 14 - Chunks of Bytecode implementation
- Basic bytecode chunk structure with opcodes
- Value array for constant storage
- Debug utilities for disassembly
- Initial `Constant` and `Return` opcodes