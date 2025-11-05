const std = @import("std");
const com = @import("compressor.zig");
const archive = @import("../types/archive.zig");

pub const PlainCompressor = struct {
    fn compressFn(_: *anyopaque, reader: std.io.AnyReader, writer: std.io.AnyWriter, allocator: std.mem.Allocator) !usize {
        var buffer = try allocator.alloc(u8, 1024);
        defer allocator.free(buffer);
        var total_bytes: usize = 0;
        var read_bytes = try reader.readAll(buffer);
        while (read_bytes > 0) {
            try writer.writeAll(buffer[0..read_bytes]);
            total_bytes += read_bytes;
            read_bytes = try reader.readAll(buffer);
        }
        return total_bytes;
    }

    pub fn compressor(self: *PlainCompressor) com.Compressor {
        return .{ .ptr = self, .compressFn = compressFn };
    }
};
