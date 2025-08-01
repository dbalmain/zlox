# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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