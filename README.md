# zlox

A Zig implementation of the Lox programming language from Robert Nystrom's "Crafting Interpreters".

This project implements the bytecode virtual machine from Part II of the book, written in Zig for performance and learning purposes.

## Current Status

- **Chapter 14**: Chunks of Bytecode - Basic bytecode representation and virtual machine foundation

## Building and Running

```bash
# Build the project
zig build

# Run the interpreter
zig build run

# Run with a file
zig build run -- script.lox

# Run tests
zig build test
```

## Project Structure

- `src/main.zig` - Main executable entry point
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