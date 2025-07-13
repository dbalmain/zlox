const std = @import("std");
const value = @import("value.zig");

pub const ObjType = enum {
    String,
};

pub const Obj = struct {
    type: ObjType,
    next: ?*Obj,
};

pub const ObjString = struct {
    obj: Obj,
    length: usize,
    chars: []const u8,
    hash: u32,
};

// Safely casts an Obj pointer to an ObjString pointer.
// The safety is ensured by checking the object's type before calling.
pub fn as_string(obj: *Obj) *ObjString {
    return @ptrCast(@alignCast(obj));
}

// Returns the character slice from an ObjString.
pub fn as_string_bytes(obj: *Obj) []const u8 {
    return as_string(obj).chars;
}

// Generic allocator for any object type.
fn allocate_object(allocator: std.mem.Allocator, comptime T: type, obj_type: ObjType, head: *?*Obj) !*T {
    const ptr = try allocator.create(T);
    ptr.obj.type = obj_type;
    ptr.obj.next = head.*;
    head.* = &ptr.obj;
    return ptr;
}

// FNV-1a hash function.
fn hash_string(bytes: []const u8) u32 {
    var hash: u32 = 2166136261;
    for (bytes) |b| {
        hash ^= b;
        hash *%= 16777619;
    }
    return hash;
}

// Creates a new ObjString on the heap, copying the provided characters.
pub fn copy_string(allocator: std.mem.Allocator, bytes: []const u8, head: *?*Obj) !*ObjString {
    // Note: String interning will be added here later.
    const heap_chars = try allocator.alloc(u8, bytes.len);
    @memcpy(heap_chars, bytes);
    return take_string(allocator, heap_chars, bytes.len, head);
}

pub fn take_string(allocator: std.mem.Allocator, chars: []u8, length: usize, head: *?*Obj) !*ObjString {
    var ptr = try allocate_object(allocator, ObjString, .String, head);
    ptr.length = length;
    ptr.chars = chars;
    ptr.hash = hash_string(chars[0..length]);
    return ptr;
}

pub fn deinit_string(allocator: std.mem.Allocator, obj_string: *ObjString) void {
    allocator.free(obj_string.chars);
    allocator.destroy(obj_string);
}

pub fn deinit(allocator: std.mem.Allocator, obj: *Obj) void {
    switch (obj.type) {
        .String => deinit_string(allocator, as_string(obj)),
    }
}

pub fn free_objects(allocator: std.mem.Allocator, head: *?*Obj) void {
    var object_ptr = head.*;
    while (object_ptr) |obj| {
        const next_object = obj.next;
        deinit(allocator, obj);
        object_ptr = next_object;
    }
    head.* = null;
}
