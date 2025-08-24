const std = @import("std");

pub const InterpreterError = error{
    RuntimeError,
    StackUnderflow,
    InvalidArgument,
};

pub const CompileError = error{
    CompileError,
    UnexpectedEof,
    ParseError,
    UnexpectedError,
    OutOfMemory,
};

pub const ObjError = error{
    TypeMismatch,
};

pub const ValueError = error{
    ValueOverflow,
};