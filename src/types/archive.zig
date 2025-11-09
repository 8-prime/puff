const std = @import("std");

pub const ArchiveType = enum { plain };
pub const Puff = struct { files: std.ArrayList(PuffEntry), type: ArchiveType };
pub const PuffEntry = struct { relativePath: []const u8, puffedLength: u64, tempStartOffset: u64 };
