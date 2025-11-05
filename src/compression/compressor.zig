const std = @import("std");

pub const Compressor = struct {
    ptr: *anyopaque,
    compressFn: *const fn (ptr: *anyopaque, reader: std.io.AnyReader, writer: std.io.AnyWriter, allocator: std.mem.Allocator) anyerror!usize,

    pub fn compress(self: Compressor, reader: std.io.AnyReader, writer: std.io.AnyWriter, allocator: std.mem.Allocator) !usize {
        return self.compressFn(self.ptr, reader, writer, allocator);
    }
};

pub const Decompressor = struct {
    ptr: *anyopaque,
    decompressFn: *const fn (ptr: *anyopaque, reader: std.io.AnyReader, writer: std.io.AnyWriter, allocator: std.mem.Allocator) anyerror!void,

    pub fn decompress(self: Compressor, reader: std.io.AnyReader, writer: std.io.AnyWriter, allocator: std.mem.Allocator) !void {
        return self.decompressFn(self.ptr, reader, writer, allocator);
    }
};
