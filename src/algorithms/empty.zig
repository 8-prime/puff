const std = @import("std");
const com = @import("../compressor.zig");

pub const EmptyCompressor = struct {
    fn compressFn(_: *anyopaque, _: std.io.AnyReader, _: std.io.AnyWriter) anyerror!void {}

    pub fn compressor(self: *EmptyCompressor) com.Compressor {
        return .{ .ptr = self, .compressFn = compressFn };
    }
};
