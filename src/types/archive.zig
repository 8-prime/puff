const std = @import("std");
pub const Puff = struct { files: std.ArrayList(PuffEntry) };
pub const PuffEntry = struct { relativePath: []const u8, puffedLength: u64, tempStartOffset: u64 };
