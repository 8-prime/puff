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
        return .{ .ptr = self, .compressFn = compressFn, .archiveType = @intFromEnum(archive.ArchiveType.plain) };
    }
};

pub const PlainDecompressor = struct {
    fn decompressFn(_: *anyopaque, reader: std.io.AnyReader, start: u64, end: u64, writer: std.io.AnyWriter, allocator: std.mem.Allocator) !void {
        const total_size = end - start;
        const bufferSize: u64 = if (total_size < 1024) total_size else 1024;

        var buffer = try allocator.alloc(u8, bufferSize);
        defer allocator.free(buffer);

        var total_bytes: usize = 0;
        var read_bytes = try reader.readAll(buffer);
        while (read_bytes > 0) {
            try writer.writeAll(buffer[0..read_bytes]);
            total_bytes += read_bytes;
            const remainder = total_size - total_bytes;
            read_bytes = try reader.readAll(buffer[0..remainder]);
        }
    }

    pub fn init() PlainDecompressor {
        return PlainDecompressor{};
    }

    pub fn decompressor(self: *PlainDecompressor) com.Decompressor {
        return .{ .ptr = self, .decompressFn = decompressFn, .archiveType = @intFromEnum(archive.ArchiveType.plain) };
    }
};
