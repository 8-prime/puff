const std = @import("std");

pub const Compressor = struct {
    ptr: *anyopaque,
    compressFn: *const fn (ptr: *anyopaque, reader: std.io.AnyReader, writer: std.io.AnyWriter) anyerror!void,

    pub fn compress(self: Compressor, reader: std.io.AnyReader, writer: std.io.AnyWriter) !void {
        return self.compressFn(self.ptr, reader, writer);
    }
};
